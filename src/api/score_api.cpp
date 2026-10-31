#include "api/score_api.hpp"

#include "api/host_api.hpp"
#include "cart/save_store.hpp"
#include "core/log.hpp"

#include <sol/sol.hpp>

#include <algorithm>
#include <string>
#include <vector>

namespace phos {

namespace {

constexpr int kDefaultMax = 5;
constexpr int kMaxScores = 20;

/// 一个排行榜实例：固定容量、降序、写进当前卡带存档的指定键。
/// 存档不可用（manifest 没声明 save）时只在内存里工作——卡带不该为此写分支。
struct ScoreTable {
    HostContext* host = nullptr;
    int capacity = kDefaultMax;
    std::string key = "scores";
    std::vector<int> values;

    bool available() const { return host != nullptr && host->save != nullptr; }

    void load() {
        values.clear();
        if (!available()) return;
        if (const auto raw = host->save->get(key)) {
            size_t start = 0;
            while (start <= raw->size()) {
                const size_t comma = raw->find(',', start);
                const std::string piece =
                    raw->substr(start, comma == std::string::npos ? std::string::npos : comma - start);
                if (!piece.empty()) {
                    try {
                        const long long parsed = std::stoll(piece);
                        if (parsed >= 0 && parsed <= 0x7fffffff)
                            values.push_back(static_cast<int>(parsed));
                    } catch (...) {
                        // 存档是不可信输入：坏项跳过，别让一个字符毁掉整张榜
                    }
                }
                if (comma == std::string::npos) break;
                start = comma + 1;
            }
        }
        std::sort(values.begin(), values.end(), std::greater<int>());
        if (static_cast<int>(values.size()) > capacity) values.resize(capacity);
    }

    void save() const {
        if (!available()) return;
        std::string out;
        for (size_t i = 0; i < values.size(); ++i) {
            if (i > 0) out += ',';
            out += std::to_string(values[static_cast<size_t>(i)]);
        }
        if (!host->save->set(key, out)) log::warn("phos.score: cannot persist '" + key + "'");
    }

    /// 插入并返回名次（1 基）；没进榜返回 0
    int add(int value) {
        if (value < 0 || capacity <= 0) return 0;
        values.push_back(value);
        std::sort(values.begin(), values.end(), std::greater<int>());
        if (static_cast<int>(values.size()) > capacity) values.resize(capacity);
        const auto it = std::find(values.begin(), values.end(), value);
        if (it == values.end()) return 0;
        save();
        return static_cast<int>(std::distance(values.begin(), it)) + 1;
    }

    int best() const { return values.empty() ? 0 : values.front(); }
};

std::string clean_key(const std::string& wanted) {
    if (wanted.empty() || wanted.size() > 64) return "scores";
    if (wanted.find('=') != std::string::npos || wanted.find('\n') != std::string::npos)
        return "scores";
    return wanted;
}

} // namespace

void register_score_api(sol::state& lua, HostContext& host) {
    sol::table phos = lua["phos"];
    sol::table score = phos.create_named("score");

    lua.new_usertype<ScoreTable>(
        "phos.Score", sol::no_constructor,
        "available", [](const ScoreTable& t) { return t.available(); },
        "capacity", [](const ScoreTable& t) { return t.capacity; },
        "best", [](const ScoreTable& t) { return t.best(); },
        "list",
        [](const ScoreTable& t, sol::this_state ts) {
            sol::state_view view(ts);
            sol::table out = view.create_table();
            for (size_t i = 0; i < t.values.size(); ++i)
                out[static_cast<int>(i) + 1] = t.values[i];
            return out;
        },
        "add", [](ScoreTable& t, int value) { return t.add(value); },
        "clear",
        [](ScoreTable& t) {
            t.values.clear();
            t.save();
        },
        "key", [](const ScoreTable& t) { return t.key; });

    /// phos.score.new{ max = 5, key = "scores" }：构造时自动从存档装载
    score["new"] = [&host](sol::optional<sol::table> opts) {
        ScoreTable table;
        table.host = &host;
        if (opts) {
            sol::object max = (*opts)["max"];
            if (max.is<int>()) table.capacity = max.as<int>();
            if (max.is<double>()) table.capacity = static_cast<int>(max.as<double>());
            sol::object key = (*opts)["key"];
            if (key.is<std::string>()) table.key = clean_key(key.as<std::string>());
        }
        table.capacity = std::clamp(table.capacity, 1, kMaxScores);
        table.load();
        return table;
    };

    /// 便捷：取当前卡带某个榜的前 N 名（等价 new{...}:list()），不写盘
    score["top"] = [&host, &lua](sol::optional<int> count, sol::optional<std::string> key) {
        ScoreTable table;
        table.host = &host;
        table.capacity = std::clamp(count.value_or(kDefaultMax), 1, kMaxScores);
        table.key = clean_key(key.value_or("scores"));
        table.load();
        sol::table out = lua.create_table();
        for (size_t i = 0; i < table.values.size(); ++i)
            out[static_cast<int>(i) + 1] = table.values[i];
        return out;
    };
}

} // namespace phos

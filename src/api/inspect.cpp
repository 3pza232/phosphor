#include "api/inspect.hpp"

#include "agent/json_lite.hpp"

#include <sol/sol.hpp>

#include <set>
#include <sstream>

namespace phos {

namespace {

/// 是不是"纯数组"：键恰好是 1..n 的连续整数。
/// 数组要按 1..n 的顺序展开——Lua 的 next 遍历顺序不保证，直接迭代会打乱元素次序
bool is_sequence(const sol::table& table) {
    const size_t n = table.size();
    if (n == 0) return false;  // 空表当对象输出（{} 与 [] 对读的人来说一样）
    size_t counted = 0;
    for (const auto& entry : table) {
        if (!entry.first.is<long long>()) return false;
        ++counted;
    }
    return counted == n;
}

/// 循环引用保护：记录正在展开的表
void write_value(std::ostringstream& out, const sol::object& value, int depth,
                 std::set<const void*>& seen) {
    switch (value.get_type()) {
        case sol::type::number: {
            const double number = value.as<double>();
            // 整数值不带小数点，便于 agent 直接当作整数使用
            if (number == static_cast<double>(static_cast<long long>(number)))
                out << static_cast<long long>(number);
            else
                out << number;
            return;
        }
        case sol::type::string: return void(out << json::quote(value.as<std::string>()));
        case sol::type::boolean: return void(out << (value.as<bool>() ? "true" : "false"));
        case sol::type::table: {
            const sol::table table = value.as<sol::table>();
            const void* identity = table.pointer();
            if (depth <= 0 || (identity && seen.count(identity))) {
                out << "{\"__table\":" << table.size() << "}";
                return;
            }
            if (identity) seen.insert(identity);

            // 纯数组 → JSON 数组，按 1..n 展开。少了这一步，卡带 debug_state 里的
            // "幽灵列表"会变成 {"1":…,"2":…} 的伪数组，agent 得先猜出它是 1 基的
            if (is_sequence(table)) {
                out << "[";
                const size_t n = table.size();
                for (size_t i = 1; i <= n; ++i) {
                    if (i > 1) out << ",";
                    write_value(out, table[i], depth - 1, seen);
                }
                out << "]";
                if (identity) seen.erase(identity);
                return;
            }

            out << "{";
            bool first = true;
            for (const auto& entry : table) {
                // 只展开字符串/数值键，数组下标转成字符串键
                std::string key;
                if (entry.first.is<std::string>()) key = entry.first.as<std::string>();
                else if (entry.first.is<long long>()) key = std::to_string(entry.first.as<long long>());
                else continue;

                if (!first) out << ",";
                first = false;
                out << json::quote(key) << ":";
                write_value(out, entry.second, depth - 1, seen);
            }
            out << "}";

            if (identity) seen.erase(identity);
            return;
        }
        case sol::type::function: return void(out << "{\"__type\":\"function\"}");
        case sol::type::userdata: return void(out << "{\"__type\":\"userdata\"}");
        case sol::type::thread: return void(out << "{\"__type\":\"thread\"}");
        default: return void(out << "null");
    }
}

} // namespace

std::string lua_value_to_json(const sol::object& value, int max_depth) {
    std::ostringstream out;
    std::set<const void*> seen;
    write_value(out, value, max_depth, seen);
    return out.str();
}

} // namespace phos

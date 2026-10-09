#include "devkit/api_check.hpp"

#include "api/host_api.hpp"
#include "core/defaults.hpp"
#include "core/input.hpp"
#include "core/palette.hpp"
#include "core/screen.hpp"

#include <sol/sol.hpp>

#include <algorithm>
#include <fstream>
#include <iterator>
#include <set>
#include <vector>

namespace phos::devkit {

namespace {

constexpr int kMaxTableDepth = 3;

void collect_registered(const sol::table& table, const std::string& prefix,
                        std::set<std::string>& functions, std::set<std::string>& tables,
                        std::set<std::string>& fields, int depth) {
    if (depth > kMaxTableDepth) return;
    for (const auto& entry : table) {
        if (!entry.first.is<std::string>()) continue;
        const std::string name = entry.first.as<std::string>();
        const std::string full = prefix + "." + name;

        // 用 Lua 自身的类型判定（sol 的 is<T>() 带隐式转换语义，会把 usertype 误判为表）
        switch (entry.second.get_type()) {
            case sol::type::function: functions.insert(full); break;
            case sol::type::table:
                tables.insert(full);
                collect_registered(entry.second.as<sol::table>(), full, functions, tables, fields,
                                   depth + 1);
                break;
            default:
                // 常量字段（颜色常量、screen.width 之类）：注解用 @field 声明它们，
                // 于是"注解承诺了、实现却没有"这种谎话也能被查出来
                fields.insert(full);
                break;
        }
    }
}

/// 注解文件里的三类声明：
///   `function phos.x.y(...)`        函数
///   `phos.x = {}`                   表
///   `---@class phos.x` + @field ... 该表的字段（只有与 `phos.x = {}` 配对的才校验，
///                                   避免把 phos.Color 这类 usertype 的字段算进来）
void collect_annotated(const std::string& text, std::set<std::string>& functions,
                       std::set<std::string>& tables, std::set<std::string>& fields) {
    std::string pending_class;
    std::vector<std::string> pending_fields;

    std::size_t begin = 0;
    while (begin <= text.size()) {
        const std::size_t end = text.find('\n', begin);
        std::string line =
            text.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
        if (!line.empty() && line.back() == '\r') line.pop_back();
        begin = end == std::string::npos ? text.size() + 1 : end + 1;

        const std::size_t first = line.find_first_not_of(" \t");
        if (first == std::string::npos) continue;
        line.erase(0, first);

        if (line.compare(0, 10, "---@class ") == 0) {
            pending_class = line.substr(10);
            while (!pending_class.empty() && pending_class.back() == ' ') pending_class.pop_back();
            pending_fields.clear();
            continue;
        }
        if (line.compare(0, 10, "---@field ") == 0) {
            std::string rest = line.substr(10);
            const std::size_t space = rest.find_first_of(" \t");
            if (space != std::string::npos) rest.resize(space);
            if (!rest.empty() && !pending_class.empty()) pending_fields.push_back(rest);
            continue;
        }

        const std::string function_prefix = "function phos.";
        if (line.compare(0, function_prefix.size(), function_prefix) == 0) {
            const std::size_t paren = line.find('(');
            if (paren != std::string::npos) functions.insert(line.substr(9, paren - 9));
            pending_class.clear();
            pending_fields.clear();
            continue;
        }
        if (line.compare(0, 5, "phos.") == 0) {
            const std::size_t assign = line.find(" = {}");
            if (assign != std::string::npos) {
                const std::string name = line.substr(0, assign);
                tables.insert(name);
                // 只有当这块 @class 就是这张表本身时，其 @field 才代表"表的字段"
                if (pending_class == name)
                    for (const std::string& field : pending_fields) fields.insert(name + "." + field);
            }
            pending_class.clear();
            pending_fields.clear();
            continue;
        }
        if (line.empty() || line[0] != '-') {  // 注释之外的任何行：注解块结束
            pending_class.clear();
            pending_fields.clear();
        }
    }
}

std::vector<std::string> difference(const std::set<std::string>& left,
                                    const std::set<std::string>& right) {
    std::vector<std::string> out;
    for (const std::string& item : left)
        if (!right.count(item)) out.push_back(item);
    return out;
}

} // namespace

ApiCheckResult check_api(const std::string& annotation_path) {
    ApiCheckResult result;

    std::ifstream file(annotation_path);
    if (!file) {
        result.error = "cannot open annotation file: " + annotation_path;
        return result;
    }
    const std::string text((std::istreambuf_iterator<char>(file)),
                           std::istreambuf_iterator<char>());

    std::set<std::string> annotated_functions, annotated_tables, annotated_fields;
    collect_annotated(text, annotated_functions, annotated_tables, annotated_fields);

    // 空沙箱 + 最小宿主上下文：只注册，不运行任何卡带
    Screen screen(kContentW, kContentH);
    Input input;
    Palette palette = builtin_palette();
    HostContext host;
    host.screen = &screen;
    host.input = &input;
    host.palette = &palette;

    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::string, sol::lib::table, sol::lib::math);
    register_host_api(lua, host);

    std::set<std::string> registered_functions, registered_tables, registered_fields;
    collect_registered(lua["phos"], "phos", registered_functions, registered_tables,
                       registered_fields, 0);

    result.implemented = static_cast<int>(registered_functions.size() + registered_tables.size());
    result.documented = static_cast<int>(annotated_functions.size() + annotated_tables.size());

    auto append = [](std::vector<std::string>& target, std::vector<std::string> extra) {
        std::sort(extra.begin(), extra.end());
        target.insert(target.end(), extra.begin(), extra.end());
    };
    append(result.undocumented, difference(registered_functions, annotated_functions));
    append(result.undocumented, difference(registered_tables, annotated_tables));
    append(result.unimplemented, difference(annotated_functions, registered_functions));
    append(result.unimplemented, difference(annotated_tables, registered_tables));
    // 字段只查"注解承诺了、实现却没有"这一个方向：
    // 反方向（实现了但没在注解里逐个列出，如颜色常量）不是问题，报出来只会刷屏
    append(result.unimplemented, difference(annotated_fields, registered_fields));
    return result;
}

} // namespace phos::devkit

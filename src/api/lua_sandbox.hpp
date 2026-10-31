#pragma once

#include <sol/sol.hpp>

#include <initializer_list>
#include <string>

namespace phos::lua_sandbox {

/// 一段可本地化的文本（manifest / 内容包声明里的 name、desc 等）：
/// `"蛇"` 表示中英同文；`{ zh = "蛇", en = "SNAKE" }` 两种语言各一份。
/// 只写一种时另一边回落到它（两边要么同值、要么同空），调用方不必各自再补回落。
struct Localized {
    std::string zh;
    std::string en;
    bool empty() const { return zh.empty() && en.empty(); }
};

/// 不可信脚本的统一沙箱底线：打开调用方给定的标准库 → 摘掉文件与动态加载函数
/// → 装看门狗（lua_guard::attach；预算仍由各次调用的 BudgetScope 提供）
/// → 把 print 汇入主机日志（前缀为 print_tag）。
///
/// 库集合由调用方决定（卡带 / 内容包 / 清单的白名单各不相同），业务 API（`phos.*`、
/// `require`）也由调用方在返回后注册——这里只管三者共同的那条底线。
/// print_tag 为 nullptr 时不重定向（只读声明的清单不产生日志）。
/// 注意：print_tag 的指针会被存进 Lua 闭包（不复制字符串），必须是静态存储期。
void open(sol::state& lua, std::initializer_list<sol::lib> libraries, const char* print_tag);

/// 读一个本地化值（字符串，或 `{ zh = …, en = … }` 表）；其它类型返回空。
Localized read_localized(const sol::object& value);

/// 读表里 key 处的本地化值（规则同上）。
Localized read_localized(const sol::table& table, const char* key);

} // namespace phos::lua_sandbox

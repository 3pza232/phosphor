#pragma once

#include <string>

#include <sol/sol.hpp>

namespace phos {

/// 把 Lua 值转成 JSON 片段，供 agent 侧观测（`state.query`）。
///
/// 支持 number / string / boolean / nil；表按 `max_depth` 递归展开为对象，
/// 超出深度的表记为 `{"__table":N}`（N = 元素个数），循环引用自动截断。
std::string lua_value_to_json(const sol::object& value, int max_depth);

} // namespace phos

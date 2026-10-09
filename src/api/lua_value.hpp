#pragma once

#include "core/color.hpp"

#include <sol/sol.hpp>

namespace phos::api {

/// Lua 值 → 引擎类型的读取工具。
///
/// 脚本宿主（`api/`、`cart/`、`pack/`、`devkit/`）都要把脚本里的表读成引擎类型，
/// 而规则必须一致：同一个 `{r,g,b}` 无论在皮肤、滤镜还是卡带图标里，都该得到
/// 同一个颜色——包括越界值怎么处理。所以只实现一处。

/// `{ r, g, b }` → Color。通道缺失时取 fallback 的对应通道，数值按 0..255 夹紧。
Color read_color(const sol::object& object, Color fallback);

/// 脚本里的"一个字符" → 码点。三种写法都认：
/// 字符串（取第一个码点，UTF-8 安全）、数字（码点本身）、其余 → fallback。
/// 与 read_color 同一理由：同一个字符无论写在屏幕、面板还是绘制区域里，
/// 都该得到同一个结果，所以只实现一处。
char32_t read_char(const sol::object& object, char32_t fallback);

} // namespace phos::api

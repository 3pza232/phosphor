#pragma once

#include "core/color.hpp"

#include <sol/sol.hpp>

namespace phos {
struct HostContext;

namespace api {

/// UI 绑定层共用的参数解析：顶层 phos.ui.*、phos.Region 方法与几何原语都从这里取同一套规则。
///
/// 规则与 docs/api-reference.md 的两组底色约定一致：
///   - 省略 fg（或不是颜色值）= 激活色板的 white；
///   - 省略 bg（或不是颜色值）= 保留原底色（kKeepBg）。

/// Lua 的"一个字符" → 码点：字符串取首码点、数字当码点；其余 → fallback。
/// 与 api::read_char 同一规则，这里只是把 UI 绑定的入口收成一个名字。
char32_t parse_ch(const sol::object& object, char32_t fallback);

/// 前景色：Color（phos.color.*）或 {r,g,b} 表；其余（含缺省）→ fallback。
Color parse_fg(const sol::object& object, Color fallback);

/// 背景色。keep_when_omitted=true 时与 api::read_background 完全一致
/// （Color/{r,g,b} 原样读；坏表缺通道按 Color::black 补；其余 → kKeepBg），
/// 现行 UI 绑定全部走这条；false 时按 read_color 读、省略回落 fallback
/// （"总是写底色"的调用方用，当前 API 层还没有这种调用点）。
Color parse_bg(const sol::object& object, Color fallback, bool keep_when_omitted);

/// 一次解析"字符 + 前景 + 背景"三元组：几何原语与 Region 的写格调用同组。
struct InlinePaint {
    char32_t ch = U' ';
    Color fg;
    Color bg;
};
InlinePaint parse_inline(const sol::object& ch, const sol::object& fg, const sol::object& bg,
                         char32_t fallback_ch, const HostContext& host);

/// 精灵 step（降采样步长）：缺省 1，< 1 钳到 1。
/// 与 core/ui 的 icon 同一规则；core 对直接调用者仍有最终兜底。
int parse_step(const sol::optional<int>& step);

/// 精灵 brightness：缺省 1，非有限按 1，钳到 0..1。同上。
float parse_brightness(const sol::optional<float>& brightness);

} // namespace api
} // namespace phos

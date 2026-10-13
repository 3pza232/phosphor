#pragma once

#include "core/color.hpp"
#include "core/palette.hpp"

#include <cstdint>
#include <map>
#include <sol/sol.hpp>

namespace phos { struct HostContext; }

namespace phos::api {

/// Lua 值 → 引擎类型的读取工具。
///
/// 脚本宿主（`api/`、`cart/`、`pack/`、`devkit/`）都要把脚本里的表读成引擎类型，
/// 而规则必须一致：同一个 `{r,g,b}` 无论在皮肤、色板还是卡带图标里，都该得到
/// 同一个颜色——包括越界值怎么处理。所以只实现一处。

/// `Color` 或 `{ r, g, b }` → Color。通道缺失时取 fallback 的对应通道，数值按 0..255 夹紧。
Color read_color(const sol::object& object, Color fallback);

/// 脚本里的"一个字符" → 码点。三种写法都认：
/// 字符串（取第一个码点，UTF-8 安全）、数字（码点本身）、其余 → fallback。
/// 与 read_color 同一理由：同一个字符无论写在屏幕、面板还是绘制区域里，
/// 都该得到同一个结果，所以只实现一处。
char32_t read_char(const sol::object& object, char32_t fallback);

/// 单个颜色通道 → 0..255 的整数。非数字、NaN、无穷 → fallback（四舍五入取整）。
/// `phos.color.rgb` 与 `read_color` 的通道都走它：坏值不会变成乱跳的通道
int read_channel(const sol::object& object, int fallback = 0);

/// 从表里读一个数值字段：非数字、NaN、±无穷 → fallback。
/// 音效包、联机选项、音频参数都读数值表，"坏值怎么处理"只有这一份实现
double read_number(const sol::table& table, const char* key, double fallback);

/// `{ "第一行", "第二行" }` → 行列表。非字符串项跳过：
/// 脚本里给错类型的一项不该让整块画面都画不出来。
std::vector<std::string> read_rows(const sol::object& object);

/// `{ ["#"] = {r,g,b} }` → 字符 → 颜色。键取首字节（字符画是 ASCII，按码点取反而是绕路）；
/// 值是颜色的项才收——卡带图标与精灵共用这份读取，两处各写一套迟早对同一个表给出不同结果。
std::map<char, Color> read_char_color_map(const sol::object& object);

/// 背景色参数 → Color。拿到颜色（`Color` 或 `{r,g,b}` 表）就原样返回；
/// **其余一律返回带 `keep` 标记的颜色**，含义是"保留该格原有底色"——
/// 卡带 API 里"没给背景色"就是这个意思。谁把 keep 当默认值、谁把黑当默认值，
/// 由各绑定按 docs/api-reference.md 的两组规则决定。
Color read_background(const sol::object& object);

/// 取激活色板的某个色；无激活色板（如无头模式）时回落 fallback
Color slot_color(const HostContext& host, PaletteSlot slot, Color fallback);
/// 卡带 API 省略**前景**时的默认色 = 激活色板的 white
Color default_fg(const HostContext& host);
/// 省略**背景**时的默认色 = 激活色板的 black（`panel.fill/clear` 另取主题面板色）
Color default_bg(const HostContext& host);

/// 缩放参数（`phos.screen` / `phos.panel` / `phos.ui` 的 `put`/`print` 可选末参）：
/// < 2 按常规（1），超过 `Screen::kMaxCellScale` 钳到上限。是"更大的字"的入参
std::uint8_t read_scale(const sol::optional<int>& scale);

} // namespace phos::api

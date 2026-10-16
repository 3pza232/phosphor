#pragma once

namespace phos {

/// 主机版本号——全工程唯一权威来源（C++ 与 Lua 均从此取值，禁止各处硬编码）。
/// 进位规矩（1.0 之前不承诺兼容性，只求"看一眼版本号就知道这批改动的分量"）：
///   y：同世代内的修错与小补（新增一张卡带、修一条文档、补一个门禁）
///   x：**能力世代**更替——新增子系统，或卡带 API 世代 `kPhosApiVersion` 变了
/// 0.8.0：同屏多字号——`phos.screen/panel/ui` 的 `put`/`print` 增加可选 `scale`
///         （更大的字成块占位）；字体方案可显式声明字号与回退顺序。卡带 API 进世代 6
/// 0.8.1：小补——`phos.input` 增键盘专属键 `backspace`（退格）；字体方案可声明可调字号范围（Mod 可改）
/// 0.8.2：内容包扩容——卡带架样式成为内容包（`theme/shelf/<名>/shelf.lua`：可注册绘制、二维导航、
///         本地化样式名）；Mod 改命名化（`mods/<id>/` + 可选 `mod.lua` 清单，游戏内 `M` 键开关、
///         改动后重启生效）；新增三个开机动画 + 主题（深海声呐 / 东方翰墨 / 黄铜机械）
inline constexpr const char* kVersion = "0.8.2";
/// 产品名
inline constexpr const char* kProductName = "PHOSPHOR";
/// 卡带 API 世代：manifest 声明 `phos_api` 高于它就拒绝加载，
/// 而不是让卡带在运行到一半时才撞上缺失的接口。逐代叠加，旧卡带只需旧世代的接口：
///   2 = 可选图层（phos.layer）与 phos.text.ink_box / phos.input.duration /
///       phos.input.keys / phos.sys.frame
///   3 = 墨迹叠加（phos.screen.blend）、半格绘制（plot / quadrant / cell_of）与
///       独立底色（back / back_rect，及各自的区域版）
///   4 = 局域网联机（phos.net：开房/加入/收发/发现）
///   5 = 主题携带内容色板：`phos.color.*` 随主题变；卡带默认前景/背景取自色板，
///       面板与浮层默认底色取自主题（卡带不必改代码，但配色会随主题变）
///   6 = 同屏多字号：`put`/`print` 增加可选 `scale`（>=2 时那一个字占 scale 列 x scale 行）
inline constexpr int kPhosApiVersion = 6;

} // namespace phos

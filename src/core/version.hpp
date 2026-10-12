#pragma once

namespace phos {

/// 主机版本号——全工程唯一权威来源（C++ 与 Lua 均从此取值，禁止各处硬编码）。
/// 进位规矩（1.0 之前不承诺兼容性，只求"看一眼版本号就知道这批改动的分量"）：
///   y：同世代内的修错与小补（新增一张卡带、修一条文档、补一个门禁）
///   x：**能力世代**更替——新增子系统，或卡带 API 世代 `kPhosApiVersion` 变了
inline constexpr const char* kVersion = "0.5.0";
/// 产品名
inline constexpr const char* kProductName = "PHOSPHOR";
/// 卡带 API 世代：manifest 声明 `phos_api` 高于它就拒绝加载，
/// 而不是让卡带在运行到一半时才撞上缺失的接口。逐代叠加，旧卡带行为完全不变：
///   2 = 可选图层（phos.layer）与 phos.text.ink_box / phos.input.duration /
///       phos.input.keys / phos.sys.frame
///   3 = 墨迹叠加（phos.screen.blend）、半格绘制（plot / quadrant / cell_of）与
///       独立底色（back / back_rect，及各自的区域版）
///   4 = 局域网联机（phos.net：开房/加入/收发/发现）
inline constexpr int kPhosApiVersion = 4;

} // namespace phos

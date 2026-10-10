#pragma once

namespace phos {

/// 主机版本号——全工程唯一权威来源（C++ 与 Lua 均从此取值，禁止各处硬编码）
inline constexpr const char* kVersion = "0.2.0";
/// 产品名
inline constexpr const char* kProductName = "PHOSPHOR";
/// 卡带 API 世代：manifest 声明 `phos_api` 高于它就拒绝加载，
/// 而不是让卡带在运行到一半时才撞上缺失的接口
inline constexpr int kPhosApiVersion = 1;

} // namespace phos

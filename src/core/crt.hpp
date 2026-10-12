#pragma once

#include "core/screen.hpp"

namespace phos {

struct Palette;

/// 显像管后处理参数。参照 RetroArch 系 CRT 后处理的做法：
/// 细扫描线（屏幕行的亮暗条纹）+ 孔径格栅（RGB 子像素条纹）+ 轻度辉光。
struct CrtParams {
    float scanline = 0.0f;  // 扫描线深度 0..1（细线，非整片压暗）
    float mask = 0.0f;      // 孔径格栅强度 0..1
    float glow = 0.12f;     // 字符辉光 0..1（过强会让像素字发虚）
    bool compensate = true; // 亮度补偿：抵消细线与格栅带来的整体变暗
    Color tint{255, 255, 255};
};

/// 扫描线周期（像素）。固定在 3px 左右才像"屏幕行"，过大就变成整片变暗。
inline constexpr float kScanlinePeriodPx = 3.0f;

/// 暗线在周期内的相位区间（起点、终点）：两端平滑过渡，避免出现硬边。
/// CPU 光栅化与 GL 着色器共用（着色器经 uniform 取值），两条渲染路径才对得上。
inline constexpr float kScanlineDarkStart = 0.68f;
inline constexpr float kScanlineDarkEnd = 0.98f;

/// 亮度补偿的损失系数：按暗线占比与格栅通道占比估算的平均亮度损失。
/// 两条渲染路径都必须引用这里，否则同一档位在窗口与截图里会亮得不一样。
inline constexpr float kScanlineLossPerUnit = 0.16f;
inline constexpr float kMaskLossPerUnit = 0.55f;

/// 机器扫描线档位：0=OFF 1=WEAK 2=MEDIUM 3=STRONG
inline constexpr int kCrtLevelCount = 4;

/// 档位换算为后处理参数；tint 恒取色板，scanline 在色板声明 >0 且档位非 OFF 时以色板为准，
/// glow / mask 由档位决定
CrtParams crt_params_for_level(int level, const Palette& palette);

/// 档位显示名
const char* crt_level_name(int level);

} // namespace phos

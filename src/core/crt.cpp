#include "core/crt.hpp"

#include "core/palette.hpp"

namespace phos {

namespace {

struct LevelSpec {
    const char* name;
    float scanline;  // 细线深度
    float mask;      // 格栅强度（保持较低，避免整体发暗）
    float glow;      // 辉光（保持较低，保住像素字清晰度）
};

// 强度档位（OFF 之外三档）：靠"细线结构"制造 CRT 观感，而不是靠压暗和发虚
constexpr LevelSpec kLevels[kCrtLevelCount] = {
    {"OFF",    0.00f, 0.00f, 0.10f},
    {"WEAK",   0.38f, 0.07f, 0.12f},
    {"MEDIUM", 0.65f, 0.14f, 0.16f},
    {"STRONG", 0.92f, 0.22f, 0.22f},
};

} // namespace

CrtParams crt_params_for_level(int level, const Palette& palette) {
    if (level < 0) level = 0;
    if (level >= kCrtLevelCount) level = kCrtLevelCount - 1;
    const LevelSpec& spec = kLevels[level];

    CrtParams p;
    p.scanline = spec.scanline;
    p.mask = spec.mask;
    p.glow = spec.glow;
    p.compensate = level > 0;
    p.tint = palette.tint;

    // 色板可声明自己的扫描线强度（>0 时优先），保持内容包的表达力
    if (palette.scan_strength > 0.01f && level > 0)
        p.scanline = palette.scan_strength;

    return p;
}

const char* crt_level_name(int level) {
    if (level < 0) level = 0;
    if (level >= kCrtLevelCount) level = kCrtLevelCount - 1;
    return kLevels[level].name;
}

} // namespace phos

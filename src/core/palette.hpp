#pragma once

#include "core/screen.hpp"

#include <array>
#include <string>

namespace phos {

/// 调色板槽位：与 phos.color.* 常量一一对应
enum class PaletteSlot {
    black, white, gray, dark_gray,
    red, green, blue, yellow,
    cyan, magenta, orange, purple,
    count
};
constexpr size_t kPaletteSlots = static_cast<size_t>(PaletteSlot::count);

/// 槽位名（顺序与 PaletteSlot 一一对应）。
/// 打包扫描（读 palette.lua）与 Lua API（写 phos.color.*）都取这一份：
/// 有了它，"枚举加一项、名字表漏改"这种静默错色就不会发生。
inline constexpr const char* kPaletteSlotNames[kPaletteSlots] = {
    "black",  "white",   "gray",   "dark_gray", "red",    "green",
    "blue",   "yellow",  "cyan",   "magenta",   "orange", "purple",
};

constexpr const char* palette_slot_name(PaletteSlot slot) {
    return kPaletteSlotNames[static_cast<size_t>(slot)];
}

/// 一套显像管质感定义（palette 内容包的内存形态）
struct Palette {
    std::string id = "default";
    std::string name = "GREEN PHOSPHOR";
    std::array<Color, kPaletteSlots> slots{};
    float scan_strength = 0.08f;      // 扫描线强度 0..1（设置界面的开关是总闸）
    Color tint{255, 255, 255};        // 显像管整体色调（乘算，含外壳界面）
};

/// 出厂默认调色板（硬编码兜底，永远是回退链的最后一环）
Palette builtin_palette();

} // namespace phos

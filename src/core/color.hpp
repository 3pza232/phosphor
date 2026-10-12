#pragma once

#include <cstdint>

namespace phos {

/// 一种颜色。调色板、屏幕格、界面样式、卡带图标都用它。
///
/// 单独成文件：几乎所有模块都要用 Color，而它不该逼任何人连带包含整个屏幕网格。
struct Color {
    uint8_t r = 255, g = 255, b = 255;

    /// "别动这格的背景"：背景色带这个标记时，Screen::put 取该格**原有**背景。
    /// 卡带界面样式（style_from_palette）整体带它，于是覆盖层默认透明
    bool keep = false;

    static const Color black, white, gray, dark_gray;
    static const Color red, green, blue, yellow;
    static const Color cyan, magenta, orange, purple;
};

/// put / print / fill 的**默认底色**：保留该格原有底色（即"透明"，不覆盖背景）。
/// 这样"写字/画图标"默认不会在黑底上砸出方块；需要实底的地方显式传背景色即可。
/// 底层网格的默认 `alpha` 是不透明的（见 Screen::Cell），所以默认透明只影响"是否覆盖背景色"，
/// 不会让底层漏空
inline const Color kKeepBg{255, 255, 255, true};

} // namespace phos

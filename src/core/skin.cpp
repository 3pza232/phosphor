#include "core/skin.hpp"

#include "core/text.hpp"

namespace phos {

bool skin_ui_glyph(std::string_view text, char32_t& out) {
    const auto codepoints = text::decode(text);
    if (codepoints.size() != 1) return false;
    const char32_t cp = codepoints.front();
    if (cp < 32 || cp == 127) return false;  // 控制字符会破坏网格/终端，不算合法字形
    out = cp;
    return true;
}

bool skin_ui_accept_metric(int value, int min_value, int max_value) {
    return value >= min_value && value <= max_value;
}

Skin builtin_skin() {
    Skin s;
    // 硬编码兜底机身：没有任何皮肤包时才出场，名字刻意与内容包区分开
    s.id = "builtin";
    s.name = "BUILTIN";
    s.left = "||";
    s.right = "||";
    // 出厂机身：极简工业风（宽度由主机自动补齐）
    s.top = {
        "====================================================================",
        "= PHOSPHOR P-1                                     CRT DISPLAY UNIT =",
        "====================================================================",
    };
    s.bottom = {
        "====================================================================",
        "= MODEL P-1                        NO USER SERVICEABLE PARTS INSIDE =",
        "====================================================================",
    };
    s.lamps = {
        {8, 1, {80, 255, 120}, 2.4f},
        {74, 1, {255, 80, 80}, 9.0f},
    };
    return s;
}

} // namespace phos

#include "core/effects.hpp"

namespace phos::effects {

namespace {

constexpr int kFlashRows = 4;  // 闪烁带条数

} // namespace

void draw_insert_flash(Screen& screen, const ui::Rect& content, Color bright, Color accent,
                       long frame) {
    for (int i = 0; i < kFlashRows; ++i) {
        const int y = content.y + static_cast<int>((frame * 7 + i * 11) % content.h);
        const bool solid = i % 2 == 0;
        const char32_t ch = solid ? U'=' : U'#';
        const Color color = solid ? bright : accent;
        // 底色留空（keep）：亮带压在内容/机身上透出来，不再砸出黑底
        for (int x = content.x; x < content.x + content.w; ++x)
            screen.put(x, y, ch, color);
    }
}

void draw_eject_collapse(Screen& screen, const ui::Rect& content, float progress, Color bright) {
    const int center_y = content.y + content.h / 2;

    // 只清字形、保留机身底色：拔卡这一瞬内容区已经是机身色，不该再糊一条黑带
    for (int x = content.x; x < content.x + content.w; ++x)
        screen.put(x, center_y, U' ', bright);

    const int half = static_cast<int>((1.0f - progress) * (content.w / 2));
    const int mid = content.x + content.w / 2;
    for (int dx = -half; dx <= half; ++dx)
        screen.put(mid + dx, center_y, U'#', bright);
}

} // namespace phos::effects

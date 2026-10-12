#include "core/ui.hpp"

#include "core/palette.hpp"
#include "core/skin.hpp"
#include "core/text.hpp"

#include <algorithm>
#include <vector>

namespace phos::ui {

Style style_from_skin(const Skin& skin) {
    Style s;
    s.fg = skin.ui_fg;
    s.dim = skin.ui_dim;
    s.accent = skin.accent;
    s.frame = skin.frame;
    s.bg = skin.ui_bg;
    return s;
}

Style style_from_palette(const Palette& palette) {
    auto slot = [&palette](PaletteSlot which) {
        return palette.slots[static_cast<size_t>(which)];
    };
    Style s;
    s.fg = slot(PaletteSlot::white);
    s.dim = slot(PaletteSlot::dark_gray);
    s.accent = slot(PaletteSlot::green);
    s.frame = slot(PaletteSlot::gray);
    s.bg = slot(PaletteSlot::black);
    // 卡带侧的界面样式**默认不动背景**：卡带的浮窗/边框压在游戏画面上时，
    // 不该把底下的画面糊成一块黑板。要一块不透明底的地方，显式传颜色即可
    // （机身边框走 style_from_skin，仍是实底，不受这里影响）
    s.bg.keep = true;
    return s;
}

Rect Rect::centered(Rect area, int w, int h) {
    return Rect{area.x + (area.w - w) / 2, area.y + (area.h - h) / 2, w, h};
}

void fill(Screen& screen, Rect rect, char32_t ch, Color fg, Color bg) {
    screen.fill(rect.x, rect.y, rect.w, rect.h, ch, fg, bg);
}

void print(Screen& screen, int x, int y, std::string_view text, Color fg, Color bg) {
    screen.print(x, y, text, fg, bg);  // 解码与宽度推进统一由 Screen 负责
}

void print_centered(Screen& screen, int y, std::string_view text, Color fg, Color bg,
                    int base, int span) {
    print(screen, text::centered_x(text, base, span), y, text, fg, bg);
}

void divider(Screen& screen, int x, int y, int width, Color color, Color bg) {
    for (int i = 0; i < width; ++i)
        screen.put(x + i, y, U'-', color, bg);
}

void frame(Screen& screen, Rect rect, std::string_view title, const Style& style) {
    if (rect.w < 2 || rect.h < 2) return;

    // 标题先占据上边框的一段，其余用 '-' 填充。
    // 标题按**显示宽度**截断（中文标题占两格，按字节算会顶穿边框）、
    // 并留出左右各一个空格，所以可用宽度要再减 2
    std::string top(static_cast<size_t>(rect.w), '-');
    if (!title.empty()) {
        constexpr int kOffset = 2;
        const int room = rect.w - kOffset - 2;
        if (room > 0) {
            top = std::string(static_cast<size_t>(kOffset), '-') + " " +
                  text::truncate(title, room) + " ";
            top.resize(static_cast<size_t>(rect.w), '-');
        }
    }
    // 标题可能含全角字符：整行走 Screen::print 按宽度推进
    screen.print(rect.x, rect.y, top, style.frame, style.bg);
    for (int i = 0; i < rect.w; ++i)
        screen.put(rect.x + i, rect.bottom(), U'-', style.frame, style.bg);
    for (int y = rect.y + 1; y < rect.bottom(); ++y) {
        screen.put(rect.x, y, U'|', style.frame, style.bg);
        screen.put(rect.right(), y, U'|', style.frame, style.bg);
    }
    screen.put(rect.x, rect.y, U'+', style.frame, style.bg);
    screen.put(rect.right(), rect.y, U'+', style.frame, style.bg);
    screen.put(rect.x, rect.bottom(), U'+', style.frame, style.bg);
    screen.put(rect.right(), rect.bottom(), U'+', style.frame, style.bg);
}

void bar(Screen& screen, int x, int y, int width, float ratio, const Style& style) {
    if (width < 2) return;
    ratio = ratio < 0.0f ? 0.0f : (ratio > 1.0f ? 1.0f : ratio);
    int filled = static_cast<int>(ratio * (width - 2) + 0.5f);

    screen.put(x, y, U'[', style.frame, style.bg);
    screen.put(x + width - 1, y, U']', style.frame, style.bg);
    for (int i = 1; i < width - 1; ++i) {
        bool on = (i - 1) < filled;
        screen.put(x + i, y, on ? U'#' : U'-', on ? style.accent : style.dim, style.bg);
    }
}

void menu(Screen& screen, Rect rect, const std::vector<std::string>& items, int selected,
          const Style& style) {
    if (items.empty() || rect.h <= 0) return;

    // 垂直滚动窗口：保证选中项可见
    int visible = rect.h;
    int first = 0;
    if (selected >= visible) first = selected - visible + 1;
    if (first > static_cast<int>(items.size()) - visible)
        first = static_cast<int>(items.size()) - visible;
    if (first < 0) first = 0;

    for (int row = 0; row < visible; ++row) {
        int index = first + row;
        if (index >= static_cast<int>(items.size())) break;
        int y = rect.y + row;
        bool is_selected = index == selected;

        std::string label = text::pad_right(items[static_cast<size_t>(index)],
                                            static_cast<size_t>(rect.w - 2));
        Color color = is_selected ? style.accent : style.fg;
        screen.put(rect.x, y, is_selected ? U'>' : U' ', style.accent, style.bg);
        print(screen, rect.x + 1, y, label, color, style.bg);
    }
}

void text_block(Screen& screen, int x, int y, int width, std::string_view body, int max_lines,
                const Style& style) {
    auto lines = text::wrap(body, static_cast<size_t>(width < 1 ? 1 : width),
                            static_cast<size_t>(max_lines < 1 ? 1 : max_lines));
    for (size_t i = 0; i < lines.size(); ++i)
        print(screen, x, y + static_cast<int>(i), lines[i], style.fg, style.bg);
}

void icon(Screen& screen, const std::vector<std::string>& rows,
          const std::map<char, Color>& colors, int center_x, int center_y, int step,
          float brightness, Color fallback) {
    if (rows.empty() || step < 1) return;

    int src_h = static_cast<int>(rows.size());
    int src_w = 0;
    for (const auto& row : rows)
        src_w = std::max(src_w, text::display_width(row));

    int draw_h = (src_h + step - 1) / step;
    int draw_w = (src_w + step - 1) / step;
    int x0 = center_x - draw_w / 2;
    int y0 = center_y - draw_h / 2;

    auto scale = [brightness](Color c) {
        auto channel = [brightness](uint8_t v) {
            float out = static_cast<float>(v) * brightness;
            return static_cast<uint8_t>(out > 255.0f ? 255.0f : out);
        };
        return Color{channel(c.r), channel(c.g), channel(c.b)};
    };

    for (int dy = 0; dy < draw_h; ++dy) {
        int sy = dy * step;
        if (sy >= src_h) break;
        // 按码点取样：图标是 manifest 里的字符画，按字节取会在多字节字符上崩
        const std::vector<char32_t> glyphs = text::decode(rows[static_cast<size_t>(sy)]);
        for (int dx = 0; dx < draw_w; ++dx) {
            int sx = dx * step;
            if (sx >= static_cast<int>(glyphs.size())) break;
            const char32_t ch = glyphs[static_cast<size_t>(sx)];
            if (ch == U'.' || ch == U' ') continue;
            auto it = colors.find(static_cast<char>(ch));
            Color c = it != colors.end() ? it->second : fallback;
            // 保留底色：图标压在卡带架/机身上，不该砸出一块黑底
            screen.put(x0 + dx, y0 + dy, ch, scale(c), phos::kKeepBg);
        }
    }
}

int navigate(const Input& input, int count, int current, NavAction& action) {
    action = NavAction::none;
    if (count <= 0) return 0;

    int index = current;
    if (index < 0 || index >= count) index = 0;
    if (input.pressed(Key::up))   index = (index + count - 1) % count;
    if (input.pressed(Key::down)) index = (index + 1) % count;
    if (input.pressed(Key::a)) action = NavAction::confirm;
    if (input.pressed(Key::b)) action = NavAction::cancel;
    return index;
}

} // namespace phos::ui

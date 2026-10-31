#include "core/ui.hpp"

#include "core/color.hpp"
#include "core/palette.hpp"
#include "core/skin.hpp"
#include "core/text.hpp"

#include <algorithm>
#include <cmath>
#include <vector>

namespace phos::ui {

namespace {

/// 几何原语的裁剪区：屏幕 ∩ 可选 clip。clip 为空指针时就是整块屏幕。
/// 用 64 位求交，脚本传入的矩形可能贴近 INT_MAX；返回空矩形（w/h = 0）表示不可见。
Rect clipped_rect(const Screen& screen, const Rect* clip) {
    long long x0 = 0;
    long long y0 = 0;
    long long x1 = static_cast<long long>(screen.width()) - 1;
    long long y1 = static_cast<long long>(screen.height()) - 1;
    if (clip) {
        x0 = std::max<long long>(x0, clip->x);
        y0 = std::max<long long>(y0, clip->y);
        x1 = std::min<long long>(x1, static_cast<long long>(clip->x) + clip->w - 1);
        y1 = std::min<long long>(y1, static_cast<long long>(clip->y) + clip->h - 1);
    }
    if (x1 < x0 || y1 < y0) return Rect{0, 0, 0, 0};
    return Rect{static_cast<int>(x0), static_cast<int>(y0), static_cast<int>(x1 - x0 + 1),
                static_cast<int>(y1 - y0 + 1)};
}

/// Cohen–Sutherland：把线段裁到 [min_x, max_x] × [min_y, max_y] 的矩形内。
/// 端点来自脚本，可能接近 INT_MIN/INT_MAX（整数乘除会溢出），所以用 double 求交后再取整；
/// 窗口外的超大坐标不会变成无界的光栅化循环。
bool clip_to_rect(double& x1, double& y1, double& x2, double& y2, double min_x, double max_x,
                  double min_y, double max_y) {
    const auto code = [min_x, max_x, min_y, max_y](double x, double y) {
        int c = 0;
        if (x < min_x) c |= 1;
        else if (x > max_x) c |= 2;
        if (y < min_y) c |= 4;
        else if (y > max_y) c |= 8;
        return c;
    };
    int c1 = code(x1, y1);
    int c2 = code(x2, y2);
    for (int guard = 0; guard < 8; ++guard) {
        if ((c1 | c2) == 0) return true;   // 两端都在窗口内
        if ((c1 & c2) != 0) return false;  // 同一侧外：整段不可见
        const int c = c1 != 0 ? c1 : c2;
        double x = 0.0;
        double y = 0.0;
        if ((c & 1) != 0) {
            x = min_x;
            y = y1 + (y2 - y1) * (min_x - x1) / (x2 - x1);
        } else if ((c & 2) != 0) {
            x = max_x;
            y = y1 + (y2 - y1) * (max_x - x1) / (x2 - x1);
        } else if ((c & 4) != 0) {
            y = min_y;
            x = x1 + (x2 - x1) * (min_y - y1) / (y2 - y1);
        } else {
            y = max_y;
            x = x1 + (x2 - x1) * (max_y - y1) / (y2 - y1);
        }
        if (c == c1) {
            x1 = x;
            y1 = y;
            c1 = code(x1, y1);
        } else {
            x2 = x;
            y2 = y;
            c2 = code(x2, y2);
        }
    }
    return false;
}

} // namespace

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

void line(Screen& screen, int x1, int y1, int x2, int y2, char32_t ch, Color fg, Color bg,
          const Rect* clip) {
    const Rect area = clipped_rect(screen, clip);
    if (area.w <= 0 || area.h <= 0) return;
    const int lo_x = area.x;
    const int hi_x = area.x + area.w - 1;
    const int lo_y = area.y;
    const int hi_y = area.y + area.h - 1;

    double ax = x1, ay = y1, bx = x2, by = y2;
    if (!clip_to_rect(ax, ay, bx, by, static_cast<double>(lo_x), static_cast<double>(hi_x),
                      static_cast<double>(lo_y), static_cast<double>(hi_y)))
        return;
    int px = std::clamp(static_cast<int>(std::lround(ax)), lo_x, hi_x);
    int py = std::clamp(static_cast<int>(std::lround(ay)), lo_y, hi_y);
    const int ex = std::clamp(static_cast<int>(std::lround(bx)), lo_x, hi_x);
    const int ey = std::clamp(static_cast<int>(std::lround(by)), lo_y, hi_y);

    const int dx = ex > px ? ex - px : px - ex;
    const int dy = ey > py ? ey - py : py - ey;
    const int sx = px < ex ? 1 : -1;
    const int sy = py < ey ? 1 : -1;
    int err = dx - dy;
    for (;;) {
        screen.put(px, py, ch, fg, bg);
        if (px == ex && py == ey) break;
        const int e2 = 2 * err;
        if (e2 > -dy) {
            err -= dy;
            px += sx;
        }
        if (e2 < dx) {
            err += dx;
            py += sy;
        }
    }
}

void outline(Screen& screen, int x, int y, int w, int h, char32_t ch, Color fg, Color bg,
             const Rect* clip) {
    if (w <= 0 || h <= 0) return;
    const Rect area = clipped_rect(screen, clip);
    if (area.w <= 0 || area.h <= 0) return;
    const long long ax0 = area.x;
    const long long ay0 = area.y;
    const long long ax1 = static_cast<long long>(area.x) + area.w - 1;
    const long long ay1 = static_cast<long long>(area.y) + area.h - 1;

    const long long x0 = x;
    const long long y0 = y;
    const long long x1 = x0 + w - 1;
    const long long y1 = y0 + h - 1;

    // 上下边：与裁剪区横向求交后成段画（宽矩形只画可见段，循环次数有界）
    const long long hx0 = std::max(x0, ax0);
    const long long hx1 = std::min(x1, ax1);
    if (hx0 <= hx1) {
        if (y0 >= ay0 && y0 <= ay1)
            for (long long i = hx0; i <= hx1; ++i)
                screen.put(static_cast<int>(i), static_cast<int>(y0), ch, fg, bg);
        if (y1 != y0 && y1 >= ay0 && y1 <= ay1)
            for (long long i = hx0; i <= hx1; ++i)
                screen.put(static_cast<int>(i), static_cast<int>(y1), ch, fg, bg);
    }
    // 左右边：角格已由上下边覆盖，纵向区间去掉两端（退化时为空）
    const long long vy0 = std::max(y0 + 1, ay0);
    const long long vy1 = std::min(y1 - 1, ay1);
    if (vy0 <= vy1) {
        if (x0 >= ax0 && x0 <= ax1)
            for (long long i = vy0; i <= vy1; ++i)
                screen.put(static_cast<int>(x0), static_cast<int>(i), ch, fg, bg);
        if (x1 != x0 && x1 >= ax0 && x1 <= ax1)
            for (long long i = vy0; i <= vy1; ++i)
                screen.put(static_cast<int>(x1), static_cast<int>(i), ch, fg, bg);
    }
}

void circle(Screen& screen, int cx, int cy, int r, char32_t ch, Color fg, Color bg,
            const Rect* clip) {
    const Rect area = clipped_rect(screen, clip);
    if (area.w <= 0 || area.h <= 0) return;
    const long long ax0 = area.x;
    const long long ay0 = area.y;
    const long long ax1 = static_cast<long long>(area.x) + area.w - 1;
    const long long ay1 = static_cast<long long>(area.y) + area.h - 1;
    if (r <= 0) {  // 半径 0（或负数）：退化成一格（裁剪区内才写）
        if (cx >= ax0 && cx <= ax1 && cy >= ay0 && cy <= ay1) screen.put(cx, cy, ch, fg, bg);
        return;
    }

    const long long ccx = cx;
    const long long ccy = cy;
    const auto plot = [&](long long px, long long py) {
        if (px < ax0 || py < ay0 || px > ax1 || py > ay1) return;
        screen.put(static_cast<int>(px), static_cast<int>(py), ch, fg, bg);
    };
    // 八向对称点里"较小坐标"是 y：y 超过屏幕任一边长后，八个镜像点都不在屏幕内。
    // 上界仍按**屏幕**算（与不传 clip 时的几何一致）：clip 只过滤结果，
    // 不改变同一段弧的采样；半径再大也不会变成无界循环。
    const long long limit = std::max(screen.width() - 1, screen.height() - 1);
    long long x = r;
    long long y = 0;
    long long err = 1 - x;
    while (x >= y) {
        if (y > limit) break;
        plot(ccx + x, ccy + y);
        plot(ccx - x, ccy + y);
        plot(ccx + x, ccy - y);
        plot(ccx - x, ccy - y);
        if (x != y) {
            plot(ccx + y, ccy + x);
            plot(ccx - y, ccy + x);
            plot(ccx + y, ccy - x);
            plot(ccx - y, ccy - x);
        }
        ++y;
        if (err < 0) {
            err += 2 * y + 1;
        } else {
            --x;
            err += 2 * (y - x) + 1;
        }
    }
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
    // ratio 来自脚本/内容：NaN/inf 不能参与 int 转换（那是 UB）。非有限一律按 0，其余钳到 0..1
    ratio = std::isfinite(ratio) ? std::clamp(ratio, 0.0f, 1.0f) : 0.0f;
    const int filled = static_cast<int>(ratio * static_cast<float>(width - 2) + 0.5f);

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
    if (rows.empty()) return;
    // step = 降采样步长：整数 >= 1（< 1 钳到 1，0 = 逐字符）。
    // brightness = 0..1：非有限按 1，越界钳制；它只改前景色，图标仍按字形占格
    // （brightness = 0 => 全黑，视觉上等于"画空"）。
    step = std::max(1, step);
    if (!std::isfinite(brightness)) brightness = 1.0f;
    brightness = std::clamp(brightness, 0.0f, 1.0f);

    const int src_h = static_cast<int>(rows.size());
    int src_w = 0;
    for (const auto& row : rows)
        src_w = std::max(src_w, text::display_width(row));

    // 向上取整但不写 src + step - 1：step 来自脚本，极大时会 int 溢出
    const int draw_h = (src_h - 1) / step + 1;
    const int draw_w = src_w == 0 ? 0 : (src_w - 1) / step + 1;
    const int x0 = center_x - draw_w / 2;
    const int y0 = center_y - draw_h / 2;

    // 提亮/压暗：与指示灯呼吸、其它高亮共用 core/color.hpp 的 scale_color（钳位只有一份）
    auto scale = [brightness](Color c) { return scale_color(c, brightness); };

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

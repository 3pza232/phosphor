#include "core/surface.hpp"

#include "core/text.hpp"

#include <algorithm>

namespace phos {

Surface::Surface(Screen& screen, int origin_x, int origin_y, int w, int h)
    : screen_(screen), ox_(origin_x), oy_(origin_y),
      w_(w < 0 ? 0 : w), h_(h < 0 ? 0 : h) {}

void Surface::put(int x, int y, char32_t ch, Color fg, Color bg) {
    const int cols = text::char_width(ch);
    if (cols == 0 || x < 0 || x + cols > w_ || y < 0 || y >= h_) return;
    screen_.put(ox_ + x, oy_ + y, ch, fg, bg);
}

void Surface::print(int x, int y, std::string_view text, Color fg, Color bg) {
    if (y < 0 || y >= h_) return;
    // 右缘按**显示宽度**截断（汉字算两格）。起笔落在面外时 x 可负，
    // 那时保留整行、由下面的逐格判断丢弃左边看不见的部分
    const std::string clipped = text::truncate(text, w_ - x);
    int col = x;
    for (char32_t cp : text::decode(clipped)) {
        const int cols = text::char_width(cp);
        if (cols == 0) continue;
        if (col + cols > w_) break;  // 右边界放不下就停，宁少画不错位
        if (col >= 0) screen_.put(ox_ + col, oy_ + y, cp, fg, bg);
        col += cols;
    }
}

void Surface::fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg) {
    // 先把矩形与本面求交，再整块交给 Screen::fill：宽字符成对铺的规则在那一处，
    // 逐格自己写会在右缘留下半个宽字的位置
    const int x0 = std::max(x, 0);
    const int y0 = std::max(y, 0);
    const int x1 = std::min(x + w, w_);
    const int y1 = std::min(y + h, h_);
    if (x1 <= x0 || y1 <= y0) return;
    screen_.fill(ox_ + x0, oy_ + y0, x1 - x0, y1 - y0, ch, fg, bg);
}

void Surface::blit(int x, int y, const std::vector<std::string>& rows, Color fg, Color bg) {
    for (size_t i = 0; i < rows.size(); ++i)
        print(x, y + static_cast<int>(i), rows[i], fg, bg);
}

const Cell& Surface::at(int x, int y) const {
    return inside(x, y) ? screen_.at(ox_ + x, oy_ + y) : Screen::empty();
}

char32_t Surface::glyph_at(int x, int y) const {
    return inside(x, y) ? screen_.glyph_at(ox_ + x, oy_ + y) : 0;
}

} // namespace phos

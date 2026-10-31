#include "core/screen.hpp"

#include "core/screen_draw.hpp"
#include "core/screen_store.hpp"
#include "core/screen_text.hpp"

namespace phos {

Screen::Screen(int w, int h) : store_(w, h) {}

void Screen::resize(int w, int h) { store_.resize(w, h); }

void Screen::put(int x, int y, char32_t ch, Color fg, Color bg, uint8_t scale) {
    screen_draw::Writer::put(store_, x, y, ch, fg, bg, scale);
}

void Screen::print(int x, int y, std::string_view text, Color fg, Color bg, uint8_t scale) {
    screen_draw::Writer::print(store_, x, y, text, fg, bg, scale);
}

void Screen::fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg) {
    screen_draw::Writer::fill(store_, x, y, w, h, ch, fg, bg);
}

bool Screen::blend(int x, int y, char32_t ch, Color fg) {
    return screen_draw::Writer::blend(store_, x, y, ch, fg);
}

void Screen::back(int x, int y, Color bg) { screen_draw::Writer::back(store_, x, y, bg); }

void Screen::plot(int x2, int y2, Color fg) { screen_draw::Writer::plot(store_, x2, y2, fg); }

void Screen::forget_plot_bits(int x, int y) {
    screen_draw::Writer::forget_plot_bits(store_, x, y);
}

void Screen::set(int x, int y, const Cell& cell) { screen_draw::Writer::set(store_, x, y, cell); }

void Screen::prepend_ink(int x, int y, char32_t ch, Color fg) {
    screen_draw::Writer::prepend_ink(store_, x, y, ch, fg);
}

void Screen::clear_transparent() { screen_draw::Writer::clear_transparent(store_); }

const Cell& Screen::at(int x, int y) const { return store_.at(x, y); }

const std::vector<Screen::Ink>& Screen::inks(int x, int y) const { return store_.inks(x, y); }

const Cell& Screen::empty() { return ScreenStore::empty(); }

char32_t Screen::glyph_at(int x, int y) const {
    if (x < 0 || y < 0 || x >= store_.width() || y >= store_.height()) return 0;
    const Cell& cell = store_.at(x, y);
    if (cell.scale == 0) return 0;  // 被缩放块覆盖：这一格自身没有字形（它的字在上方/左方的头格）
    const Cell* source = &cell;
    if (cell.cols == 0) {
        // 续格：宽字符问哪一格都答得出（字形与字符都在头格上）
        const Cell& head = store_.at(x - 1, y);
        if (head.cols != 2) return 0;
        source = &head;
    }
    // 空格是内容（原样返回），只有控制字符算"这格没东西"
    if (source->ch < 32 || source->ch == 0x7F) return 0;
    return source->ch;
}

bool Screen::covered_by_scaled_block(int x, int y) const {
    return store_.covered_by_scaled_block(x, y);
}

char32_t Screen::quadrant_glyph(uint8_t bits) { return ScreenStore::quadrant_glyph(bits); }

Screen::SubCell Screen::cell_of(int x2, int y2) { return ScreenStore::cell_of(x2, y2); }

std::string Screen::to_text() const { return screen_text::to_text(*this); }

} // namespace phos

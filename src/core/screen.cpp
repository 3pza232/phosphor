#include "core/screen.hpp"

#include "core/screen_draw.hpp"
#include "core/screen_text.hpp"

namespace phos {

Screen::Screen(int w, int h) : w_(w), h_(h), cells_(static_cast<size_t>(w) * h) {}

void Screen::resize(int w, int h) {
    w_ = w;
    h_ = h;
    cells_.assign(static_cast<size_t>(w) * h, Cell{});
    inks_.clear();        // 键是 y*w_+x：尺寸一变，旧键就全错了
    plot_bits_.clear();
}

void Screen::put(int x, int y, char32_t ch, Color fg, Color bg, uint8_t scale) {
    screen_draw::Writer::put(*this, x, y, ch, fg, bg, scale);
}

bool Screen::scaled_block_of(int x, int y, int& head_x, int& head_y) const {
    if (x < 0 || x >= w_ || y < 0 || y >= h_) return false;
    // 头格只可能在 (x,y) 的左上：往上 < kMaxCellScale 行、往左 < 2*kMaxCellScale 列
    for (int hy = y; hy > y - kMaxCellScale && hy >= 0; --hy) {
        for (int hx = x; hx > x - 2 * kMaxCellScale && hx >= 0; --hx) {
            const Cell& head = cells_[static_cast<size_t>(index_of(hx, hy))];
            if (head.scale < 2) continue;
            const int bw = head.cols * head.scale;
            const int bh = head.scale;
            if (x >= hx && x < hx + bw && y >= hy && y < hy + bh) {
                head_x = hx;
                head_y = hy;
                return true;
            }
        }
    }
    return false;
}

std::vector<Screen::Ink>* Screen::inks_at(int x, int y) {
    if (inks_.empty() || x < 0 || y < 0 || x >= w_ || y >= h_) return nullptr;
    const auto it = inks_.find(index_of(x, y));
    return it == inks_.end() ? nullptr : &it->second;
}

const std::vector<Screen::Ink>& Screen::inks(int x, int y) const {
    static const std::vector<Ink> none;
    if (inks_.empty() || x < 0 || y < 0 || x >= w_ || y >= h_) return none;
    const auto it = inks_.find(index_of(x, y));
    return it == inks_.end() ? none : it->second;
}

bool Screen::blend(int x, int y, char32_t ch, Color fg) {
    return screen_draw::Writer::blend(*this, x, y, ch, fg);
}

void Screen::prepend_ink(int x, int y, char32_t ch, Color fg) {
    screen_draw::Writer::prepend_ink(*this, x, y, ch, fg);
}

void Screen::back(int x, int y, Color bg) {
    screen_draw::Writer::back(*this, x, y, bg);
}

char32_t Screen::quadrant_glyph(uint8_t bits) {
    // 用 \u 转义而不是直接写字符：字形表不该依赖源文件的编码，换编辑器也不会变样
    static const char32_t kGlyph[16] = {
        U' ',      U'\u2598', U'\u259D', U'\u2580', U'\u2596', U'\u258C',
        U'\u259E', U'\u259B', U'\u2597', U'\u259A', U'\u2590', U'\u259C',
        U'\u2584', U'\u2599', U'\u259F', U'\u2588',
    };
    return kGlyph[bits & 0x0F];
}

Screen::SubCell Screen::cell_of(int x2, int y2) {
    SubCell out;
    // 子位是"行、列"两位选出来的**一个**格子，不是"行的位 或 列的位" ——
    // 那样左下会算成 1|4 = 5（左半），墨多出一倍
    out.x = x2 / 2;
    out.y = y2 / 2;
    out.bit = static_cast<uint8_t>(1u << ((y2 & 1) * 2 + (x2 & 1)));
    return out;
}

void Screen::plot(int x2, int y2, Color fg) {
    screen_draw::Writer::plot(*this, x2, y2, fg);
}

void Screen::forget_plot_bits(int x, int y) {
    screen_draw::Writer::forget_plot_bits(*this, x, y);
}

void Screen::set(int x, int y, const Cell& cell) {
    screen_draw::Writer::set(*this, x, y, cell);
}

void Screen::clear_transparent() {
    screen_draw::Writer::clear_transparent(*this);
}

void Screen::print(int x, int y, std::string_view text, Color fg, Color bg, uint8_t scale) {
    screen_draw::Writer::print(*this, x, y, text, fg, bg, scale);
}

void Screen::fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg) {
    screen_draw::Writer::fill(*this, x, y, w, h, ch, fg, bg);
}

const Cell& Screen::empty() {
    static const Cell blank{};
    return blank;
}

const Cell& Screen::at(int x, int y) const {
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return empty();
    return cells_[static_cast<size_t>(index_of(x, y))];
}

char32_t Screen::glyph_at(int x, int y) const {
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return 0;  // 越界不算"这格有东西"
    const Cell& cell = at(x, y);
    if (cell.scale == 0) return 0;  // 被缩放块覆盖：这一格自身没有字形（它的字在上方/左方的头格）
    const Cell* source = &cell;
    if (cell.cols == 0) {
        // 续格：宽字符问哪一格都答得出（字形与字符都在头格上）
        const Cell& head = at(x - 1, y);
        if (head.cols != 2) return 0;
        source = &head;
    }
    // 空格是内容（原样返回），只有控制字符算"这格没东西"
    if (source->ch < 32 || source->ch == 0x7F) return 0;
    return source->ch;
}

bool Screen::covered_by_scaled_block(int x, int y) const {
    int head_x = 0, head_y = 0;
    return scaled_block_of(x, y, head_x, head_y);
}

std::string Screen::to_text() const { return screen_text::to_text(*this); }

} // namespace phos
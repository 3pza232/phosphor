#include "core/screen.hpp"

#include "core/text.hpp"

namespace phos {

const Color Color::black{0, 0, 0};
const Color Color::white{230, 230, 230};
const Color Color::gray{140, 140, 140};
const Color Color::dark_gray{70, 70, 70};
const Color Color::red{255, 80, 80};
const Color Color::green{80, 255, 120};
const Color Color::blue{90, 140, 255};
const Color Color::yellow{255, 230, 90};
const Color Color::cyan{90, 230, 230};
const Color Color::magenta{230, 90, 230};
const Color Color::orange{255, 160, 60};
const Color Color::purple{160, 100, 255};

Screen::Screen(int w, int h) : w_(w), h_(h), cells_(static_cast<size_t>(w) * h) {}

void Screen::resize(int w, int h) {
    w_ = w;
    h_ = h;
    cells_.assign(static_cast<size_t>(w) * h, Cell{});
}

namespace {

/// 把一格恢复成空白（保留颜色由调用方随后写入）
void blank(Cell& c) {
    c.ch = U' ';
    c.cols = 1;
}

} // namespace

void Screen::put(int x, int y, char32_t ch, Color fg, Color bg) {
    if (y < 0 || y >= h_) return;
    const int width = text::char_width(ch);

    // 先清理被覆盖的旧内容：写到续格上要连带清掉它的头格，
    // 写到全角头格上要连带清掉它的续格——否则会留下半个宽字符
    if (x >= 0 && x < w_) {
        Cell& target = cells_[static_cast<size_t>(y) * w_ + x];
        if (target.cols == 0 && x > 0) {
            Cell& head = cells_[static_cast<size_t>(y) * w_ + x - 1];
            blank(head);
            head.fg = fg;
            head.bg = bg;
        } else if (target.cols == 2 && x + 1 < w_) {
            Cell& tail = cells_[static_cast<size_t>(y) * w_ + x + 1];
            blank(tail);
            tail.fg = fg;
            tail.bg = bg;
        }
    }
    if (x < 0 || x >= w_ || width == 0) return;

    Cell& c = cells_[static_cast<size_t>(y) * w_ + x];
    c.ch = ch;
    c.fg = fg;
    c.bg = bg;
    c.cols = static_cast<uint8_t>(width);

    if (width == 2 && x + 1 < w_) {
        Cell& tail = cells_[static_cast<size_t>(y) * w_ + x + 1];
        tail.ch = U' ';
        tail.fg = fg;
        tail.bg = bg;
        tail.cols = 0;
    }
}

void Screen::print(int x, int y, std::string_view text, Color fg, Color bg) {
    for (char32_t ch : text::decode(text)) {
        const int width = text::char_width(ch);
        if (width == 0) continue;
        put(x, y, ch, fg, bg);
        x += width;
        if (x >= w_) return;  // 右侧已越界：后面的字符不会再显示
    }
}

void Screen::fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg) {
    const int width = text::char_width(ch);
    for (int row = y; row < y + h; ++row)
        for (int col = x; col < x + w; ++col) {
            // 用宽字符填充时按两格一组铺，最后若只剩一格则留空（不切半个字）
            if (width == 2 && (col - x) % 2 != 0) continue;
            if (width == 2 && col + 1 >= x + w) {
                put(col, row, U' ', fg, bg);
                continue;
            }
            put(col, row, ch, fg, bg);
        }
}

void Screen::clear(Color fg, Color bg) {
    for (auto& c : cells_) {
        c.ch = U' ';
        c.cols = 1;
        c.fg = fg;
        c.bg = bg;
    }
}

const Cell& Screen::at(int x, int y) const {
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return out_of_bounds_;
    return cells_[static_cast<size_t>(y) * w_ + x];
}

char32_t Screen::glyph_at(int x, int y) const {
    const Cell& cell = at(x, y);
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

std::string Screen::to_text() const {
    std::string out;
    out.reserve(static_cast<size_t>(w_ + 1) * h_);
    for (int y = 0; y < h_; ++y) {
        for (int x = 0; x < w_; ++x) {
            // 续格不输出：全角字符的 UTF-8 本身已经"占两格"，
            // 再补一个空格会把"中文"拆成"中 文"——agent 读屏和断言匹配都会变难。
            // 代价是含全角字符的行按字节数不再等于列数（终端里显示仍是两倍宽）。
            if (at(x, y).cols == 0) continue;
            const char32_t ch = glyph_at(x, y);
            if (ch == 0) {
                out += ' ';  // 空白/控制字符导出为空格，列宽不变
                continue;
            }
            text::append_utf8(out, ch);  // 全角字符按 UTF-8 原样导出
        }
        out += '\n';
    }
    return out;
}

} // namespace phos

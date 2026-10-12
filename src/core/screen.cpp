#include "core/screen.hpp"

#include "core/log.hpp"
#include "core/text.hpp"

#include <algorithm>

namespace phos {

Screen::Screen(int w, int h) : w_(w), h_(h), cells_(static_cast<size_t>(w) * h) {}

void Screen::resize(int w, int h) {
    w_ = w;
    h_ = h;
    cells_.assign(static_cast<size_t>(w) * h, Cell{});
    inks_.clear();        // 键是 y*w_+x：尺寸一变，旧键就全错了
    plot_bits_.clear();
}

void Screen::put(int x, int y, char32_t ch, Color fg, Color bg) {
    if (y < 0 || y >= h_) return;
    // 替换语义：这一格（以及被宽字符连带清理的邻格）的**笔迹与子位累积一并清掉** ——
    // put 是"把这一格改成这个字"，不是"再画一笔"（那是 blend / plot）。
    // 两张表都为空时在这里一次哈希都不做：不叠笔、不画半格的卡带零开销
    const auto drop_inks_at = [this](int cx, int cy) {
        if (cx < 0 || cx >= w_ || cy < 0 || cy >= h_) return;
        const int index = index_of(cx, cy);
        if (!inks_.empty()) inks_.erase(index);
        if (!plot_bits_.empty()) plot_bits_.erase(index);
    };
    // 背景色带"别动背景"标记时，先解析成该格当前背景（全屏唯一的解析点）。
    // 这一路同时意味着"不改变该格底色的存在性"——图层的字形覆盖靠它
    const bool keeps_bg = bg.keep;
    if (keeps_bg && x >= 0 && x < w_) {
        bg = cells_[static_cast<size_t>(index_of(x, y))].bg;
        bg.keep = false;
    }
    const int width = text::char_width(ch);
    // 给了底色就是"这一格的底存在"；带 keep 的写入不动它
    const uint8_t alpha = keeps_bg ? 0 : 255;

    // 先清理被覆盖的旧内容：写到续格上要连带清掉它的头格，
    // 写到全角头格上要连带清掉它的续格——否则会留下半个宽字符
    if (x >= 0 && x < w_) {
        Cell& target = cells_[static_cast<size_t>(index_of(x, y))];
        if (target.cols == 0 && x > 0) {
            Cell& head = cells_[static_cast<size_t>(index_of(x - 1, y))];
            head.clear_glyph();
            head.fg = fg;
            head.bg = bg;
            if (!keeps_bg) head.alpha = alpha;
            drop_inks_at(x - 1, y);
        } else if (target.cols == 2 && x + 1 < w_) {
            Cell& tail = cells_[static_cast<size_t>(index_of(x + 1, y))];
            tail.clear_glyph();
            tail.fg = fg;
            tail.bg = bg;
            if (!keeps_bg) tail.alpha = alpha;
            drop_inks_at(x + 1, y);
        }
    }
    if (x < 0 || x >= w_ || width == 0) return;

    Cell& c = cells_[static_cast<size_t>(index_of(x, y))];
    c.ch = ch;
    c.fg = fg;
    c.bg = bg;
    c.cols = static_cast<uint8_t>(width);
    if (!keeps_bg) c.alpha = alpha;
    drop_inks_at(x, y);

    // 续格顺手写上；落在最后一列时没有右邻格可写，最右侧就只剩头格——这是原始网格
    // 原有的行为，外壳自己的排版依赖它：贴边时看得见半个宽字，比整格少一个字好。
    // 卡带那一侧的 Surface 反过来——放不下就整格不写（见 core/surface.cpp）
    if (width == 2 && x + 1 < w_) {
        Cell& tail = cells_[static_cast<size_t>(index_of(x + 1, y))];
        // 即将被写成续格的那一格若原本是**全角头格**，它的续格在 x+2：不一起清掉就留下
        // 一个没有头的孤儿续格 —— 文本导出与两条渲染路都会跳过续格，整行因此少一列
        if (tail.cols == 2 && x + 2 < w_) {
            Cell& orphan = cells_[static_cast<size_t>(index_of(x + 2, y))];
            orphan.clear_glyph();
            orphan.fg = fg;
            orphan.bg = bg;
            if (!keeps_bg) orphan.alpha = alpha;
            drop_inks_at(x + 2, y);
        }
        tail.ch = U' ';
        tail.fg = fg;
        tail.bg = bg;
        tail.cols = 0;
        if (!keeps_bg) tail.alpha = alpha;
        drop_inks_at(x + 1, y);
    }
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
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return false;
    // 叠画只收半角字形：宽字要占两格（还要维护续格），那是 put 的活。
    // 收下却只画半格，等于给调用方一个看不见的错误
    if (text::char_width(ch) != 1) {
        log::warn("blend 只支持半角字形（这一笔被忽略）");
        return false;
    }
    const int index = index_of(x, y);
    Cell& cell = cells_[static_cast<size_t>(index)];
    if (cell.ch == U' ') {
        // 这一格原本没有字形：新的一笔直接成为最前面那一笔（不进笔迹表）
        cell.ch = ch;
        cell.fg = fg;
        return true;
    }
    if (cell.ch == ch) {
        // 同一个字形再画一次：改的是这一笔的颜色，不值得为它多记一笔
        cell.fg = fg;
        return true;
    }
    // 新的一笔**在最前面**（后画的压在上面，与纸上作画一致），原先那一笔退进笔迹表。
    // 文本导出取最前面那一笔，所以文本与画面说的是同一件事
    const std::vector<Ink>* list = inks_at(x, y);
    const int used = list ? static_cast<int>(list->size()) : 0;
    if (used + 2 > kMaxInks) {
        // 只报一次：这一格满了是**每分钟几十次**的常态（雨雪密处），
        // 每次都写日志会把日志冲成噪声，真正要看的那条反而被埋掉
        if (!warned_ink_cap_) {
            warned_ink_cap_ = true;
            log::warn("同一格叠画已达上限（kMaxInks），后续被拒绝的笔不再逐条报出");
        }
        return false;
    }
    const Ink below{cell.ch, cell.fg};
    cell.ch = ch;
    cell.fg = fg;
    // 字形槽换人了：这一格的子位累积随之作废，否则之后再来半笔会拿旧的位掩码去合成
    if (!plot_bits_.empty()) plot_bits_.erase(index);
    inks_[index].push_back(below);  // 表里越靠前越深，末尾就是"刚退下来的那一笔"
    return true;
}

void Screen::prepend_ink(int x, int y, char32_t ch, Color fg) {
    if (ch == U' ' || x < 0 || y < 0 || x >= w_ || y >= h_) return;
    if (text::char_width(ch) != 1) return;  // 同 blend：叠画只收半角
    std::vector<Ink>& list = inks_[index_of(x, y)];
    list.insert(list.begin(), Ink{ch, fg});
    // 满了就丢**最深**的一笔：新的一笔是表层，丢了它等于这一格根本没画上
    while (static_cast<int>(list.size()) + 1 > kMaxInks) {
        list.pop_back();
        log::warn("同一格叠画已达上限（kMaxInks），最深的一笔被丢弃");
    }
}

void Screen::back(int x, int y, Color bg) {
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return;
    // 底色省略（kKeepBg）= 保留该格原有底色：什么都不做。
    // 浮层（ui.region）的 back / back_rect 正是靠这条默认值实现"只改字形、不动底"；
    // 若把 keep 当普通颜色写下去，会在画面上糊出一块白底（kKeepBg 的 rgb 是白）
    if (bg.keep) return;
    Cell& cell = cells_[static_cast<size_t>(index_of(x, y))];
    cell.bg = bg;
    cell.alpha = 255;  // "写了底色"就是"这一格的底存在"，与 put 给底色同义
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
    if (x2 < 0 || y2 < 0 || x2 >= w_ * 2 || y2 >= h_ * 2) return;
    const SubCell at = cell_of(x2, y2);
    plot_bit(at.x, at.y, at.bit, fg);
}

void Screen::plot_bit(int x, int y, uint8_t bit, Color fg) {
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return;
    if ((bit & 0x0F) == 0) return;
    const int index = index_of(x, y);
    Cell& cell = cells_[static_cast<size_t>(index)];
    // 宽字（头格或续格）上不落半笔：改掉头格的字形会留下半截续格，改续格则根本没有槽位
    if (cell.cols != 1) return;
    plot_bits_[index] |= static_cast<uint8_t>(bit & 0x0F);
    const uint8_t bits = plot_bits_[index];
    cell.ch = quadrant_glyph(bits);
    cell.fg = fg;
    // 只动字形槽：底色（alpha）与笔迹表都不碰 —— 半笔落在别人画的格子上是叠加，不是替换
}

void Screen::forget_plot_bits(int x, int y) {
    if (plot_bits_.empty() || x < 0 || y < 0 || x >= w_ || y >= h_) return;
    plot_bits_.erase(index_of(x, y));
}

void Screen::set(int x, int y, const Cell& cell) {
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return;
    const int index = index_of(x, y);
    cells_[static_cast<size_t>(index)] = cell;
    // 字形槽换人了，子位累积作废
    if (!plot_bits_.empty()) plot_bits_.erase(index);
    // 搬来的是**可见字形**：笔迹保留 —— 层合成"下层的话 + 上层的话"叠加就靠它。
    // 搬来的是**空格**：这一格从此没有字形，压在它下面的笔迹也一并抹掉
    // （层用空格抹掉下层字形时正是这个语义；留着笔迹会在空位上留下两笔游墨）
    if (cell.ch == U' ' && !inks_.empty()) inks_.erase(index);
}

void Screen::clear_transparent() {
    Cell transparent_cell;
    transparent_cell.alpha = 0;
    std::fill(cells_.begin(), cells_.end(), transparent_cell);
    inks_.clear();
    plot_bits_.clear();
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

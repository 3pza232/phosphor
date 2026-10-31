#include "core/screen_store.hpp"

namespace phos {

ScreenStore::ScreenStore(int w, int h) : w_(w), h_(h), cells_(static_cast<size_t>(w) * h) {}

void ScreenStore::resize(int w, int h) {
    w_ = w;
    h_ = h;
    cells_.assign(static_cast<size_t>(w) * h, Cell{});
    inks_.clear();  // 键是 y*w_+x：尺寸一变，旧键就全错了
    plot_bits_.clear();
}

const Cell& ScreenStore::empty() {
    static const Cell blank{};
    return blank;
}

const Cell& ScreenStore::at(int x, int y) const {
    if (x < 0 || y < 0 || x >= w_ || y >= h_) return empty();
    return cells_[static_cast<size_t>(index_of(x, y))];
}

std::vector<Ink>* ScreenStore::inks_at(int x, int y) {
    if (inks_.empty() || x < 0 || y < 0 || x >= w_ || y >= h_) return nullptr;
    const auto it = inks_.find(index_of(x, y));
    return it == inks_.end() ? nullptr : &it->second;
}

const std::vector<Ink>& ScreenStore::inks(int x, int y) const {
    static const std::vector<Ink> none;
    if (inks_.empty() || x < 0 || y < 0 || x >= w_ || y >= h_) return none;
    const auto it = inks_.find(index_of(x, y));
    return it == inks_.end() ? none : it->second;
}

bool ScreenStore::scaled_block_of(int x, int y, int& head_x, int& head_y) const {
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

bool ScreenStore::covered_by_scaled_block(int x, int y) const {
    int head_x = 0, head_y = 0;
    return scaled_block_of(x, y, head_x, head_y);
}

ScreenStore::SubCell ScreenStore::cell_of(int x2, int y2) {
    SubCell out;
    // 子位是"行、列"两位选出来的**一个**格子，不是"行的位 或 列的位" ——
    // 那样左下会算成 1|4 = 5（左半），墨多出一倍
    out.x = x2 / 2;
    out.y = y2 / 2;
    out.bit = static_cast<uint8_t>(1u << ((y2 & 1) * 2 + (x2 & 1)));
    return out;
}

char32_t ScreenStore::quadrant_glyph(uint8_t bits) {
    // 用 \u 转义而不是直接写字符：字形表不该依赖源文件的编码，换编辑器也不会变样
    static const char32_t kGlyph[16] = {
        U' ',      U'\u2598', U'\u259D', U'\u2580', U'\u2596', U'\u258C',
        U'\u259E', U'\u259B', U'\u2597', U'\u259A', U'\u2590', U'\u259C',
        U'\u2584', U'\u2599', U'\u259F', U'\u2588',
    };
    return kGlyph[bits & 0x0F];
}

} // namespace phos

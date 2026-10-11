#include "core/layered_screen.hpp"

#include <algorithm>

namespace phos {

namespace {

/// 这一格是否被该层用到：给过底色、写过字形、或作为宽字续格占位。
/// 三者皆无 = 空白透传，合成时整格跳过
bool uses_cell(const Cell& cell) {
    return cell.alpha != 0 || cell.ch != U' ' || cell.cols == 0;
}

/// 合成后的宽字符归一。一格只有一个字形槽，而宽字占两格：
/// 上层若压掉了某宽字的续格（或留下无头的续格），这个字就渲染不出来，
/// 于是把不成对的格子降级成空格——底色留着，只是不再有字
void normalize_wide_chars(Screen& target, int ox, int oy, int w, int h) {
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const Cell& cell = target.at(ox + x, oy + y);
            if (cell.cols != 2) continue;
            const bool tail_ok = x + 1 < w && target.at(ox + x + 1, oy + y).cols == 0;
            if (tail_ok) continue;
            Cell fixed = cell;
            fixed.clear_glyph();
            target.set(ox + x, oy + y, fixed);
        }
    }
    // 上一步抹掉的头格会把自己的续格变成孤儿，所以这一遍放在后面：
    // 它顺带清掉那些续格，两遍合起来就是"宽字要么完整、要么不出现在画面上"
    for (int y = 0; y < h; ++y) {
        for (int x = 0; x < w; ++x) {
            const Cell& cell = target.at(ox + x, oy + y);
            if (cell.cols != 0) continue;
            const bool head_ok = x > 0 && target.at(ox + x - 1, oy + y).cols == 2;
            if (head_ok) continue;
            Cell fixed = cell;
            fixed.clear_glyph();
            target.set(ox + x, oy + y, fixed);
        }
    }
}

} // namespace

void LayeredScreen::reset(int w, int h) {
    layers_.clear();
    width_ = w > 0 ? w : kContentW;
    height_ = h > 0 ? h : kContentH;
}

void LayeredScreen::clear_all() {
    for (Layer& layer : layers_) layer.cells.clear_transparent();
}

Layer* LayeredScreen::find(const std::string& name) {
    for (Layer& layer : layers_)
        if (layer.name == name) return &layer;
    return nullptr;
}

const Layer* LayeredScreen::find(const std::string& name) const {
    for (const Layer& layer : layers_)
        if (layer.name == name) return &layer;
    return nullptr;
}

Layer* LayeredScreen::create(const std::string& name, int z) {
    if (Layer* existing = find(name)) return existing;
    if (static_cast<int>(layers_.size()) >= kMaxLayers) return nullptr;

    Layer& layer = layers_.emplace_back();
    layer.name = name;
    layer.z = z;
    layer.cells = Screen(width_, height_);
    // 新层"什么都没有"：空格 + alpha=0，未写到的格在合成时透传下层
    layer.cells.clear_transparent();
    return &layer;
}

bool LayeredScreen::remove(const std::string& name) {
    for (auto it = layers_.begin(); it != layers_.end(); ++it) {
        if (it->name != name) continue;
        layers_.erase(it);
        return true;
    }
    return false;
}

std::vector<const Layer*> LayeredScreen::ordered() const {
    std::vector<const Layer*> out;
    out.reserve(layers_.size());
    for (const Layer& layer : layers_) out.push_back(&layer);
    std::stable_sort(out.begin(), out.end(),
                     [](const Layer* a, const Layer* b) { return a->z < b->z; });
    return out;
}

bool LayeredScreen::merge_over(Screen& target, int origin_x, int origin_y) {
    if (layers_.empty()) return false;
    if (std::none_of(layers_.begin(), layers_.end(), [](const Layer& l) { return l.visible; }))
        return false;

    const std::vector<const Layer*> order = ordered();
    // 所有层同尺寸（由 reset 统一给定），按第一层定循环上界
    const int w = std::min(width_, order.front()->cells.width());
    const int h = std::min(height_, order.front()->cells.height());

    for (const Layer* layer : order) {
        if (!layer->visible) continue;
        const Screen& src = layer->cells;
        for (int y = 0; y < h; ++y) {
            for (int x = 0; x < w; ++x) {
                const Cell& cell = src.at(x, y);
                if (!uses_cell(cell)) continue;

                const int px = origin_x + x, py = origin_y + y;
                Cell merged = target.at(px, py);
                // 这一层自己的叠笔：它们在本层字形之后、下层内容之前（合成按"先深后浅"），
                // 所以倒着 prepend 一遍，让最早的那一笔落在最深处
                const std::vector<Screen::Ink>& src_inks = src.inks(x, y);
                for (auto it = src_inks.rbegin(); it != src_inks.rend(); ++it) {
                    target.prepend_ink(px, py, it->ch, it->fg);
                }
                // 下层原有的字形：这一层画的是**可见字形**时，把下层那一笔压到后面去 ——
                // 于是"下层的字 + 上层的字"在合成结果里是**叠加**（两笔都画），
                // 而不是后来的把先前的顶掉。这一层只写空格时照旧（空格 = 抹掉下层字形）
                if (cell.ch != U' ' && merged.ch != U' ' && merged.ch != cell.ch) {
                    target.prepend_ink(px, py, merged.ch, merged.fg);
                }
                // 这一格的字形换人了：下层的**子位累积**随之作废，
                // 否则之后再来半笔会拿旧的位掩码去合成，画出谁也没要过的形状。
                // 用空格抹掉下层字形这一路同样要作废 —— 掩码记住的是"哪几个子位有笔"，
                // 字形没了，这份记账也不再成立
                target.forget_plot_bits(px, py);
                // 字形槽：这层用到了这格，就以它的内容为准
                merged.ch = cell.ch;
                merged.fg = cell.fg;
                merged.cols = cell.cols;
                // 底色槽：只有给过底色才覆盖。没给就保留底下的——"字压在世界底上"
                if (cell.alpha != 0) {
                    merged.bg = cell.bg;
                    merged.alpha = 255;
                }
                target.set(px, py, merged);
            }
        }
    }

    normalize_wide_chars(target, origin_x, origin_y, w, h);
    return true;
}

} // namespace phos

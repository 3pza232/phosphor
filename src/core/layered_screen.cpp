#include "core/layered_screen.hpp"

#include <algorithm>

namespace phos {

namespace {

/// 这一格是否被该层用到：给过底色、写过字形、或作为宽字续格占位。
/// 三者皆无 = 空白透传，合成时整格跳过
bool uses_cell(const Cell& cell) {
    return cell.alpha != 0 || cell.ch != U' ' || cell.cols == 0;
}

/// 抹掉一格的字形（保留底色与存在性）：宽字被上层截断时用
void drop_glyph(Cell& cell) {
    cell.ch = U' ';
    cell.cols = 1;
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
            drop_glyph(fixed);
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
            drop_glyph(fixed);
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

                Cell merged = target.at(origin_x + x, origin_y + y);
                // 字形槽：这层用到了这格，就以它的内容为准（空格 = 抹掉下层的字形）
                merged.ch = cell.ch;
                merged.fg = cell.fg;
                merged.cols = cell.cols;
                // 底色槽：只有给过底色才覆盖。没给就保留底下的——"字压在世界底上"
                if (cell.alpha != 0) {
                    merged.bg = cell.bg;
                    merged.alpha = 255;
                }
                target.set(origin_x + x, origin_y + y, merged);
            }
        }
    }

    normalize_wide_chars(target, origin_x, origin_y, w, h);
    return true;
}

} // namespace phos

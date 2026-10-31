#include "ui/layout.hpp"

#include "core/text.hpp"

#include <algorithm>

namespace phos::ui {

namespace {

int border_width(const Node& node) { return node.props.border == Border::none ? 0 : 1; }

int pad_w(const Node& node) { return node.props.padding.l + node.props.padding.r; }
int pad_h(const Node& node) { return node.props.padding.t + node.props.padding.b; }

int outer_w(const Node& node) {
    const int w = node.natural_w + node.props.margin.l + node.props.margin.r;
    return w < 0 ? 0 : w;
}

int outer_h(const Node& node) {
    const int h = node.natural_h + node.props.margin.t + node.props.margin.b;
    return h < 0 ? 0 : h;
}

/// 文本按宽度折行后的行数（未指定宽度时只有一行）
int wrapped_lines(const Props& props, int width) {
    if (props.overflow != Overflow::wrap || width <= 0) return props.lines > 0 ? props.lines : 1;
    const auto rows = text::wrap(props.text, static_cast<size_t>(width));
    const int cap = props.lines > 0 ? props.lines : static_cast<int>(rows.size());
    return std::min<int>(cap, static_cast<int>(rows.size()) == 0 ? 1 : static_cast<int>(rows.size()));
}

} // namespace

bool focusable_kind(Kind kind) {
    switch (kind) {
        case Kind::list:
        case Kind::option:
        case Kind::checkbox:
        case Kind::field:
        case Kind::button: return true;
        default: return false;
    }
}

std::vector<int> table_column_widths(const Props& props, int available) {
    int n = static_cast<int>(props.columns.size());
    for (const auto& row : props.rows) n = std::max(n, static_cast<int>(row.size()));
    n = std::max(n, static_cast<int>(props.widths.size()));
    if (n <= 0) return {};
    std::vector<int> widths(static_cast<size_t>(n), 0);
    for (int i = 0; i < n; ++i) {
        if (i < static_cast<int>(props.widths.size()) && props.widths[static_cast<size_t>(i)] > 0) {
            widths[static_cast<size_t>(i)] = props.widths[static_cast<size_t>(i)];
            continue;
        }
        int natural = 0;
        if (i < static_cast<int>(props.columns.size()))
            natural = text::display_width(props.columns[static_cast<size_t>(i)]);
        for (const auto& row : props.rows)
            if (i < static_cast<int>(row.size()))
                natural = std::max(natural, text::display_width(row[static_cast<size_t>(i)]));
        widths[static_cast<size_t>(i)] = natural;
    }
    constexpr int kGap = 2;
    int total = kGap * (n - 1);
    for (int w : widths) total += w;
    if (available > total && n > 0) {
        // 显式 widths 是"固定宽"；只有自适应列（缺省/0）参与余量摊分。
        // 全固定列时右侧留白——想铺满就给 0，而不是让固定列被悄悄拉宽
        std::vector<int> auto_columns;
        for (int i = 0; i < n; ++i)
            if (i >= static_cast<int>(props.widths.size()) ||
                props.widths[static_cast<size_t>(i)] <= 0)
                auto_columns.push_back(i);
        if (!auto_columns.empty()) {
            const int extra = (available - total) / static_cast<int>(auto_columns.size());
            for (int index : auto_columns) widths[static_cast<size_t>(index)] += extra;
            widths[static_cast<size_t>(auto_columns.back())] +=
                (available - total) % static_cast<int>(auto_columns.size());
        }
    }
    return widths;
}

Size measure(Node& node, int avail_w, const Theme& theme) {
    const Props& props = node.props;
    int content_w = 0;
    int content_h = 0;

    switch (node.kind) {
        case Kind::scroll: {
            const int child_avail = std::max(0, avail_w - pad_w(node) - border_width(node) * 2);
            int content = 0;
            int width = 0;
            bool first = true;
            for (Node& child : node.children) {
                const Size size = measure(child, child_avail, theme);
                if (!first) content += std::max(0, props.gap);
                first = false;
                content += size.h + child.props.margin.t + child.props.margin.b;
                width = std::max(width, size.w + child.props.margin.l + child.props.margin.r);
            }
            content_w = props.width > 0 ? props.width : width;
            content_h = props.height > 0 ? props.height : content;
            break;
        }
        case Kind::grid: {
            const int cols = props.cols > 0 ? props.cols : std::max(1, static_cast<int>(node.children.size()));
            const int gap = std::max(0, props.gap);
            const int rows = (static_cast<int>(node.children.size()) + cols - 1) / cols;
            const int cell_avail = avail_w > 0 ? std::max(0, (avail_w - gap * (cols - 1)) / cols) : 0;
            int cell_w = 0;
            std::vector<int> row_h(static_cast<size_t>(rows), 0);
            for (size_t i = 0; i < node.children.size(); ++i) {
                Node& child = node.children[i];
                const Size size = measure(child, cell_avail, theme);
                cell_w = std::max(cell_w, size.w + child.props.margin.l + child.props.margin.r);
                const int row = static_cast<int>(i) / cols;
                row_h[static_cast<size_t>(row)] =
                    std::max(row_h[static_cast<size_t>(row)],
                             size.h + child.props.margin.t + child.props.margin.b);
            }
            int height = gap * (rows > 0 ? rows - 1 : 0);
            for (int h : row_h) height += h;
            content_w = avail_w > 0 ? avail_w : cols * cell_w + gap * (cols - 1);
            content_h = height;
            break;
        }
        case Kind::column:
        case Kind::box:
        case Kind::row: {
            const int child_avail = std::max(0, avail_w - pad_w(node) - border_width(node) * 2);
            int main = 0;
            int cross = 0;
            bool first = true;
            for (Node& child : node.children) {
                if (child.props.absolute) {
                    measure(child, child_avail, theme);
                    continue;
                }
                const Size size = measure(child, child_avail, theme);
                const int grow_main = node.kind == Kind::row ? outer_w(child) : outer_h(child);
                if (!first) main += std::max(0, props.gap);
                first = false;
                main += grow_main;
                cross = std::max(cross, node.kind == Kind::row ? outer_h(child) : outer_w(child));
            }
            content_w = node.kind == Kind::row ? main : cross;
            content_h = node.kind == Kind::row ? cross : main;
            break;
        }
        case Kind::text: {
            const int scale = props.scale > 0 ? props.scale : 1;
            const int full = text::display_width(props.text);
            content_w = props.width > 0 ? props.width : full * scale;
            const int wrap_width = props.width > 0 ? props.width / scale : 0;
            content_h = wrapped_lines(props, wrap_width) * scale;
            if (props.overflow == Overflow::wrap && props.width <= 0 && avail_w > 0) {
                const int cols = std::max(1, avail_w / scale);
                content_w = avail_w;
                content_h = wrapped_lines(props, cols) * scale;
            }
            break;
        }
        case Kind::divider:
            content_w = props.width > 0 ? props.width : std::max(0, avail_w);
            content_h = 1;
            break;
        case Kind::spacer:
            content_w = props.width;
            content_h = props.height;
            break;
        case Kind::list: {
            int width = 0;
            for (const std::string& item : props.items)
                width = std::max(width, text::display_width(item) + props.indent);
            content_w = props.width > 0 ? props.width : width;
            content_h = props.height > 0 ? props.height : static_cast<int>(props.items.size());
            break;
        }
        case Kind::table: {
            const auto widths = table_column_widths(props, 0);
            int width = 0;
            for (size_t i = 0; i < widths.size(); ++i)
                width += widths[i] + (i > 0 ? 2 : 0);
            content_w = props.width > 0 ? props.width : width;
            const int header = props.columns.empty() ? 0 : 2;  // 表头 + 分隔线
            content_h = header + static_cast<int>(props.rows.size());
            break;
        }
        case Kind::stat: {
            const int label_w = props.label_w > 0 ? props.label_w : theme.metrics.label_w;
            content_w = props.width > 0
                            ? props.width
                            : label_w + 1 + text::display_width(props.value);
            content_h = 1;
            break;
        }
        case Kind::option:
        case Kind::button:
            content_w = props.width > 0 ? props.width
                                        : props.indent + text::display_width(props.text);
            content_h = 1;
            break;
        case Kind::checkbox:
            content_w = props.width > 0 ? props.width
                                        : props.indent + 4 + text::display_width(props.text);
            content_h = 1;
            break;
        case Kind::field:
            content_w = props.width > 0 ? props.width : 20;
            content_h = 1;
            break;
        case Kind::bar:
            content_w = props.width > 0 ? props.width : 20;
            content_h = 1;
            break;
        case Kind::hint: {
            int width = 0;
            for (size_t i = 0; i < props.items.size(); i += 2) {
                if (i > 0) width += 2;
                width += 1 + text::display_width(props.items[i]) + 2;
                if (i + 1 < props.items.size()) width += text::display_width(props.items[i + 1]);
            }
            content_w = props.width > 0 ? props.width : width;
            content_h = 1;
            break;
        }
    }

    int w = content_w + pad_w(node) + border_width(node) * 2;
    int h = content_h + pad_h(node) + border_width(node) * 2;
    if (props.width > 0) w = props.width + pad_w(node) + border_width(node) * 2;
    if (props.height > 0) h = props.height + pad_h(node) + border_width(node) * 2;
    if (props.min_w > 0) w = std::max(w, props.min_w);
    if (props.min_h > 0) h = std::max(h, props.min_h);
    if (props.max_w > 0) w = std::min(w, props.max_w);
    if (props.max_h > 0) h = std::min(h, props.max_h);
    if (w < 0) w = 0;
    if (h < 0) h = 0;

    node.natural_w = w;
    node.natural_h = h;
    node.focusable = focusable_kind(node.kind) && props.enabled;
    return Size{w, h};
}

void arrange(Node& node, Rect rect, const Theme& theme) {
    node.rect = rect;
    const int border = border_width(node);
    node.inner = Rect{rect.x + border + node.props.padding.l,
                      rect.y + border + node.props.padding.t,
                      std::max(0, rect.w - border * 2 - pad_w(node)),
                      std::max(0, rect.h - border * 2 - pad_h(node))};

    if (node.kind == Kind::scroll) {
        // 视口：子项按列排，y/x 减去显式偏移；超出视口的部分由绘制裁剪
        const int gap = std::max(0, node.props.gap);
        int cursor = node.inner.y - std::max(0, node.props.scroll);
        const int offset_x = std::max(0, node.props.scroll_x);
        // 内容更宽才启用横向自然宽（可滚）；否则按视口宽拉伸，保持纵向列表的旧布局
        int widest = 0;
        for (const Node& child : node.children) {
            const int natural = child.props.width > 0 ? child.props.width : child.natural_w;
            widest = std::max(widest, natural + child.props.margin.l + child.props.margin.r);
        }
        const bool horizontal_overflow = widest > node.inner.w;
        bool first = true;
        for (Node& child : node.children) {
            if (child.props.absolute) {
                arrange(child,
                        Rect{node.inner.x + child.props.x - offset_x, cursor + child.props.y, 0, 0},
                        theme);
                continue;
            }
            if (!first) cursor += gap;
            first = false;
            // 横向：显式 width 优先，否则用子项自然宽（可超出视口，由裁剪负责）
            int child_w = child.props.width > 0 ? child.props.width
                                                : (horizontal_overflow ? child.natural_w
                                                                       : node.inner.w);
            int child_h = child.props.height > 0 ? child.props.height : child.natural_h;
            arrange(child, Rect{node.inner.x + child.props.margin.l - offset_x, cursor,
                                std::max(0, child_w), std::max(0, child_h)}, theme);
            cursor += child_h + child.props.margin.t + child.props.margin.b;
        }
        return;
    }

    if (node.kind == Kind::grid) {
        const int cols = node.props.cols > 0
                             ? node.props.cols
                             : std::max(1, static_cast<int>(node.children.size()));
        const int gap = std::max(0, node.props.gap);
        const int cell_w = std::max(0, (node.inner.w - gap * (cols - 1)) / cols);
        const int rows = (static_cast<int>(node.children.size()) + cols - 1) / cols;
        // 行高按"内容高 + 上下外边距"取最大值：与 measure() 同一套尺寸语义，
        // 否则子项的自然高不等时下一行会压到上一行的 margin 里
        std::vector<int> row_h(static_cast<size_t>(rows), 0);
        for (size_t i = 0; i < node.children.size(); ++i) {
            Node& child = node.children[i];
            const int row = static_cast<int>(i) / cols;
            const int content_h = child.props.height > 0 ? child.props.height : child.natural_h;
            row_h[static_cast<size_t>(row)] =
                std::max(row_h[static_cast<size_t>(row)],
                         content_h + child.props.margin.t + child.props.margin.b);
        }
        int y = node.inner.y;
        for (int row = 0; row < rows; ++row) {
            for (int col = 0; col < cols; ++col) {
                const size_t index = static_cast<size_t>(row) * static_cast<size_t>(cols) +
                                     static_cast<size_t>(col);
                if (index >= node.children.size()) break;
                Node& child = node.children[index];
                const int content_h = child.props.height > 0 ? child.props.height : child.natural_h;
                // 外边距是"元素盒子之外"的间距：格宽/行高里扣掉它，元素矩形本身变小、位置内缩
                const int child_w = std::max(0, cell_w - child.props.margin.l - child.props.margin.r);
                const int x = node.inner.x + col * (cell_w + gap) + child.props.margin.l;
                arrange(child, Rect{x, y + child.props.margin.t, child_w, content_h}, theme);
            }
            y += row_h[static_cast<size_t>(row)] + gap;
        }
        return;
    }

    if (node.kind != Kind::column && node.kind != Kind::row && node.kind != Kind::box) return;

    // 绝对定位的子项：按父内容区偏移，不参与流
    for (Node& child : node.children) {
        if (!child.props.absolute) continue;
        const int w = child.props.width > 0 ? child.props.width : child.natural_w;
        const int h = child.props.height > 0 ? child.props.height : child.natural_h;
        arrange(child, Rect{node.inner.x + child.props.x, node.inner.y + child.props.y, w, h},
                theme);
    }

    const bool horizontal = node.kind == Kind::row;
    const int main_avail = horizontal ? node.inner.w : node.inner.h;

    // 先扣掉固定部分，再把剩余空间按 grow 分给可变项（余数给最后一项，保证不丢格）
    int fixed = 0;
    int grow_total = 0;
    bool first = true;
    for (Node& child : node.children) {
        if (child.props.absolute) continue;
        if (!first) fixed += std::max(0, node.props.gap);
        first = false;
        fixed += horizontal ? outer_w(child) : outer_h(child);
        if (child.props.grow > 0) grow_total += child.props.grow;
    }
    int leftover = std::max(0, main_avail - fixed);
    int grow_left = grow_total;

    int cursor = horizontal ? node.inner.x : node.inner.y;
    first = true;
    for (Node& child : node.children) {
        if (child.props.absolute) continue;
        if (!first) cursor += std::max(0, node.props.gap);
        first = false;

        int child_w = child.props.width > 0 ? child.props.width : child.natural_w;
        int child_h = child.props.height > 0 ? child.props.height : child.natural_h;

        // 剩余空间按 grow 权重分配；余数给最后一项，保证不多不少刚好铺满
        if (child.props.grow > 0 && grow_left > 0) {
            const int add = (child.props.grow == grow_left)
                                ? leftover
                                : leftover * child.props.grow / grow_left;
            leftover -= add;
            grow_left -= child.props.grow;
            if (horizontal)
                child_w += add;
            else
                child_h += add;
        }

        const int cross_avail = horizontal ? node.inner.h : node.inner.w;
        int cross = horizontal ? child_h : child_w;
        if (child.props.align_h == Align::stretch) {
            if (horizontal) {
                if (child.props.height <= 0) child_h = std::max(child_h, cross_avail);
            } else {
                if (child.props.width <= 0 && child_w < cross_avail) child_w = cross_avail;
            }
        } else if (child.props.align_h == Align::center) {
            // 由绘制方按 inner 对齐；这里只把宽度定下来
        }

        int x = node.inner.x + child.props.margin.l;
        int y = node.inner.y + child.props.margin.t;
        if (horizontal) {
            x = cursor + child.props.margin.l;
            y = node.inner.y + child.props.margin.t;
            if (child.props.align_h == Align::start) y = node.inner.y + child.props.margin.t;
        } else {
            y = cursor + child.props.margin.t;
            if (child.props.align_h == Align::center)
                x = node.inner.x + (node.inner.w - child_w) / 2;
            else if (child.props.align_h == Align::end)
                x = node.inner.x + node.inner.w - child_w - child.props.margin.r;
        }

        arrange(child, Rect{x, y, std::max(0, child_w), std::max(0, child_h)}, theme);
        if (horizontal)
            cursor += child_w + child.props.margin.l + child.props.margin.r;
        else
            cursor += child_h + child.props.margin.t + child.props.margin.b;
    }
}

void collect_focusables(Node& node, std::vector<Node*>& out) {
    if (node.focusable) out.push_back(&node);
    for (Node& child : node.children) collect_focusables(child, out);
}

} // namespace phos::ui
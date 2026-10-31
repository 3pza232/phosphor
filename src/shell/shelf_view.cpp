#include "shell/shelf_view.hpp"

#include "core/text.hpp"
#include "ui/frame.hpp"
#include "ui/layout.hpp"

#include <algorithm>
#include <utility>

namespace phos::shelf {

namespace {

// 布局常量集中于本模块
constexpr int kMarginX = 2;
constexpr int kListPlateX = 38;
constexpr int kListPlateW = 38;
constexpr int kListPlateH = 18;
constexpr int kListInfoH = 8;
constexpr int kIconCenterY = 12;
constexpr int kIconSpacing = 26;      // 视窗样式邻位横向间距
constexpr int kIconNeighborDrop = 6;  // 邻位图标下沉行数
constexpr float kNeighborBrightness = 0.75f;
constexpr int kTitleY = 26;           // 视窗样式名称行（相对内容区）

// 铭牌**固定尺寸**（按出厂最大图标 18x8 + 内边距）：每张卡带的框一样大，图标在其中居中。
// 不再让框随图标大小伸缩——否则各卡带框大框小，名字长时还会顶穿窄框。名字单独画在下方，
// 因此框顶不留名字
constexpr int kPlateW = 24, kPlateH = 12;                  // 当前卡带
constexpr int kNeighborPlateW = 12, kNeighborPlateH = 6;   // 邻位（缩一半）

// 组件层的屏 id 与元素 id：视图的输入由外壳处理（它才知道搜索过滤后的整表），
// 这里只做"声明 → 排布 → 绘制"，所以每次绘制用一份一次性的状态表
constexpr const char* kContentScreen = "shell.shelf.content";
constexpr const char* kListId = "shelf/list";
constexpr const char* kInfoTextId = "shelf/info_text";
constexpr const char* kTitleId = "shelf/title";
constexpr const char* kDescId = "shelf/desc";
constexpr const char* kEmptyId = "shelf/empty";
constexpr const char* kEmptyHintId = "shelf/empty_hint";

/// 以 (cx, cy) 为中心的固定尺寸铭牌矩形
ui::Rect plate_at(int cx, int cy, int w, int h) {
    return ui::Rect{cx - w / 2, cy - h / 2, w, h};
}

/// 把整屏矩形改写成"相对内容区"的绝对定位矩形（组件的 x/y 是相对父内容区的）
ui::Node& place(ui::Node& root, const ui::Rect& content, const ui::Rect& rect, ui::Kind kind,
                std::string id) {
    ui::Node& node = root.add(kind, std::move(id));
    node.props.absolute = true;
    node.props.x = rect.x - content.x;
    node.props.y = rect.y - content.y;
    node.props.width = rect.w;
    node.props.height = rect.h;
    return node;
}

std::vector<std::string> labels_of(const std::vector<CartInfo>& carts, Lang lang) {
    std::vector<std::string> labels;
    labels.reserve(carts.size());
    for (const CartInfo& cart : carts) labels.push_back(display_name(cart, lang));
    return labels;
}

void draw_list(Screen& screen, const ui::Rect& content, const ShelfView& view,
               const ui::Style& style) {
    const auto& carts = *view.carts;
    const int plate_x = content.x + kListPlateX;
    const CartInfo& cart = carts[static_cast<size_t>(view.cursor)];

    // 左：卡带列表。滚动/高亮/截断由 list 组件负责（旧实现是 ui::menu 自带一份滚动）
    ui::State state;
    ui::Frame frame(kContentScreen, state, view.theme, content, nullptr);
    const ui::Rect list_rect{content.x + kMarginX + 2, content.y + 3,
                             kListPlateX - kMarginX - 6, content.h - 6};
    ui::Node& list = place(frame.root(), content, list_rect, ui::Kind::list, kListId);
    list.props.items = labels_of(carts, view.lang);
    list.props.indent = 0;
    list.props.text_gap = 1;

    // 视图只给"选中第几张"：可见首行沿用旧 menu 的规则（选中项贴底才滚），
    // 光标与滚动都是组件状态，绘制前显式灌入
    ui::WidgetState& widget = state.screen(kContentScreen).widgets[kListId];
    widget.cursor = view.cursor;
    const int visible = std::max(1, list_rect.h);
    int first = view.cursor >= visible ? view.cursor - visible + 1 : 0;
    first = std::min(first, std::max(0, static_cast<int>(carts.size()) - visible));
    widget.scroll = std::max(0, first);

    // 简介：折行/行数由 text 组件统一处理（旧实现是 ui::text_block）
    const ui::Rect info{plate_x, content.y + 3 + kListPlateH, kListPlateW, kListInfoH};
    ui::Node& info_text =
        place(frame.root(), content, ui::Rect{info.x + 2, info.y + 2, info.w - 4, info.h - 3},
              ui::Kind::text, kInfoTextId);
    info_text.props.text = cart.desc.get(view.lang == Lang::en);
    info_text.props.overflow = ui::Overflow::wrap;
    info_text.props.lines = info.h - 3;

    // 右：铭牌（边框 + 字符画图标）与简介框的框体。铭牌是"框 + 图标"的复合体，
    // 图标本来就要自绘，框沿用同一套绘制原语，免得一块铭牌由两套绘制拼起来
    const ui::Rect plate{plate_x, content.y + 3, kListPlateW, kListPlateH};
    ui::frame(screen, plate, display_name(cart, view.lang), style);
    ui::icon(screen, cart.icon_rows, cart.icon_colors, plate.x + plate.w / 2,
             plate.y + plate.h / 2, 1, 1.0f, style.accent);
    ui::frame(screen, info, tr(view.lang, Msg::shelf_info), style);

    frame.run();
    frame.paint(screen);
}

void draw_window(Screen& screen, const ui::Rect& content, const ShelfView& view,
                 const ui::Style& style) {
    const auto& carts = *view.carts;
    const int count = static_cast<int>(carts.size());
    const int center_x = content.x + content.w / 2;
    const float slide = view.position - static_cast<float>(view.cursor);

    // 邻位预览：只显示真实存在的相邻卡带（不循环）；首位无左邻、末位无右邻
    ui::Style neighbor_style = style;
    neighbor_style.frame = style.dim;
    for (int k = -1; k <= 1; ++k) {
        const int index = view.cursor + k;
        if (index < 0 || index >= count) continue;

        const float dx = (static_cast<float>(k) - slide) * kIconSpacing;
        const int x = center_x + static_cast<int>(dx);
        if (k != 0 && (x < content.x - 8 || x > content.right() + 8)) continue;

        const bool current = (k == 0);
        const CartInfo& cart = carts[static_cast<size_t>(index)];
        const int step = current ? 1 : 2;
        const int cy = content.y + kIconCenterY + (current ? 0 : kIconNeighborDrop);

        if (!current)
            ui::frame(screen, plate_at(x, cy, kNeighborPlateW, kNeighborPlateH), "", neighbor_style);
        ui::icon(screen, cart.icon_rows, cart.icon_colors, x, cy, step,
                 current ? 1.0f : kNeighborBrightness, style.accent);
    }

    // 当前卡带：图标铭牌（尺寸固定、框顶不留名——名字单独画在下方一行）
    const CartInfo& cart = carts[static_cast<size_t>(view.cursor)];
    const std::string name = display_name(cart, view.lang);
    ui::frame(screen, plate_at(center_x, content.y + kIconCenterY, kPlateW, kPlateH), "", style);

    // 名字（高亮）与简介：居中/折行/截断交给组件，版面行坐标仍取自本模块常量
    ui::State state;
    ui::Frame frame(kContentScreen, state, view.theme, content, nullptr);
    const std::string title = count > 1 ? "<  " + name + "  >" : name;
    ui::Node& title_node =
        place(frame.root(), content, ui::Rect{content.x, content.y + kTitleY, content.w, 1},
              ui::Kind::text, kTitleId);
    title_node.props.text = title;
    title_node.props.align_h = ui::Align::center;
    title_node.props.accent = true;

    ui::Node& desc =
        place(frame.root(), content,
              ui::Rect{content.x + 8, content.y + kTitleY + 3, content.w - 16, 2}, ui::Kind::text,
              kDescId);
    desc.props.text = cart.desc.get(view.lang == Lang::en);
    desc.props.overflow = ui::Overflow::wrap;
    desc.props.lines = 2;

    frame.run();
    frame.paint(screen);
}

void draw_empty(Screen& screen, const ui::Rect& content, const ShelfView& view) {
    ui::State state;
    ui::Frame frame(kContentScreen, state, view.theme, content, nullptr);
    const int y = content.y + content.h / 2;
    ui::Node& line =
        place(frame.root(), content, ui::Rect{content.x, y, content.w, 1}, ui::Kind::text, kEmptyId);
    line.props.text = tr(view.lang, Msg::shelf_empty);
    line.props.align_h = ui::Align::center;
    ui::Node& hint = place(frame.root(), content, ui::Rect{content.x, y + 2, content.w, 1},
                           ui::Kind::text, kEmptyHintId);
    hint.props.text = tr(view.lang, Msg::shelf_empty_hint);
    hint.props.align_h = ui::Align::center;
    hint.props.dim = true;
    frame.run();
    frame.paint(screen);
}

} // namespace

std::string display_name(const CartInfo& cart, Lang lang) {
    const std::string& name = cart.name.get(lang == Lang::en);
    return cart.error.empty() ? name : name + tr(lang, Msg::shelf_broken);
}

void draw_builtin(Screen& screen, const ui::Rect& content, const ShelfView& view,
                  const ui::Style& style) {
    if (!view.carts || view.carts->empty()) {
        draw_empty(screen, content, view);
        return;
    }
    if (view.style == ShelfStyle::list)
        draw_list(screen, content, view, style);
    else
        draw_window(screen, content, view, style);
}

void draw(Screen& screen, const ui::Rect& content, const ShelfView& view, const ui::Style& style,
          const Painter& painter) {
    // 空列表：主机自己画提示，绝不调用内容包（包不负责"没有内容"这件事）
    if (!view.carts || view.carts->empty()) {
        draw_empty(screen, content, view);
        return;
    }
    // 内容包接管内容区：仅当视图标记为外部且画家确实存在。画家缺失即回退内置——
    // 包损坏/被删时内容区仍画得出来
    if (view.external && painter) {
        painter(screen, content, view, style);
        return;
    }
    draw_builtin(screen, content, view, style);
}

} // namespace phos::shelf

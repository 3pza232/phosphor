#include "shell/shelf_view.hpp"

#include "core/text.hpp"

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

void draw_list(Screen& screen, const ui::Rect& content, const ShelfView& view,
               const ui::Style& style) {
    const auto& carts = *view.carts;
    const int plate_x = content.x + kListPlateX;

    // 左：卡带列表（统一 menu 原语，自带滚动）
    std::vector<std::string> labels;
    labels.reserve(carts.size());
    for (const auto& cart : carts) labels.push_back(display_name(cart, view.lang));

    const ui::Rect list{content.x + kMarginX + 2, content.y + 3,
                        kListPlateX - kMarginX - 6, content.h - 6};
    ui::menu(screen, list, labels, view.cursor, style);

    // 右：图标铭牌（带边框）+ 简介框
    const CartInfo& cart = carts[static_cast<size_t>(view.cursor)];
    const ui::Rect plate{plate_x, content.y + 3, kListPlateW, kListPlateH};
    ui::frame(screen, plate, display_name(cart, view.lang), style);
    ui::icon(screen, cart.icon_rows, cart.icon_colors, plate.x + plate.w / 2,
             plate.y + plate.h / 2, 1, 1.0f, style.accent);

    const ui::Rect info{plate_x, plate.bottom() + 1, kListPlateW, kListInfoH};
    ui::frame(screen, info, tr(view.lang, Msg::shelf_info), style);
    ui::text_block(screen, info.x + 2, info.y + 2, info.w - 4, cart.desc.get(view.lang == Lang::en),
                   info.h - 3, style);
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
            ui::frame(screen, icon_plate_rect(cart, x, cy, step, 2), "", neighbor_style);
        ui::icon(screen, cart.icon_rows, cart.icon_colors, x, cy, step,
                 current ? 1.0f : kNeighborBrightness, style.accent);
    }

    // 当前卡带：图标铭牌（标题嵌在上边框）
    const CartInfo& cart = carts[static_cast<size_t>(view.cursor)];
    const std::string name = display_name(cart, view.lang);
    ui::frame(screen, icon_plate_rect(cart, center_x, content.y + kIconCenterY, 1, 3),
              name, style);

    const std::string title = count > 1 ? "<  " + name + "  >" : name;
    ui::print_centered(screen, content.y + kTitleY, title, style.accent, style.bg,
                       content.x, content.w);
    ui::text_block(screen, content.x + 8, content.y + kTitleY + 3, content.w - 16,
                   cart.desc.get(view.lang == Lang::en), 2, style);
}

void draw_empty(Screen& screen, const ui::Rect& content, const ui::Style& style, Lang lang) {
    ui::print_centered(screen, content.y + content.h / 2, tr(lang, Msg::shelf_empty),
                       style.fg, style.bg, content.x, content.w);
    ui::print_centered(screen, content.y + content.h / 2 + 2, tr(lang, Msg::shelf_empty_hint),
                       style.dim, style.bg, content.x, content.w);
}

} // namespace

std::string display_name(const CartInfo& cart, Lang lang) {
    const std::string& name = cart.name.get(lang == Lang::en);
    return cart.error.empty() ? name : name + tr(lang, Msg::shelf_broken);
}

ui::Rect icon_plate_rect(const CartInfo& cart, int center_x, int center_y, int step,
                         int padding) {
    int rows = static_cast<int>(cart.icon_rows.size());
    int cols = 0;
    for (const auto& row : cart.icon_rows)
        cols = cols > static_cast<int>(row.size()) ? cols : static_cast<int>(row.size());

    const int w = (cols + step - 1) / step + padding * 2;
    const int h = (rows + step - 1) / step + padding * 2;
    return ui::Rect{center_x - w / 2, center_y - h / 2, w, h};
}

void draw(Screen& screen, const ui::Rect& content, const ShelfView& view,
          const ui::Style& style) {
    if (!view.carts || view.carts->empty()) {
        draw_empty(screen, content, style, view.lang);
        return;
    }
    if (view.style == ShelfStyle::list)
        draw_list(screen, content, view, style);
    else
        draw_window(screen, content, view, style);
}

} // namespace phos::shelf

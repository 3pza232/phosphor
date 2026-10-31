#include "ui/theme.hpp"

#include "core/palette.hpp"
#include "core/skin.hpp"

namespace phos::ui {

Theme theme_from_skin(const Skin& skin) {
    Theme theme;
    theme.bg = skin.ui_bg;
    theme.surface = skin.ui_bg;
    theme.surface_alt = skin.panel;
    theme.text = skin.ui_fg;
    theme.text_dim = skin.ui_dim;
    theme.accent = skin.accent;
    theme.border = skin.frame;
    theme.border_focus = skin.accent;
    theme.selection_bg = skin.panel;
    theme.selection_fg = skin.accent;
    theme.disabled = scale_color(skin.ui_dim, 0.7f);

    // 可选 ui 覆盖：只合并 skin.lua 显式声明过的 token；未声明保持 Theme 默认。
    // 卡带主题 theme_from_palette 不走这条，故卡带 UI 永远不受 skin.ui 影响。
    const SkinUi& overrides = skin.ui;
    if (overrides.glyphs.h) theme.glyphs.h = *overrides.glyphs.h;
    if (overrides.glyphs.v) theme.glyphs.v = *overrides.glyphs.v;
    if (overrides.glyphs.tl) theme.glyphs.tl = *overrides.glyphs.tl;
    if (overrides.glyphs.tr) theme.glyphs.tr = *overrides.glyphs.tr;
    if (overrides.glyphs.bl) theme.glyphs.bl = *overrides.glyphs.bl;
    if (overrides.glyphs.br) theme.glyphs.br = *overrides.glyphs.br;
    if (overrides.glyphs.cursor) theme.glyphs.cursor = *overrides.glyphs.cursor;
    if (overrides.glyphs.bullet) theme.glyphs.bullet = *overrides.glyphs.bullet;
    if (overrides.glyphs.scroll_thumb) theme.glyphs.scroll_thumb = *overrides.glyphs.scroll_thumb;
    if (overrides.glyphs.scroll_track) theme.glyphs.scroll_track = *overrides.glyphs.scroll_track;
    if (overrides.glyphs.table_rule) theme.glyphs.table_rule = *overrides.glyphs.table_rule;
    if (overrides.metrics.pad_x) theme.metrics.pad_x = *overrides.metrics.pad_x;
    if (overrides.metrics.pad_y) theme.metrics.pad_y = *overrides.metrics.pad_y;
    if (overrides.metrics.gap) theme.metrics.gap = *overrides.metrics.gap;
    if (overrides.metrics.label_w) theme.metrics.label_w = *overrides.metrics.label_w;
    if (overrides.metrics.indent) theme.metrics.indent = *overrides.metrics.indent;
    return theme;
}

Theme theme_from_palette(const Palette& palette) {
    auto slot = [&palette](PaletteSlot which) {
        return palette.slots[static_cast<size_t>(which)];
    };
    Theme theme;
    theme.bg = slot(PaletteSlot::black);
    theme.surface = slot(PaletteSlot::black);
    theme.surface_alt = slot(PaletteSlot::dark_gray);
    theme.text = slot(PaletteSlot::white);
    theme.text_dim = slot(PaletteSlot::dark_gray);
    theme.accent = slot(PaletteSlot::green);
    theme.border = slot(PaletteSlot::gray);
    theme.border_focus = slot(PaletteSlot::green);
    theme.selection_bg = slot(PaletteSlot::dark_gray);
    theme.selection_fg = slot(PaletteSlot::yellow);
    theme.warning = slot(PaletteSlot::yellow);
    theme.danger = slot(PaletteSlot::red);
    theme.disabled = scale_color(slot(PaletteSlot::gray), 0.6f);
    return theme;
}

} // namespace phos::ui

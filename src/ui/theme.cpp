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

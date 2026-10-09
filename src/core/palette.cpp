#include "core/palette.hpp"

namespace phos {

Palette builtin_palette() {
    Palette p;
    p.slots[static_cast<size_t>(PaletteSlot::black)]     = Color::black;
    p.slots[static_cast<size_t>(PaletteSlot::white)]     = Color::white;
    p.slots[static_cast<size_t>(PaletteSlot::gray)]      = Color::gray;
    p.slots[static_cast<size_t>(PaletteSlot::dark_gray)] = Color::dark_gray;
    p.slots[static_cast<size_t>(PaletteSlot::red)]       = Color::red;
    p.slots[static_cast<size_t>(PaletteSlot::green)]     = Color::green;
    p.slots[static_cast<size_t>(PaletteSlot::blue)]      = Color::blue;
    p.slots[static_cast<size_t>(PaletteSlot::yellow)]    = Color::yellow;
    p.slots[static_cast<size_t>(PaletteSlot::cyan)]      = Color::cyan;
    p.slots[static_cast<size_t>(PaletteSlot::magenta)]   = Color::magenta;
    p.slots[static_cast<size_t>(PaletteSlot::orange)]    = Color::orange;
    p.slots[static_cast<size_t>(PaletteSlot::purple)]    = Color::purple;
    return p;
}

} // namespace phos

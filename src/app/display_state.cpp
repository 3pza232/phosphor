#include "app/display_state.hpp"

namespace phos {

void DisplayState::resize_screen(const Skin& skin) {
    display_.screen.resize(skin.grid_w(), skin.grid_h());
}

void DisplayState::reset_chrome(int content_w, int content_h) {
    display_.chrome.resize(content_w, content_h);
    display_.chrome.clear_transparent();
}

void DisplayState::apply_crt(int level, const Palette& palette) {
    crt_ = crt_params_for_level(level, palette);
}

} // namespace phos

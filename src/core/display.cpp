#include "core/display.hpp"

#include "render/renderer.hpp"

namespace phos {

void Display::present(Renderer& renderer, const LayeredScreen& layers, int origin_x, int origin_y,
                      bool layered, bool overlay) const {
    renderer.draw(layered ? base : screen);
    if (layered) renderer.draw_layers(layers, origin_x, origin_y);
    if (overlay) renderer.draw_overlay(chrome, origin_x, origin_y);
}

} // namespace phos

#include "core/display.hpp"

#include "core/composition.hpp"
#include "render/renderer.hpp"

namespace phos {

void Display::present(Renderer& renderer, const FrameView& view) const {
    if (!view.base) return;
    renderer.draw(*view.base);
    if (view.layers) renderer.draw_layers(*view.layers, view.content.x, view.content.y);
    if (view.overlay && view.chrome) renderer.draw_overlay(*view.chrome, view.content.x, view.content.y);
}

} // namespace phos

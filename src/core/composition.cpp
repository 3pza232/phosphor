#include "core/composition.hpp"

namespace phos {

FrameView compose_frame(const Display& display, const LayeredScreen& layers,
                        const ui::Rect& content, bool playing, bool panel_visible) {
    FrameView view;
    view.layered = frame_uses_layers(playing, layers.active());
    view.overlay = frame_uses_overlay(playing, panel_visible);
    view.base = frame_base(display, view.layered);
    view.layers = frame_layers(layers, view.layered);
    view.chrome = &display.chrome;
    view.content = content;
    return view;
}

} // namespace phos

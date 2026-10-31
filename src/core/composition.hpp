#pragma once

#include "core/display.hpp"
#include "core/ui.hpp"

namespace phos {

struct FrameView;

/// 一帧的组成（**纯数据**，不依赖 Renderer）：哪块当底、是否叠图层、是否叠主机 chrome、
/// 内容区几何。present / CPU 截图都从这里取参数，不再各自拼 layered/overlay。
struct FrameView {
    const Screen* base = nullptr;          // 底：有层用 Display::base，无层用 Display::screen
    const LayeredScreen* layers = nullptr;  // 有层合成时指向层集；否则 nullptr
    const Screen* chrome = nullptr;         // 主机 chrome（present 叠层用；始终指向 Display::chrome）
    ui::Rect content;                       // 内容区几何（原点只取 content.x / content.y）
    bool layered = false;                   // 本帧是否走图层合成
    bool overlay = false;                   // 本帧是否该叠主机 chrome（playing && 侧栏可见）
};

/// 决策规则（单独可测的纯函数，也是 compose_frame 的唯一实现来源）
inline bool frame_uses_layers(bool playing, bool layers_active) {
    return playing && layers_active;
}
inline bool frame_uses_overlay(bool playing, bool panel_visible) {
    return playing && panel_visible;
}
/// 有层时底用 Display::base，否则用文本整屏 Display::screen
inline const Screen* frame_base(const Display& display, bool layered) {
    return layered ? &display.base : &display.screen;
}
inline const LayeredScreen* frame_layers(const LayeredScreen& layers, bool layered) {
    return layered ? &layers : nullptr;
}
/// CPU 截图/像素光栅化的 overlay：无层时 screen 已含分隔线、不需要再叠 chrome；
/// 有层时 base 快照在写分隔线之前，必须补 chrome 才与窗口一致
inline const Screen* frame_cpu_overlay(const FrameView& view) {
    return view.layered && view.overlay ? view.chrome : nullptr;
}

/// 从三块面 + 层集 + 内容区几何算出这一帧的组成（唯一决策点）。
/// playing / panel_visible 是外部游戏状态；层是否真的在用由 LayeredScreen::active() 决定
FrameView compose_frame(const Display& display, const LayeredScreen& layers,
                        const ui::Rect& content, bool playing, bool panel_visible);

} // namespace phos

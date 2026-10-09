#pragma once

#include "core/screen.hpp"
#include "core/ui.hpp"
#include "shell/messages.hpp"

namespace phos::boot {

/// 内置兜底开机自检（一个启动动画包都没有时用它）。
/// 与 settings_view / tape_view 同一套路：屏幕模块不认识 Shell 的内部状态，
/// 几何与语言都由调用方填进上下文。
struct BootContext {
    Lang lang = Lang::zh;
    ui::Rect content;
    float elapsed = 0.0f;   // 进入开机动画后的秒数
    float interval = 0.4f;  // 相邻两行之间隔多少秒
};

/// 画一帧自检画面（逐行打出 + 行尾光标闪烁）
void draw(Screen& screen, const BootContext& ctx, const ui::Style& style);

} // namespace phos::boot

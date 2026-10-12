#pragma once

#include "core/screen.hpp"
#include "core/ui.hpp"

namespace phos::effects {

/// 插卡瞬间的电压闪烁：内容区掠过几条不稳定的亮带（带子在底色上"透出"，不铺黑底）
/// （调用方每帧传入递增的 frame 作为随机源，保证不引入额外状态）
void draw_insert_flash(Screen& screen, const ui::Rect& content, Color bright, Color accent,
                       long frame);

/// 拔卡时的画面收缩：progress 0→1，亮线自两侧收拢后熄灭（清字形、保留机身底色）
void draw_eject_collapse(Screen& screen, const ui::Rect& content, float progress, Color bright);

} // namespace phos::effects

#pragma once

#include "core/layered_screen.hpp"
#include "core/screen.hpp"

namespace phos {

class Renderer;

/// 主机显示面：三块字符网格 + 它们的合成顺序。**集中一处**，因为三者本是同一件事的三面：
///   * `screen` —— 卡带纹理视图（底层 + 各图层的**文本**合成，一格一个字形）；文本导出与
///     agent 读的就是它
///   * `base`   —— 图层合成**之前**的那一帧（壳 + 卡带画的世界）；有图层的卡带渲染走它
///   * `chrome` —— 主机 chrome（侧栏分隔线等）：画在**所有图层之上**，否则会被卡带世界盖住
///
/// 只吃 `Renderer` 与自己，不碰 `HostContext`——于是它是纯展示单元，不反向依赖 API 层。
struct Display {
    Screen screen;
    Screen base;
    Screen chrome;

    /// 把三块面合成到窗口：底（有图层时用 base）→ 逐层叠画 → chrome。
    /// 顺序与原点同离屏截图（见 render/screen_image 的 overlay 参数），两路才一致。
    /// `layered` = 本帧是否走图层合成；`overlay` = 是否叠 chrome（仅"正在玩且有侧栏"）
    void present(Renderer& renderer, const LayeredScreen& layers, int origin_x, int origin_y,
                 bool layered, bool overlay) const;
};

} // namespace phos

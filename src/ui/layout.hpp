#pragma once

#include "ui/element.hpp"
#include "ui/theme.hpp"

#include <vector>

namespace phos::ui {

struct Size {
    int w = 0, h = 0;
};

/// 测量：写入 node.natural_w / natural_h（边框+内边距+内容，不含 margin）。
/// avail_w 是父内容区可用宽度（用于折行与"撑满"判断）。
Size measure(Node& node, int avail_w, const Theme& theme);

/// 排布：把 node 放到 rect（含边框，不含 margin），递归写 children 的 rect/inner。
void arrange(Node& node, Rect rect, const Theme& theme);

/// 按**视觉顺序**收集可聚焦元素（受 enabled 约束）。输入导航与 agent 观测共用它。
void collect_focusables(Node& node, std::vector<Node*>& out);

/// 该种类是否天然可聚焦（list / option / checkbox / field / button）。
bool focusable_kind(Kind kind);

} // namespace phos::ui

#pragma once

#include "cart/cartridge.hpp"
#include "core/screen.hpp"
#include "core/ui.hpp"
#include "shell/messages.hpp"

#include <string>
#include <vector>

namespace phos {

/// 卡带架样式
enum class ShelfStyle { list, window };

/// 卡带架视图状态（渲染所需的全部输入，不含外壳其它状态）
struct ShelfView {
    const std::vector<CartInfo>* carts = nullptr;
    ShelfStyle style = ShelfStyle::window;
    int cursor = 0;      // 当前选中下标
    float position = 0.0f;  // 平滑滑动位置（视窗样式的动效状态）
    Lang lang = Lang::zh;   // 界面语言：卡带架自己的文案（"信息"/"（无卡带）"…）也要跟着切
};

namespace shelf {

/// 渲染卡带架主体（列表样式为列表+信息窗；视窗样式为带框图标轮播）
void draw(Screen& screen, const ui::Rect& content, const ShelfView& view, const ui::Style& style);

/// 图标铭牌矩形（按图标尺寸与缩放步长推导）
ui::Rect icon_plate_rect(const CartInfo& cart, int center_x, int center_y, int step, int padding);

/// 卡带在列表/轮播中的显示名（损坏卡带的标记随界面语言）
std::string display_name(const CartInfo& cart, Lang lang);

} // namespace shelf
} // namespace phos

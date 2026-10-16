#pragma once

#include "cart/cartridge.hpp"
#include "core/screen.hpp"
#include "core/ui.hpp"
#include "shell/messages.hpp"

#include <functional>
#include <string>
#include <vector>

namespace phos {

/// 卡带架内置样式
enum class ShelfStyle { list, window };

/// 卡带架视图状态（渲染所需的全部输入，不含外壳其它状态）
struct ShelfView {
    const std::vector<CartInfo>* carts = nullptr;
    ShelfStyle style = ShelfStyle::window;
    int cursor = 0;      // 当前选中下标
    float position = 0.0f;  // 平滑滑动位置（视窗样式的动效状态）
    Lang lang = Lang::zh;   // 界面语言：卡带架自己的文案（"信息"/"（无卡带）"…）也要跟着切
    /// 内容区是否由外部画家（内容包）接管。为真且有画家时，`shelf::draw` 把内容区整个
    /// 交给画家；画家为空则照旧走内置样式（内容包坏掉/缺失时的回退路径）
    bool external = false;
};

namespace shelf {

/// 卡带架内容区的绘制回调（由 Shell 持有、App 设置）：签名与内置 `draw` 同形，
/// 于是"包画"与"内置画"在调用点没有分别
using Painter = std::function<void(Screen&, const ui::Rect&, const ShelfView&, const ui::Style&)>;

/// 渲染卡带架主体。空列表一律由主机画"无卡带"提示（不调用画家）；
/// 其余情况：external + 画家 → 画家作画，否则内置样式（列表 / 视窗轮播）
void draw(Screen& screen, const ui::Rect& content, const ShelfView& view, const ui::Style& style,
          const Painter& painter = {});

/// 内置样式（列表 / 视窗轮播）的绘制。抽成独立入口，供画家在内容包出错时**当帧**回退
void draw_builtin(Screen& screen, const ui::Rect& content, const ShelfView& view,
                  const ui::Style& style);

/// 卡带在列表/轮播中的显示名（损坏卡带的标记随界面语言）
std::string display_name(const CartInfo& cart, Lang lang);

} // namespace shelf
} // namespace phos

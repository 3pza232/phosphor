#pragma once

#include "core/ui.hpp"

namespace phos {

struct HostContext;

/// 卡带侧界面配色：取自当前主题声明的色板（与 `phos.color` 同源，换主题时同步变化）。
/// 界面绘制与"绘制区域"共用这一条派生路径，避免配色在第二处重新推导。
ui::Style cart_style(const HostContext& host);

} // namespace phos


namespace sol { class state; }

namespace phos {

struct HostContext;

/// 注册 phos.ui.* 组件 API（边框/浮窗/菜单/进度条/正文/精灵/导航/绘制区域）。
/// 组件层与主机外壳共用 core/ui 的同一套绘制原语，
/// 因此卡带界面与系统界面在视觉上天然一致。
void register_ui_api(sol::state& lua, HostContext& host);

} // namespace phos

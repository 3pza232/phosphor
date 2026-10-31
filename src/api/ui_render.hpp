#pragma once

namespace sol {
class state;
}

namespace phos {

struct HostContext;

/// 注册卡带侧声明式界面：`phos.ui.render(spec)` 与配套查询。
/// 它把 ui/ 的组件树绑定给 Lua——与主机外壳共用同一实现与主题派生路径，
/// 所以卡带界面与系统界面在布局/焦点/配色上天然一致。
void register_cart_ui_api(sol::state& lua, HostContext& host);

} // namespace phos

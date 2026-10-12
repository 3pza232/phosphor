#pragma once

namespace sol { class state; }

namespace phos {
struct HostContext;

/// 向 Lua 沙箱注册 phos.net（局域网联机：开房/加入/收发/发现）。见 docs/api-reference.md。
void register_net_api(sol::state& lua, HostContext& host);

} // namespace phos

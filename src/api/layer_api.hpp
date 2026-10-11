#pragma once

#include "api/host_api.hpp"

#include <sol/sol.hpp>

namespace phos {

/// 注册 `phos.layer`（图层：可选的新能力，见 design/layers-and-api.md）。
/// 不建层的卡带完全不受影响：主循环里连一次合并都不会发生
void register_layer_api(sol::state& lua, HostContext& host);

} // namespace phos

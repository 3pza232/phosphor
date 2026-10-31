#pragma once

namespace sol {
class state;
}

namespace phos {

struct HostContext;

/// 注册卡带场景栈 API：`phos.scene.push/pop/top/depth/clear` 与三个查询。
/// 语义见 docs/api-reference.md 的「phos.scene」一节。
void register_scene_api(sol::state& lua, HostContext& host);

} // namespace phos

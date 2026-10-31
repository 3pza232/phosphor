#pragma once

namespace sol {
class state;
}

namespace phos {

struct HostContext;

/// 注册 `phos.score`：卡带侧的"排行榜"（TOP N 分数，写进卡带存档）。
/// 与卡带自己用 `phos.save` 拼一个逗号串相比，这层负责：键长/值域校验、
/// 排序与截断、存档不可用时的内存降级——每张卡带各写一遍迟早会在边界上分叉。
void register_score_api(sol::state& lua, HostContext& host);

} // namespace phos

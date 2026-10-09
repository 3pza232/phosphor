#pragma once

#include "cart/cartridge.hpp"

#include <string>
#include <vector>

namespace phos {

/// 卡带的机器可读描述，**只此一处定义**，两处消费：CLI 的 `--scan --json`
/// 与控制通道的 `carts.scan` / `state.query.carts`。
/// 两边各写一份字段集必然漂移：同一张卡带在 CLI 与通道里字段不一样，agent 只能各猜一套。
///
/// 字段：`id` / `name` / `version` / `author` / `sidebar_w` / `wants_save` / `path` /
/// `error`（无错误时为 `null`）
std::string cart_json(const CartInfo& info);

/// JSON 数组形式的卡带列表（形如 `[{…},{…}]`，不含外层键名）
std::string cart_list_json(const std::vector<CartInfo>& carts);

} // namespace phos

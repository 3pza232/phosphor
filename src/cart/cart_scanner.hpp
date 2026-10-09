#pragma once

#include "cart/cartridge.hpp"

#include <string>
#include <vector>

namespace phos {

/// 扫描目录，收集全部卡带（散装目录与 .phos 文件）的元信息。
/// 损坏卡带也会出现在列表中（error 非空），由界面标灰展示。
std::vector<CartInfo> scan_carts(const std::string& dir);

} // namespace phos

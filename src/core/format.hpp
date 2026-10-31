#pragma once

#include <string>

namespace phos::format {

/// 分数：千分位分隔（31200 → "31,200"）。负号保留在数字前。
/// 卡带侧 `phos.text.score()` 与主机侧展示共用这一份——各写一份迟早会在
/// "四位数怎么断"上不一致。
std::string score(long long value);

/// 计时：754 → "12:34"；3661 → "1:01:01"（超过一小时才出现小时段）。
/// 负数按 0 处理（剩余时间被算成负数是常见的边界，不该显示 "-1:-5"）。
std::string clock(long long seconds);

/// 百分比：0.4567 → "45.7%"；digits 取 0..2（缺省 1）。nan/inf 按 0 处理。
std::string percent(double ratio, int digits = 1);

} // namespace phos::format

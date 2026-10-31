#pragma once

#include "core/screen.hpp"

#include <string>

namespace phos::screen_text {

/// 把字符网格导出为纯文本（agent 接口与 --dump-screen 的唯一实现）。
///
/// 为什么在 Screen 之外：导出是"消费网格"的纯格式化，不需要摸 Screen 的存储/写入路径；
/// 拆成独立单元后，屏幕存储的演进（S7 后续：笔迹/子位/宽字状态）不必带着文本导出一起改。
///
/// 实现见 screen_text.cpp；行为契约与拆分前逐字节一致：
///   - 全角字符原样按 UTF-8 导出，续格不产出字符；
///   - 被缩放块覆盖的格（scale == 0）不产出字形，导出为空格，列宽不变；
///   - 空白/控制字符导出为单个空格；每行以换行符结尾（含最后一行）。
std::string to_text(const Screen& screen);

} // namespace phos::screen_text

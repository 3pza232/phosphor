#pragma once

#include <cstdint>
#include <limits>
#include <string>
#include <string_view>
#include <vector>

namespace phos::text {

/// 码点的显示宽度：0 = 不占格（控制字符，写屏时跳过）；1 = 半角；2 = 全角。
///
/// 判定依据是 Unicode East Asian Width 的 W/F 区间（CJK 汉字、假名、全角标点、
/// 谚文等）。**这个宽度在写屏之前就必须算准**——网格对齐、居中、折行、
/// 侧栏裁剪全部依赖它，算错一个字，整行就歪。
int char_width(char32_t ch);

/// UTF-8 → 码点序列。非法字节按 U'?' 处理，绝不吐出半个字符。
std::vector<char32_t> decode(std::string_view text);

/// 字符串的显示宽度（格数，不是字节数）
int display_width(std::string_view text);

/// 码点 → UTF-8 追加到 out（画面导出与 phos.screen.get 共用）
void append_utf8(std::string& out, char32_t ch);

/// 按显示宽度截断；切点落在码点边界上，不留半个字符，也不切开宽字符
std::string truncate(std::string_view text, int max_cols);

/// 按显示宽度折行，最多 max_lines 行（被截断时末行追加 "..."）
std::vector<std::string> wrap(std::string_view in, size_t width, size_t max_lines);

/// 不限行数的折行：调用方自己决定显示几行（例如只画固定高度的窗口）
inline std::vector<std::string> wrap(std::string_view in, size_t width) {
    return wrap(in, width, std::numeric_limits<size_t>::max());
}

/// 右侧补空格到指定显示宽度；本就超宽则先按宽度截断
std::string pad_right(std::string_view in, size_t width);

/// 居中的起始列（基于起始列 base 与可用列宽 span，按显示宽度居中）
int centered_x(std::string_view in, int base, int span);

/// 文本层的"删除"事件：输入层用它表示退格，界面层用它消费。
/// **这是唯一约定**——不要在窗口层、界面层、文档里各写一遍 '\b' 字面量。
inline constexpr char kBackspace = '\b';

/// 删除末尾一个**码点**。按字节 pop_back 会把中文删成半个序列（非法 UTF-8），
/// 所以删字符的地方一律用这个。
inline void pop_back_utf8(std::string& text) {
    while (!text.empty() && (static_cast<unsigned char>(text.back()) & 0xC0) == 0x80)
        text.pop_back();  // 先吃掉续字节
    if (!text.empty()) text.pop_back();  // 再吃掉首字节
}

} // namespace phos::text

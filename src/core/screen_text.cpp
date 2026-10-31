#include "core/screen_text.hpp"

#include "core/text.hpp"

#include <string>

namespace phos::screen_text {

std::string to_text(const Screen& screen) {
    std::string out;
    out.reserve(static_cast<size_t>(screen.width() + 1) * static_cast<size_t>(screen.height()));
    for (int y = 0; y < screen.height(); ++y) {
        for (int x = 0; x < screen.width(); ++x) {
            // 续格不输出：全角字符的 UTF-8 本身已经"占两格"，
            // 再补一个空格会把"中文"拆成"中 文"——agent 读屏和断言匹配都会变难。
            // 代价是含全角字符的行按字节数不再等于列数（终端里显示仍是两倍宽）。
            if (screen.at(x, y).cols == 0) continue;
            const char32_t ch = screen.glyph_at(x, y);
            if (ch == 0) {
                out += ' ';  // 空白/控制字符导出为空格，列宽不变
                continue;
            }
            text::append_utf8(out, ch);  // 全角字符按 UTF-8 原样导出
        }
        out += '\n';
    }
    return out;
}

} // namespace phos::screen_text

#include "core/text.hpp"

namespace phos::text {

namespace {

/// East Asian Width = W/F 的区间（含端点）。只列实际会用到的块：
/// 汉字与扩展区、假名、谚文、CJK 标点与全角形式。
struct WideRange {
    char32_t lo, hi;
};
constexpr WideRange kWideRanges[] = {
    {0x1100, 0x115F},   // 谚文字母
    {0x2E80, 0x303E},   // CJK 部首、康熙部首、CJK 符号与标点
    {0x3041, 0x33FF},   // 平假名/片假名/注音/谚文兼容/CJK 兼容/方块元素与围字
    {0x3400, 0x4DBF},   // CJK 统一表意文字扩展 A
    {0x4E00, 0x9FFF},   // CJK 统一表意文字
    {0xA000, 0xA4CF},   // 彝文
    {0xA960, 0xA97F},   // 谚文字母扩展 A
    {0xAC00, 0xD7A3},   // 谚文音节
    {0xF900, 0xFAFF},   // CJK 兼容表意文字
    {0xFE10, 0xFE19},   // 竖排形式
    {0xFE30, 0xFE6F},   // CJK 兼容形式、小写变体
    {0xFF00, 0xFF60},   // 全角 ASCII 与半角片假名
    {0xFFE0, 0xFFE6},   // 全角符号（￥￡等）
    {0x20000, 0x3FFFD}, // CJK 扩展 B 及以后
};

/// 追加一个 UTF-8 码点（1~4 字节）
void append_encoded(std::string& out, char32_t ch) {
    if (ch < 0x80) {
        out += static_cast<char>(ch);
    } else if (ch < 0x800) {
        out += static_cast<char>(0xC0 | (ch >> 6));
        out += static_cast<char>(0x80 | (ch & 0x3F));
    } else if (ch < 0x10000) {
        out += static_cast<char>(0xE0 | (ch >> 12));
        out += static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (ch & 0x3F));
    } else {
        out += static_cast<char>(0xF0 | (ch >> 18));
        out += static_cast<char>(0x80 | ((ch >> 12) & 0x3F));
        out += static_cast<char>(0x80 | ((ch >> 6) & 0x3F));
        out += static_cast<char>(0x80 | (ch & 0x3F));
    }
}

} // namespace

int char_width(char32_t ch) {
    if (ch < 32 || ch == 0x7F) return 0;  // 控制字符不占格
    for (const WideRange& range : kWideRanges)
        if (ch >= range.lo && ch <= range.hi) return 2;
    return 1;
}

std::vector<char32_t> decode(std::string_view text) {
    std::vector<char32_t> out;
    out.reserve(text.size());

    size_t i = 0;
    while (i < text.size()) {
        const unsigned char lead = static_cast<unsigned char>(text[i]);
        int length = 0;
        char32_t cp = 0;

        if (lead < 0x80) {
            length = 1;
            cp = lead;
        } else if ((lead & 0xE0) == 0xC0) {
            length = 2;
            cp = lead & 0x1F;
        } else if ((lead & 0xF0) == 0xE0) {
            length = 3;
            cp = lead & 0x0F;
        } else if ((lead & 0xF8) == 0xF0) {
            length = 4;
            cp = lead & 0x07;
        } else {
            out.push_back(U'?');  // 非法首字节：占一个位置，绝不吞掉后续内容
            ++i;
            continue;
        }

        if (i + static_cast<size_t>(length) > text.size()) {
            out.push_back(U'?');  // 被截断的多字节序列
            break;
        }
        bool valid = true;
        for (int k = 1; k < length; ++k) {
            const unsigned char cont = static_cast<unsigned char>(text[i + static_cast<size_t>(k)]);
            if ((cont & 0xC0) != 0x80) {
                valid = false;
                break;
            }
            cp = (cp << 6) | (cont & 0x3F);
        }
        if (!valid) {
            out.push_back(U'?');
            ++i;
            continue;
        }

        out.push_back(cp);
        i += static_cast<size_t>(length);
    }
    return out;
}

int display_width(std::string_view text) {
    int width = 0;
    for (char32_t ch : decode(text)) width += char_width(ch);
    return width;
}

void append_utf8(std::string& out, char32_t ch) { append_encoded(out, ch); }

std::string truncate(std::string_view text, int max_cols) {
    std::string out;
    int used = 0;
    for (char32_t ch : decode(text)) {
        const int w = char_width(ch);
        if (w == 0) continue;
        if (used + w > max_cols) break;  // 宽字符放不下就整体舍弃，不切半格
        append_encoded(out, ch);
        used += w;
    }
    return out;
}

std::vector<std::string> wrap(std::string_view in, size_t width, size_t max_lines) {
    std::vector<std::string> lines;
    if (width == 0 || max_lines == 0) return lines;

    const std::vector<char32_t> codepoints = decode(in);
    size_t index = 0;
    while (index < codepoints.size() && lines.size() < max_lines) {
        std::string line;
        int used = 0;
        while (index < codepoints.size()) {
            const char32_t ch = codepoints[index];
            const int w = char_width(ch);
            if (w == 0) {
                ++index;
                continue;
            }
            if (used + w > static_cast<int>(width)) break;
            append_encoded(line, ch);
            used += w;
            ++index;
        }

        const bool truncated = lines.size() + 1 == max_lines && index < codepoints.size();
        if (truncated) {
            // 末行且还有剩余：退到能放下 "..." 的位置，再补省略标记
            const int keep = static_cast<int>(width) - 3;
            line = truncate(line, keep < 0 ? 0 : keep);
            line += "...";
        }
        lines.push_back(std::move(line));
    }
    return lines;
}

std::string pad_right(std::string_view in, size_t width) {
    std::string out = truncate(in, static_cast<int>(width));
    int used = display_width(out);
    while (used < static_cast<int>(width)) {
        out += ' ';
        ++used;
    }
    return out;
}

int centered_x(std::string_view in, int base, int span) {
    int x = base + (span - display_width(in)) / 2;
    return x < base ? base : x;
}

} // namespace phos::text

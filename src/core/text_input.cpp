#include "core/text_input.hpp"

#include "core/text.hpp"

namespace phos::text {

TextInput::TextInput(Filter accept, size_t max_chars)
    : accept_(std::move(accept)), max_chars_(max_chars) {}

void TextInput::apply(std::string_view typed) {
    for (const char32_t ch : decode(typed)) {
        if (ch == static_cast<char32_t>(kBackspace)) {
            if (!value_.empty()) {
                pop_back_utf8(value_);
                --count_;
            }
            continue;
        }
        if (char_width(ch) == 0) continue;  // 控制字符不占格，也不该进缓冲
        if (accept_ && !accept_(ch)) continue;
        if (max_chars_ > 0 && count_ >= max_chars_) continue;
        append_utf8(value_, ch);
        ++count_;
    }
}

} // namespace phos::text

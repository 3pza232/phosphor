#include "core/input.hpp"

#include <algorithm>
#include <cctype>

namespace phos {

namespace {

/// 少数几个"显示名和键名不一样"的键：其余按大写显示
constexpr std::pair<const char*, const char*> kDisplayAliases[] = {
    {"start", "ENTER"}, {"select", "SHIFT"}, {"space", "SPACE"},
    {"comma", ","},     {"period", "."},     {"slash", "/"},
    {"semicolon", ";"}, {"apostrophe", "'"}, {"minus", "-"},
    {"equal", "="},     {"lbrace", "["},     {"rbrace", "]"},
    {"backslash", "\\"}, {"tab", "TAB"},
};

} // namespace

std::string key_display_name(std::string_view name) {
    for (const auto& [key, shown] : kDisplayAliases)
        if (name == key) return shown;
    std::string out;
    if (name.size() == 1) {
        // 字母按大写显示（"a" → "A"），数字与符号原样
        out.push_back(static_cast<char>(std::toupper(static_cast<unsigned char>(name[0]))));
        return out;
    }
    bool first = true;
    for (char c : name) {  // 其余整体大写："f1" → "F1"、"left" → "LEFT"
        const bool lowered = !first && std::isdigit(static_cast<unsigned char>(out.back()));
        out.push_back(static_cast<char>(
            lowered ? c : std::toupper(static_cast<unsigned char>(c))));
        first = false;
    }
    return out;
}

std::optional<InputAction> input_action_from(std::string_view name, bool down) {
    const std::string text(name);
    if (is_host_key(text)) return InputAction{{}, down, text};
    if (text.empty()) return std::nullopt;
    // 任何非空名字都是合法虚拟键：主机不做白名单，卡带想用哪个键就是哪个键
    return InputAction{text, down, {}};
}

int Input::find(std::string_view name) const {
    for (size_t i = 0; i < names_.size(); ++i)
        if (names_[i] == name) return static_cast<int>(i);
    return -1;
}

int Input::slot(std::string_view name) {
    const int found = find(name);
    if (found >= 0) return found;
    names_.emplace_back(name);
    cur_.push_back(false);
    prev_.push_back(false);
    down_at_.push_back(-1.0f);
    return static_cast<int>(names_.size() - 1);
}

void Input::set_key(std::string_view name, bool down) {
    if (name.empty()) return;
    const size_t index = static_cast<size_t>(slot(name));
    cur_[index] = down;
    down_at_[index] = down ? clock_ : -1.0f;
}

float Input::duration(std::string_view name) const {
    const int index = find(name);
    if (index < 0 || down_at_[static_cast<size_t>(index)] < 0.0f) return 0.0f;
    return clock_ - down_at_[static_cast<size_t>(index)];
}

void Input::push_text(std::string text) {
    text_ += std::move(text);
}

std::string Input::any_pressed() const {
    for (size_t i = 0; i < names_.size(); ++i)
        if (cur_[i] && !prev_[i]) return names_[i];
    return {};
}

void Input::release_all() {
    std::fill(cur_.begin(), cur_.end(), false);
    std::fill(down_at_.begin(), down_at_.end(), -1.0f);
}

} // namespace phos

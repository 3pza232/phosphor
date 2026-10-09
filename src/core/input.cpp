#include "core/input.hpp"

namespace phos {

std::optional<Key> key_from_name(const std::string& name) {
    for (const auto& [key, key_name] : kAllKeys)
        if (name == key_name) return key;
    return std::nullopt;
}

std::string key_primary_name(Key key) {
    switch (key) {
        case Key::left: return "LEFT";
        case Key::right: return "RIGHT";
        case Key::up: return "UP";
        case Key::down: return "DOWN";
        case Key::a: return "A";
        case Key::b: return "B";
        case Key::x: return "X";
        case Key::y: return "Y";
        case Key::start: return "ENTER";
        case Key::select: return "SHIFT";
        case Key::count: break;
    }
    return "?";
}

std::optional<InputAction> input_action_from(std::string_view name, bool down) {
    const std::string text(name);
    if (is_host_key(text)) return InputAction{std::nullopt, down, text};
    if (const auto key = key_from_name(text)) return InputAction{*key, down, {}};
    return std::nullopt;
}

void Input::set_key(Key key, bool down) {
    cur_[index(key)] = down;
}

void Input::push_text(std::string text) {
    text_ += std::move(text);
}

void Input::release_all() {
    cur_.fill(false);
}

} // namespace phos

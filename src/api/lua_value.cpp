#include "api/lua_value.hpp"

#include "core/text.hpp"

#include <sol/sol.hpp>

namespace phos::api {

Color read_color(const sol::object& object, Color fallback) {
    if (!object.is<sol::table>()) return fallback;
    const sol::table table = object.as<sol::table>();
    auto channel = [&table](int index, uint8_t fallback_channel) {
        const sol::object value = table[index];
        if (!value.is<double>() && !value.is<int>()) return fallback_channel;
        const int number = value.as<int>();
        const int clamped = number < 0 ? 0 : (number > 255 ? 255 : number);
        return static_cast<uint8_t>(clamped);
    };
    return Color{channel(1, fallback.r), channel(2, fallback.g), channel(3, fallback.b)};
}

char32_t read_char(const sol::object& object, char32_t fallback) {
    if (object.is<std::string>()) {
        // 按码点取第一个：中文等多字节字符不会被截成半个序列
        for (char32_t codepoint : text::decode(object.as<std::string>())) return codepoint;
        return fallback;
    }
    if (object.is<double>() || object.is<int>()) {
        const int number = object.as<int>();
        return number > 0 ? static_cast<char32_t>(number) : fallback;
    }
    return fallback;
}

} // namespace phos::api

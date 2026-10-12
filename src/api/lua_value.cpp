#include "api/lua_value.hpp"

#include "api/host_api.hpp"
#include "core/text.hpp"

#include <sol/sol.hpp>

namespace phos::api {

Color read_color(const sol::object& object, Color fallback) {
    if (object.is<Color>()) return object.as<Color>();
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

std::vector<std::string> read_rows(const sol::object& object) {
    std::vector<std::string> rows;
    if (!object.is<sol::table>()) return rows;
    const sol::table table = object.as<sol::table>();
    rows.reserve(table.size());
    for (size_t i = 1; i <= table.size(); ++i) {
        const sol::object row = table[i];
        if (row.is<std::string>()) rows.push_back(row.as<std::string>());
    }
    return rows;
}

std::map<char, Color> read_char_color_map(const sol::object& object) {
    std::map<char, Color> colors;
    if (!object.is<sol::table>()) return colors;
    const sol::table table = object.as<sol::table>();
    for (auto& entry : table) {
        if (!entry.first.is<std::string>()) continue;
        const std::string key = entry.first.as<std::string>();
        if (key.empty()) continue;
        if (!entry.second.is<Color>() && !entry.second.is<sol::table>()) continue;
        colors[key[0]] = read_color(entry.second, Color::white);
    }
    return colors;
}

Color read_background(const sol::object& object) {
    if (object.is<Color>() || object.is<sol::table>()) return read_color(object, Color::black);
    return kKeepBg;  // 未给：保留该格原有背景（透明底哨兵只此一份，见 color.hpp）
}

Color slot_color(const HostContext& host, PaletteSlot slot, Color fallback) {
    return host.palette ? host.palette->slots[static_cast<size_t>(slot)] : fallback;
}

Color default_fg(const HostContext& host) { return slot_color(host, PaletteSlot::white, Color::white); }

Color default_bg(const HostContext& host) { return slot_color(host, PaletteSlot::black, Color::black); }

} // namespace phos::api

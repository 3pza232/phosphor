#include "api/lua_value.hpp"

#include "api/host_api.hpp"
#include "core/screen.hpp"
#include "core/text.hpp"

#include <cmath>
#include <sol/sol.hpp>

namespace phos::api {

std::uint8_t read_scale(const sol::optional<int>& scale) {
    const int s = scale.value_or(1);
    if (s < 2) return 1;
    return static_cast<std::uint8_t>(s > Screen::kMaxCellScale ? Screen::kMaxCellScale : s);
}

int read_channel(const sol::object& object, int fallback) {
    if (!object.is<double>() && !object.is<int>()) return fallback;
    const double value = object.as<double>();
    if (!std::isfinite(value)) return fallback;  // NaN / ±inf：当没给
    const int rounded = static_cast<int>(value < 0 ? value - 0.5 : value + 0.5);
    return rounded < 0 ? 0 : (rounded > 255 ? 255 : rounded);
}

double read_number(const sol::table& table, const char* key, double fallback) {
    const sol::object value = table[key];
    if (!value.is<double>() && !value.is<int>()) return fallback;
    const double number = value.as<double>();
    return std::isfinite(number) ? number : fallback;  // NaN / ±inf：当没给
}

Color read_color(const sol::object& object, Color fallback) {
    if (object.is<Color>()) return object.as<Color>();
    if (!object.is<sol::table>()) return fallback;
    const sol::table table = object.as<sol::table>();
    return Color{static_cast<uint8_t>(read_channel(table[1], fallback.r)),
                 static_cast<uint8_t>(read_channel(table[2], fallback.g)),
                 static_cast<uint8_t>(read_channel(table[3], fallback.b))};
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

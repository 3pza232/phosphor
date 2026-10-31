#include "api/ui_options.hpp"

#include "api/host_api.hpp"
#include "api/lua_value.hpp"
#include "core/palette.hpp"

#include <algorithm>
#include <cmath>

namespace phos::api {

char32_t parse_ch(const sol::object& object, char32_t fallback) {
    return read_char(object, fallback);
}

Color parse_color(const sol::object& object, Color fallback, const Palette* palette) {
    if (palette != nullptr && object.is<std::string>()) {
        const std::string name = object.as<std::string>();
        for (size_t i = 0; i < kPaletteSlots; ++i)
            if (name == kPaletteSlotNames[i]) return palette->slots[i];
        return fallback;
    }
    return read_color(object, fallback);
}

Color parse_fg(const sol::object& object, Color fallback) {
    return parse_color(object, fallback);
}

Color parse_bg(const sol::object& object, Color fallback, bool keep_when_omitted) {
    // 透明底路径直接复用既有语义（坏表通道按 Color::black 补、其余 → kKeepBg），
    // 保证与改造前的 read_background 逐通道一致；keep=false 才用调用方的 fallback。
    if (keep_when_omitted) return read_background(object);
    return read_color(object, fallback);
}

InlinePaint parse_inline(const sol::object& ch, const sol::object& fg, const sol::object& bg,
                         char32_t fallback_ch, const HostContext& host) {
    InlinePaint out;
    out.ch = parse_ch(ch, fallback_ch);
    out.fg = parse_fg(fg, default_fg(host));
    out.bg = parse_bg(bg, default_bg(host), true);
    return out;
}

int parse_step(const sol::optional<int>& step) {
    const int value = step.value_or(1);
    return value < 1 ? 1 : value;
}

float parse_brightness(const sol::optional<float>& brightness) {
    float value = brightness.value_or(1.0f);
    if (!std::isfinite(value)) value = 1.0f;
    return std::clamp(value, 0.0f, 1.0f);
}

} // namespace phos::api

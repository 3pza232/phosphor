#include "shell/settings_view.hpp"

#include "core/crt.hpp"
#include "core/text.hpp"
#include "shell/messages.hpp"

#include <array>

namespace phos {

namespace {

/// 界面行：分区标题（不可选）或设置项
struct Row {
    bool header;
    Msg label;  // header 的文案标识；设置项的左标签由 row_text() 给出
    SettingId id;
};

// 顺序 = 界面顺序；按"机身显示 → 声音 → 系统"分组
constexpr Row kRows[] = {
    {true,  Msg::section_machine, SettingId::count},
    {false, Msg::count,           SettingId::theme},
    {false, Msg::count,           SettingId::font},
    {false, Msg::count,           SettingId::scanlines},
    {false, Msg::count,           SettingId::fps},
    {true,  Msg::section_audio,   SettingId::count},
    {false, Msg::count,           SettingId::sound_pack},
    {false, Msg::count,           SettingId::music_volume},
    {false, Msg::count,           SettingId::sfx_volume},
    {true,  Msg::section_system,  SettingId::count},
    {false, Msg::count,           SettingId::boot},
    {false, Msg::count,           SettingId::shelf_view},
    {false, Msg::count,           SettingId::language},
    {false, Msg::count,           SettingId::back},
};
constexpr int kRowCount = static_cast<int>(sizeof(kRows) / sizeof(kRows[0]));

std::string pick(const std::vector<std::string>& names, int index, const char* fallback) {
    if (names.empty() || index < 0 || index >= static_cast<int>(names.size()))
        return fallback;
    return names[static_cast<size_t>(index)];
}

/// 档位显示名（取自文案表：加语言只需加一列，这里不必再分支）。
/// 机器可读的档位名仍由 `crt_level_name()` 提供
/// （`state.query` 给 agent 用，保持 ASCII，与遥测行同一套政策）
const char* crt_level_label(Lang lang, int level) {
    switch (level) {
        case 1: return tr(lang, Msg::value_crt_low);
        case 2: return tr(lang, Msg::value_crt_mid);
        case 3: return tr(lang, Msg::value_crt_high);
        default: return tr(lang, Msg::value_crt_off);
    }
}

/// 标签补齐到固定列宽：直接复用文本层的 pad_right（按显示宽度补，中文一列算 2 格）
std::string label(Lang lang, Msg id, int cols = 16) {
    return text::pad_right(tr(lang, id), static_cast<size_t>(cols));
}

/// 选项文案（标签 + 当前值）
std::string row_text(SettingId id, const SettingsContext& ctx) {
    const Lang lang = ctx.lang;
    switch (id) {
        case SettingId::theme:
            return label(lang, Msg::row_theme) + "< " +
                   pick(ctx.skins, ctx.skin_index, tr(lang, Msg::value_default)) + " >";
        case SettingId::font:
            return label(lang, Msg::row_font) + "< " +
                   pick(ctx.fonts, ctx.font_index, tr(lang, Msg::value_default)) + " >";
        case SettingId::scanlines:
            return label(lang, Msg::row_scanlines) + "[ " +
                   crt_level_label(lang, ctx.crt_level) + " ]";
        case SettingId::fps: {
            // 读数里带上它相对实机的倍数：这台机器的逻辑是 60Hz 定步长，刷新率只改
            // 画面顺不顺、不改游戏速度——一眼能看出这件事，比对着文档猜强
            const int fps = ctx.fps > 0 ? ctx.fps : kDefaultFps;
            std::string speed;
            if (fps != kLogicFps) {
                const bool slower = fps < kLogicFps;
                speed = std::string(slower ? "  (1/" : "  (") +
                        std::to_string(slower ? kLogicFps / fps : fps / kLogicFps) + "x)";
            }
            return label(lang, Msg::row_fps) + "< " + std::to_string(fps) + speed + " >";
        }
        case SettingId::sound_pack:
            return label(lang, Msg::row_sound) + "< " +
                   pick(ctx.sounds, ctx.sound_index, tr(lang, Msg::value_silent)) + " >";
        case SettingId::music_volume:
            return label(lang, Msg::row_music) + "[ " + std::to_string(ctx.music_volume) + "% ]";
        case SettingId::sfx_volume:
            return label(lang, Msg::row_sfx) + "[ " + std::to_string(ctx.sfx_volume) + "% ]";
        case SettingId::boot:
            return label(lang, Msg::row_boot) + "< " +
                   pick(ctx.boots, ctx.boot_index, tr(lang, Msg::value_builtin)) + " >";
        case SettingId::shelf_view:
            return label(lang, Msg::row_shelf_view) + "< " +
                   tr(lang, ctx.window_style ? Msg::value_window : Msg::value_list) + " >";
        case SettingId::language:
            return label(lang, Msg::row_language) + "< " +
                   tr(lang, ctx.lang_index == 0 ? Msg::language_zh : Msg::language_en) + " >";
        case SettingId::back:
            return tr(lang, Msg::row_back);
        default:
            return {};
    }
}

} // namespace

void draw_settings(Screen& screen, const ui::Rect& content, const SettingsContext& ctx,
                   const ui::Style& style, int cursor) {
    int item_index = 0;
    int y = content.y + 4;

    for (int i = 0; i < kRowCount; ++i, ++y) {
        const Row& row = kRows[i];
        if (row.header) {
            if (i != 0) ++y;  // 分区之间留一行空白
            ui::print(screen, content.x + 4, y, tr(ctx.lang, row.label), style.dim, style.bg);
            continue;
        }

        const bool selected = item_index == cursor;
        screen.put(content.x + 6, y, selected ? U'>' : U' ', style.accent, style.bg);
        ui::print(screen, content.x + 8, y, row_text(row.id, ctx),
                  selected ? style.accent : style.fg, style.bg);
        ++item_index;
    }
}

} // namespace phos

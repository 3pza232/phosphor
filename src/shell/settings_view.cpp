#include "shell/settings_view.hpp"

#include "core/crt.hpp"
#include "core/text.hpp"
#include "ui/frame.hpp"

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
    {false, Msg::count,           SettingId::font_size},
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

std::string pick(const std::vector<std::string>& names, int index, const char* fallback) {
    if (names.empty() || index < 0 || index >= static_cast<int>(names.size()))
        return fallback;
    return names[static_cast<size_t>(index)];
}

/// 档位显示名（取自文案表：加语言只需加一列，这里不必再分支）。
/// 机器可读的档位名仍由 `crt_level_name()` 提供（agent 用，保持 ASCII）
const char* crt_level_label(Lang lang, int level) {
    switch (level) {
        case 1: return tr(lang, Msg::value_crt_low);
        case 2: return tr(lang, Msg::value_crt_mid);
        case 3: return tr(lang, Msg::value_crt_high);
        default: return tr(lang, Msg::value_crt_off);
    }
}

/// 标签补齐到固定列宽：复用文本层的 pad_right（按显示宽度补，中文一列算 2 格）
std::string label(Lang lang, Msg id, int cols = 16) {
    return text::pad_right(tr(lang, id), static_cast<size_t>(cols));
}

/// 选项文案（标签 + 当前值）。这是**数据格式化**，不是排版：排版由组件负责。
std::string row_text(SettingId id, const SettingsContext& ctx) {
    const Lang lang = ctx.lang;
    switch (id) {
        case SettingId::theme:
            return label(lang, Msg::row_theme) + "< " +
                   pick(ctx.skins, ctx.skin_index, tr(lang, Msg::value_default)) + " >";
        case SettingId::font:
            return label(lang, Msg::row_font) + "< " +
                   pick(ctx.fonts, ctx.font_index, tr(lang, Msg::value_default)) + " >";
        case SettingId::font_size:
            return label(lang, Msg::row_font_size) + "< " + std::to_string(ctx.font_px) + " >";
        case SettingId::scanlines:
            return label(lang, Msg::row_scanlines) + "[ " +
                   crt_level_label(lang, ctx.crt_level) + " ]";
        case SettingId::fps: {
            // 读数里带上它相对实机的倍数：这台机器的逻辑是 60Hz 定步长，刷新率只改
            // 画面顺不顺、不改游戏速度
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
        case SettingId::shelf_view: {
            std::string name;
            if (ctx.shelf_index == 0)
                name = tr(lang, Msg::value_list);
            else if (ctx.shelf_index >= 2 &&
                     ctx.shelf_index - 2 < static_cast<int>(ctx.shelves.size()))
                name = ctx.shelves[static_cast<size_t>(ctx.shelf_index - 2)];
            else
                name = tr(lang, Msg::value_window);
            return label(lang, Msg::row_shelf_view) + "< " + name + " >";
        }
        case SettingId::language: {
            // 语言行显示的是"当前语言"，不是"下一步会切到什么"
            const bool english = ctx.lang == Lang::en;
            return label(lang, Msg::row_language) + "< " +
                   tr(lang, english ? Msg::language_en : Msg::language_zh) + " >";
        }
        case SettingId::back:
            return tr(lang, Msg::row_back);
        default:
            return {};
    }
}

} // namespace

const char* setting_key(SettingId id) {
    switch (id) {
        case SettingId::theme: return "theme";
        case SettingId::font: return "font";
        case SettingId::font_size: return "font_size";
        case SettingId::scanlines: return "scanlines";
        case SettingId::fps: return "fps";
        case SettingId::sound_pack: return "sound";
        case SettingId::music_volume: return "music_volume";
        case SettingId::sfx_volume: return "sfx_volume";
        case SettingId::boot: return "boot";
        case SettingId::shelf_view: return "shelf_view";
        case SettingId::language: return "language";
        case SettingId::back: return "back";
        default: return "";
    }
}

SettingId setting_from_key(std::string_view key) {
    static constexpr SettingId kAll[] = {
        SettingId::theme,      SettingId::font,     SettingId::font_size,
        SettingId::scanlines,  SettingId::fps,      SettingId::sound_pack,
        SettingId::music_volume, SettingId::sfx_volume, SettingId::boot,
        SettingId::shelf_view, SettingId::language, SettingId::back,
    };
    for (SettingId id : kAll)
        if (key == setting_key(id)) return id;
    return SettingId::count;
}

int setting_item_index(SettingId id) {
    int index = 0;
    for (const Row& row : kRows) {
        if (row.header) continue;
        if (row.id == id) return index;
        ++index;
    }
    return -1;
}

void build_settings(ui::Node& root, const SettingsContext& ctx, const ui::Rect& area) {
    int section = 0;
    bool first = true;
    int gap = 0;
    for (const Row& row : kRows) {
        if (row.header) {
            if (!first) {
                ui::Node& blank = root.add_spacer("settings/gap_" + std::to_string(gap++));
                blank.props.height = 1;
            }
            ui::Node& title = root.add_text("settings/section_" + std::to_string(section++),
                                            tr(ctx.lang, row.label));
            title.props.dim = true;
            first = false;
            continue;
        }
        const std::string id = std::string("settings/") + setting_key(row.id);
        if (row.id == SettingId::back) {
            ui::Node& back = root.add(ui::Kind::button, id);
            back.props.text = row_text(row.id, ctx);
            back.props.indent = 2;
            back.props.text_gap = 2;
        } else {
            ui::Node& option = root.add(ui::Kind::option, id);
            option.props.text = row_text(row.id, ctx);
            option.props.indent = 2;
            option.props.text_gap = 2;
        }
        first = false;
    }

    // 字形预览：固定在区域底部的六行盒子（与旧版 layout 完全一致的位置）
    ui::Node& preview = root.add(ui::Kind::box, "settings/preview");
    preview.props.absolute = true;
    preview.props.x = 2;
    preview.props.y = std::max(0, area.h - 10);
    preview.props.width = std::max(2, area.w - 4);
    preview.props.height = 6;
    preview.props.border = ui::Border::single;
    preview.props.padding = ui::Insets{1, 0, 1, 0};
    preview.props.gap = 0;
    preview.props.title = tr(ctx.lang, Msg::font_preview);

    auto& sample = preview.add_text("settings/preview/ascii",
                                    "ABCDEFG abcdefg 0123456789  !?@#&%");
    sample.props.overflow = ui::Overflow::clip;
    auto& blank = preview.add_spacer("settings/preview/gap");
    blank.props.height = 1;
    preview.add_text("settings/preview/cjk", tr(ctx.lang, Msg::font_preview_cjk));
}

} // namespace phos
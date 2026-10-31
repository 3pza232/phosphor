#include "shell/settings_view.hpp"

#include "core/crt.hpp"
#include "core/text.hpp"
#include "core/version.hpp"
#include "ui/frame.hpp"

#include <algorithm>
#include <array>
#include <utility>

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

/// 设置项的本地化标签（搜索用：中英文名都参与匹配，与当前界面语言无关）
Msg row_label_msg(SettingId id) {
    switch (id) {
        case SettingId::theme: return Msg::row_theme;
        case SettingId::font: return Msg::row_font;
        case SettingId::font_size: return Msg::row_font_size;
        case SettingId::scanlines: return Msg::row_scanlines;
        case SettingId::fps: return Msg::row_fps;
        case SettingId::sound_pack: return Msg::row_sound;
        case SettingId::music_volume: return Msg::row_music;
        case SettingId::sfx_volume: return Msg::row_sfx;
        case SettingId::boot: return Msg::row_boot;
        case SettingId::shelf_view: return Msg::row_shelf_view;
        case SettingId::language: return Msg::row_language;
        case SettingId::back: return Msg::row_back;
        default: return Msg::count;
    }
}

std::string lower_ascii(std::string value) {
    for (char& c : value)
        if (c >= 'A' && c <= 'Z') c = static_cast<char>(c - 'A' + 'a');
    return value;
}

/// 每项的搜索文本：中英文标签 + 稳定 key + 常用同义词（英文/拼音无关，只补关键词）
std::string row_search_text(SettingId id) {
    std::string out = tr(Lang::zh, row_label_msg(id));
    out += ' ';
    out += tr(Lang::en, row_label_msg(id));
    out += ' ';
    out += setting_key(id);
    out += ' ';
    switch (id) {
        case SettingId::theme: out += "skin 主题 皮肤"; break;
        case SettingId::font: out += "typeface 字体"; break;
        case SettingId::font_size: out += "size 字号 大小"; break;
        case SettingId::scanlines: out += "crt scanline 扫描线"; break;
        case SettingId::fps: out += "framerate refresh 帧率 刷新率"; break;
        case SettingId::sound_pack: out += "audio sound 音效包"; break;
        case SettingId::music_volume: out += "music volume 音乐 音量"; break;
        case SettingId::sfx_volume: out += "sfx sound volume 音效 音量"; break;
        case SettingId::boot: out += "animation 启动动画"; break;
        case SettingId::shelf_view: out += "shelf layout list window 卡带架 样式"; break;
        case SettingId::language: out += "lang 语言 中文 english"; break;
        case SettingId::back: out += "return 返回 退出"; break;
        default: break;
    }
    return lower_ascii(out);
}

/// 把查询按空白切成 token；空查询 = 匹配全部
std::vector<std::string> search_tokens(std::string_view query) {
    std::vector<std::string> tokens;
    std::string current;
    for (char c : query) {
        if (c == ' ' || c == '\t' || c == '\n') {
            if (!current.empty()) tokens.push_back(lower_ascii(std::move(current)));
            current.clear();
        } else {
            current += c;
        }
    }
    if (!current.empty()) tokens.push_back(lower_ascii(std::move(current)));
    return tokens;
}

void add_setting_item(ui::Node& root, SettingId id, const SettingsContext& ctx) {
    const std::string row_id = std::string("settings/") + setting_key(id);
    if (id == SettingId::back) {
        ui::Node& back = root.add(ui::Kind::button, row_id);
        back.props.text = row_text(id, ctx);
        back.props.indent = 2;
        back.props.text_gap = 2;
    } else {
        ui::Node& option = root.add(ui::Kind::option, row_id);
        option.props.text = row_text(id, ctx);
        option.props.indent = 2;
        option.props.text_gap = 2;
    }
}

void add_preview(ui::Node& root, const SettingsContext& ctx, const ui::Rect& area) {
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

std::string glyph_utf8(char32_t cp) {
    std::string out;
    text::append_utf8(out, cp);
    return out;
}

/// 主题样张：12 个主题色角色 + 字形 + 标题/正文/次要文字 + 选中行/bar。
/// 全部走声明式组件与 theme token，不写绝对坐标；紧凑排成 5 行内容（边框另 2 行）。
void add_theme_sample(ui::Node& root, const SettingsContext& ctx) {
    const ui::Theme& theme = ctx.theme;
    const bool en = ctx.lang == Lang::en;

    ui::Node& sample = root.add_box("settings/theme/sample", en ? "THEME SAMPLE" : "主题样张");
    sample.props.border = ui::Border::single;
    sample.props.opaque = true;
    sample.props.has_bg = true;
    sample.props.bg = theme.surface;
    sample.props.has_fg = true;
    sample.props.fg = theme.text;
    // 样张是紧凑预览：仍用主题 metrics，但把内缩/间距夹到小值，
    // 免得上限 16 的皮肤度量把 12 格色板/字形行挤出设置区
    const int pad_x = std::min(std::max(0, theme.metrics.pad_x), 2);
    sample.props.padding = ui::Insets{pad_x, 0, pad_x, 0};
    sample.props.gap = 0;  // 紧凑：设置屏还要容纳 12 行设置与底部字体预览

    // 12 个可直接从 Theme 读到的颜色角色（disabled 属于文字态，不占色板格）
    const std::array<Color, 12> palette{{
        theme.bg,          theme.surface,      theme.surface_alt, theme.text,
        theme.text_dim,    theme.accent,       theme.border,      theme.border_focus,
        theme.selection_bg, theme.selection_fg, theme.warning,     theme.danger,
    }};
    const int swatch_gap = std::min(std::max(0, theme.metrics.gap), 1);
    for (int row = 0; row < 2; ++row) {
        ui::Node& swatches =
            sample.add_row("settings/theme/swatches_" + std::to_string(row));
        swatches.props.gap = swatch_gap;
        for (int col = 0; col < 6; ++col) {
            const int index = row * 6 + col;
            ui::Node& swatch =
                swatches.add_text("settings/theme/swatch_" + std::to_string(index), "  ");
            swatch.props.has_bg = true;
            swatch.props.bg = palette[static_cast<size_t>(index)];
            swatch.props.has_fg = true;
            swatch.props.fg = palette[static_cast<size_t>(index)];
        }
    }

    const char32_t tl = theme.glyphs.tl, h = theme.glyphs.h, tr = theme.glyphs.tr;
    const char32_t v = theme.glyphs.v, bl = theme.glyphs.bl, br = theme.glyphs.br;
    const std::string frame = glyph_utf8(tl) + glyph_utf8(h) + glyph_utf8(h) + glyph_utf8(tr) +
                              " " + glyph_utf8(v) + " " + glyph_utf8(bl) + glyph_utf8(h) +
                              glyph_utf8(h) + glyph_utf8(br);
    std::string glyph_line = (en ? "FRAME " : "边框 ") + frame;
    glyph_line += en ? "  CURSOR " : "  光标 ";
    glyph_line += glyph_utf8(theme.glyphs.cursor);
    glyph_line += en ? "  SCROLL " : "  滚动 ";
    glyph_line += glyph_utf8(theme.glyphs.scroll_thumb) + glyph_utf8(theme.glyphs.scroll_track);
    glyph_line += en ? "  TABLE " : "  表线 ";
    glyph_line += glyph_utf8(theme.glyphs.table_rule);
    sample.add_text("settings/theme/glyphs", glyph_line);

    ui::Node& styles = sample.add_row("settings/theme/styles");
    styles.props.gap = std::min(std::max(1, theme.metrics.gap), 2);
    styles.add_text("settings/theme/title", en ? "TITLE" : "标题").props.accent = true;
    styles.add_text("settings/theme/body", en ? "BODY" : "正文");
    styles.add_text("settings/theme/dim", en ? "DIM" : "次要").props.dim = true;

    ui::Node& state = sample.add_row("settings/theme/state");
    state.props.gap = std::min(std::max(1, theme.metrics.gap), 2);
    ui::Node& selected =
        state.add_text("settings/theme/selected", en ? "> SELECTED ITEM" : "> 选中项");
    selected.props.has_bg = true;
    selected.props.bg = theme.selection_bg;
    selected.props.has_fg = true;
    selected.props.fg = theme.selection_fg;
    state.add_text("settings/theme/bar_label", "BAR").props.dim = true;
    ui::Node& bar = state.add_bar("settings/theme/bar", 0.6f);
    bar.props.width = 10;
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

void settings_search_begin(SettingsSearch& search) {
    search.active = true;
    search.query.clear();
}

void settings_search_clear(SettingsSearch& search) {
    search.active = false;
    search.query.clear();
}

void settings_search_apply_text(SettingsSearch& search, std::string_view typed) {
    if (!search.active) return;
    std::vector<char32_t> codepoints;
    for (char32_t cp : text::decode(search.query)) codepoints.push_back(cp);
    for (char32_t cp : text::decode(typed)) {
        if (cp == U'\b') {
            if (!codepoints.empty()) codepoints.pop_back();  // 按码点退格，中文不会删半个
            continue;
        }
        if (cp < 32 || cp == 127) continue;
        if (codepoints.size() >= 64) continue;  // 查询串上限：防止坏输入无限长
        codepoints.push_back(cp);
    }
    search.query.clear();
    for (char32_t cp : codepoints) text::append_utf8(search.query, cp);
}

bool settings_search_matches(SettingId id, std::string_view query) {
    if (id == SettingId::count) return false;
    const std::vector<std::string> tokens = search_tokens(query);
    if (tokens.empty()) return true;
    const std::string haystack = row_search_text(id);
    for (const std::string& token : tokens)
        if (haystack.find(token) == std::string::npos) return false;
    return true;
}

std::vector<SettingId> settings_visible_items(const SettingsSearch& search) {
    std::vector<SettingId> items;
    const int count = static_cast<int>(SettingId::count);
    for (int i = 0; i < count; ++i) {
        const SettingId id = static_cast<SettingId>(i);
        if (!search.active || settings_search_matches(id, search.query)) items.push_back(id);
    }
    return items;
}

void build_settings(ui::Node& root, const SettingsContext& ctx, const ui::Rect& area,
                    const SettingsSearch* search) {
    if (search && search->active) {
        const std::vector<SettingId> items = settings_visible_items(*search);
        const bool english = ctx.lang == Lang::en;
        std::string prompt = english ? "SEARCH: " : "搜索: ";
        prompt += search->query;
        prompt += english ? "  (" : "  (";
        prompt += std::to_string(items.size());
        prompt += english ? " matches)" : " 项)";
        prompt += english ? "   / type   [Esc] close" : "   / 输入   [Esc] 退出";
        ui::Node& line = root.add_text("settings/search", prompt);
        line.props.dim = true;

        if (items.empty()) {
            ui::Node& empty =
                root.add_text("settings/search/empty", english ? "NO MATCHES" : "无匹配设置项");
            empty.props.dim = true;
        } else {
            for (SettingId id : items) add_setting_item(root, id, ctx);
        }
        add_preview(root, ctx, area);
        return;
    }

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
        add_setting_item(root, row.id, ctx);
        // 主题/皮肤行下方紧跟一张主题样张；只在完整树里出现（搜索态保持紧凑）
        if (row.id == SettingId::theme) add_theme_sample(root, ctx);
        first = false;
    }

    add_preview(root, ctx, area);
}

void build_about(ui::Node& root, Lang lang, const ui::Rect& area) {
    (void)area;  // 宽度由 Frame 的内容区决定；这里只声明流式内容
    const bool en = lang == Lang::en;
    root.props.padding = ui::Insets{4, 2, 4, 2};
    root.props.gap = 0;

    ui::Node& product = root.add_text("about/product", std::string(kProductName) + "  " + kVersion);
    product.props.accent = true;
    root.add_text("about/build",
                  std::string(en ? "Build: C++17  ·  logic 60 Hz  ·  phos_api "
                                 : "构建: C++17  ·  逻辑帧率 60 Hz  ·  phos_api ") +
                      std::to_string(kPhosApiVersion));
    ui::Node& tagline =
        root.add_text("about/tagline",
                      en ? "A virtual console for text, pixels and little machines."
                         : "一台给文本、像素与小机器人的虚拟游戏机。");
    tagline.props.dim = true;
    root.add_divider("about/rule0");

    root.add_text("about/ops/title", en ? "BASIC CONTROLS" : "基本操作").props.dim = true;
    auto op = [&root, en](const char* id, const char* key, const char* zh, const char* english) {
        std::string line = std::string("  ") + key;
        while (line.size() < 10) line += ' ';
        line += en ? english : zh;
        root.add_text(id, line);
    };
    op("about/ops/move", "ARROWS", "移动 / 选择", "move / select");
    op("about/ops/confirm", "ENTER", "确认 / 开始", "confirm / start");
    op("about/ops/cancel", "ESC", "返回 / 暂停", "back / pause");
    op("about/ops/settings", "F2", "设置", "settings");
    op("about/ops/search", "/", "设置内搜索", "search in settings");
    op("about/ops/about", "F1", "关于（本页）", "about (this page)");
    op("about/ops/console", "\x60", "调试台", "debug console");
    op("about/ops/f12", "F12", "截图（screenshots/）", "screenshot (screenshots/)");

    root.add_divider("about/rule1");
    root.add_text("about/content/title", en ? "CONTENT ROOT" : "内容根").props.dim = true;
    root.add_text("about/content/paths", "carts/  theme/  devkit/  mods/");
    ui::Node& content_body =
        root.add_text("about/content/body",
                      en ? "The folder containing phosphor.exe is the content root; "
                           "--root overrides it."
                         : "phosphor.exe 所在目录就是内容根；启动时可用 --root 指定别处。");
    content_body.props.overflow = ui::Overflow::wrap;
    content_body.props.lines = 2;

    root.add_text("about/credits/title", en ? "CREDITS" : "致谢").props.dim = true;
    ui::Node& credits = root.add_text(
        "about/credits/body",
        "PHOSPHOR contributors  ·  Lua 5.4  ·  GLFW  ·  miniz  ·  stb  ·  sol2");
    credits.props.dim = true;
    ui::Node& licenses = root.add_text(
        "about/licenses",
        en ? "Licenses: see extern/*/LICENSE (Lua, GLFW, miniz, stb, sol2)"
           : "许可：见 extern/ 各依赖目录的 LICENSE（Lua、GLFW、miniz、stb、sol2）");
    licenses.props.dim = true;
    ui::Node& hint = root.add_hint("about/hint");
    hint.props.items = {"ESC", en ? "back to settings" : "返回设置"};
}

} // namespace phos
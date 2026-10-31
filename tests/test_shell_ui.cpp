// 外壳界面（声明式迁移后）的纯逻辑测试：磁带码界面的元素树几何与页面语义。
// 与 test_ui.cpp 同一套路：Frame/Node 直接排布到网格，不依赖 GL/Lua。
//
// 只测"能写进单元测试的部分"：暂停菜单与 Mod 浮窗的构建函数是 Shell 的私有实现
// （依赖整机状态），它们由 tools/shell_golden.py 的逐字节基线覆盖。

#include "harness.hpp"

#include "core/input.hpp"
#include "core/version.hpp"
#include "shell/controls_view.hpp"
#include "shell/layout.hpp"
#include "shell/settings_view.hpp"
#include "shell/tape_view.hpp"
#include "ui/element.hpp"
#include "ui/layout.hpp"
#include "ui/theme.hpp"

#include <string>

using namespace phos;

namespace {

ui::Node* find_node(ui::Node& root, const std::string& id) {
    if (root.id == id) return &root;
    for (ui::Node& child : root.children)
        if (ui::Node* found = find_node(child, id)) return found;
    return nullptr;
}

/// 建树 → 排布，返回根（调用方按 id 找节点）。坐标系是整屏网格，与外壳里一致
ui::Node build_tape(tape::ScreenState& state, const ui::Rect& content, Lang lang,
                    const std::string& typed) {
    ui::Theme theme;
    ui::Node root = ui::make_root("shell.tape");
    state.build(root, content, lang, typed);
    ui::measure(root, content.w, theme);
    ui::arrange(root, content, theme);
    return root;
}

ui::Rect content_rect() { return ui::Rect{2, 3, 80, 45}; }

/// Controls 屏建树 → 排布（不跑输入；捕获逻辑直接调 ScreenState）
ui::Node build_controls(controls::ScreenState& state, const ui::Rect& content, Lang lang) {
    ui::Theme theme;
    ui::Node root = ui::make_root("shell.controls");
    state.build(root, content, lang);
    ui::measure(root, content.w, theme);
    ui::arrange(root, content, theme);
    return root;
}

void press(tape::ScreenState& state, const char* key, int times = 1) {
    Input input;
    for (int i = 0; i < times; ++i) {
        input.set_key(key, true);
        state.update(input);
        input.next_frame();
        input.set_key(key, false);
        input.next_frame();
    }
}

} // namespace

TEST(shell_tape_view_rows_match_shell_layout) {
    tape::ScreenState state;
    state.set_tape("SNAKE", "", true);  // 没有存档码：正文为空，但版面必须完整
    const ui::Rect content = content_rect();
    ui::Node root = build_tape(state, content, Lang::zh, "");

    const ui::Node* cart = find_node(root, "tape/cart");
    CHECK(cart != nullptr);
    CHECK_EQ(cart->rect.x, content.x + ShellLayout::kMarginX + 2);
    CHECK_EQ(cart->rect.y, content.y + ShellLayout::kContentTop);

    const ui::Node* label = find_node(root, "tape/label");
    CHECK(label != nullptr);
    CHECK_EQ(label->rect.y, cart->rect.y + 2);  // 卡带行与标签行之间空一行

    // 正文块的高度 = 状态行之上留一行后的剩余空间（出厂几何下 31 行）
    const ui::Node* body = find_node(root, "tape/code");
    CHECK(body != nullptr);
    CHECK_EQ(body->rect.x, cart->rect.x);
    CHECK_EQ(body->rect.w, content.w - 2 * (ShellLayout::kMarginX + 2));
    CHECK_EQ(body->rect.y, label->rect.y + 1);
    CHECK_EQ(body->rect.h, 31);

    // 状态行与页脚之间留一行，结果行再在其下（旧版面同格）
    const ui::Node* status = find_node(root, "tape/status");
    CHECK(status != nullptr);
    CHECK_EQ(status->rect.y, body->rect.y + body->rect.h + 1);
    // 状态行在结果行之上，结果行才是贴页脚的那一行（旧版面同格）
    CHECK_EQ(status->rect.y, content.bottom() - ShellLayout::kFooterGap - 3);
    CHECK(find_node(root, "tape/result") == nullptr);
}

TEST(shell_tape_view_edit_page_declares_hex_field) {
    tape::ScreenState state;
    state.set_tape("SNAKE", "A1B2", true);
    press(state, "right");  // 输入页
    CHECK(int(state.page_hint()) == int(Msg::tape_edit));

    const ui::Rect content = content_rect();
    ui::Node root = build_tape(state, content, Lang::zh, "a1");
    const ui::Node* field = find_node(root, tape::ScreenState::kFieldId);
    CHECK(field != nullptr);
    CHECK(int(field->kind) == int(ui::Kind::field));
    CHECK(int(field->props.filter) == int(ui::FieldFilter::hex));  // 只收 0-9 / A-F
    CHECK(field->props.max_chars > 0);                             // 上限沿用存档导出码的长度
    CHECK_EQ(field->rect.y, find_node(root, "tape/label")->rect.y + 1);

    // 输入页的状态行与查看页同行：切页时画面不跳
    const ui::Node* status = find_node(root, "tape/status");
    CHECK(status != nullptr);
    CHECK_EQ(status->rect.y, content.bottom() - ShellLayout::kFooterGap - 3);
    CHECK_EQ(status->props.text, std::string("已输入 2 位"));

    press(state, "left");  // 回查看页
    CHECK(int(state.page_hint()) == int(Msg::tape_view));
}

TEST(shell_tape_view_scroll_is_clamped_to_last_page) {
    tape::ScreenState state;
    // 40 个满宽折行：可滚 9 行，再往下按也停在最后
    state.set_tape("SNAKE", std::string(40 * 72, 'A'), true);
    press(state, "down", 40);

    const ui::Rect content = content_rect();
    ui::Node root = build_tape(state, content, Lang::zh, "");
    const ui::Node* status = find_node(root, "tape/status");
    CHECK(status != nullptr);
    CHECK_EQ(status->props.text, std::string("第 10 行起 / 共 40 行（↑ / ↓ 滚动）"));

    // 可见窗口从第 10 行开始：窗口内是 31 行满宽码，首字符正是被滚上去的那一段
    const ui::Node* body = find_node(root, "tape/code");
    CHECK(body != nullptr);
    CHECK_EQ(body->props.text.size(), size_t(31 * 72));

    press(state, "up", 40);  // 回到顶
    root = build_tape(state, content, Lang::zh, "");
    CHECK_EQ(find_node(root, "tape/status")->props.text,
             std::string("第 1 行起 / 共 40 行（↑ / ↓ 滚动）"));
}

TEST(shell_tape_view_without_save_only_explains_and_returns) {
    tape::ScreenState state;
    state.set_tape("SNAKE", "", false);
    CHECK(int(state.footer_hint()) == int(Msg::tape_back_hint));
    // 没有存档时左/右键也切不出输入页（敲进来无处可写）
    press(state, "right");
    CHECK(int(state.page_hint()) == int(Msg::tape_view));

    const ui::Rect content = content_rect();
    ui::Node root = build_tape(state, content, Lang::zh, "");
    const ui::Node* hint = find_node(root, "tape/hint");
    CHECK(hint != nullptr);
    CHECK_EQ(hint->rect.y, content.y + ShellLayout::kContentTop + 1);
    CHECK(find_node(root, "tape/cart") == nullptr);
}


TEST(shell_settings_search_filters_by_bilingual_names_and_keywords) {
    SettingsSearch search;
    settings_search_begin(search);
    CHECK(search.active);
    CHECK(search.query.empty());

    settings_search_apply_text(search, "font");
    auto items = settings_visible_items(search);
    auto has = [&](SettingId id) {
        for (SettingId item : items)
            if (item == id) return true;
        return false;
    };
    CHECK(has(SettingId::font));
    CHECK(has(SettingId::font_size));
    CHECK(!has(SettingId::theme));
    CHECK(settings_search_matches(SettingId::font, "font"));

    // 中文名也参与匹配（与当前界面语言无关），且空格分词是 AND
    settings_search_clear(search);
    settings_search_begin(search);
    settings_search_apply_text(search, "字体");
    items = settings_visible_items(search);
    CHECK(has(SettingId::font));

    settings_search_clear(search);
    settings_search_begin(search);
    settings_search_apply_text(search, "字号");
    items = settings_visible_items(search);
    CHECK(has(SettingId::font_size));

    settings_search_clear(search);
    settings_search_begin(search);
    settings_search_apply_text(search, "font size");
    items = settings_visible_items(search);
    CHECK_EQ(items.size(), size_t(1));
    CHECK_EQ(int(items[0]), int(SettingId::font_size));

    // 退格按码点删；清空后恢复全部设置项
    settings_search_apply_text(search, "\b");
    CHECK_EQ(search.query, std::string("font siz"));
    settings_search_apply_text(search, std::string(40, '\b'));
    CHECK(search.query.empty());
    CHECK_EQ(settings_visible_items(search).size(), size_t(settings_item_count()));

    // 无匹配：过滤结果为空
    settings_search_apply_text(search, "zzzz");
    CHECK(settings_visible_items(search).empty());
    settings_search_clear(search);
    CHECK(!search.active);
    CHECK_EQ(settings_visible_items(search).size(), size_t(settings_item_count()));
}

TEST(shell_settings_search_tree_matches_and_empty_state) {
    SettingsContext ctx;
    ctx.lang = Lang::zh;
    const ui::Rect area{7, 11, 72, 37};
    ui::Theme theme;

    SettingsSearch search;
    settings_search_begin(search);
    settings_search_apply_text(search, "音量");
    ui::Node root = ui::make_root("shell.settings");
    build_settings(root, ctx, area, &search);
    ui::measure(root, area.w, theme);
    ui::arrange(root, area, theme);

    const ui::Node* line = find_node(root, "settings/search");
    CHECK(line != nullptr);
    CHECK(line->props.text.find("搜索") != std::string::npos);
    CHECK(line->props.text.find("画质") == std::string::npos);
    CHECK(find_node(root, "settings/music_volume") != nullptr);
    CHECK(find_node(root, "settings/sfx_volume") != nullptr);
    CHECK(find_node(root, "settings/theme") == nullptr);  // 没命中的条目不出现在树里
    CHECK(find_node(root, "settings/section_0") == nullptr);  // 搜索态不画分区标题
    CHECK(find_node(root, "settings/preview") != nullptr);

    // 无匹配：多一行提示，预览框仍在
    settings_search_apply_text(search, "zzzz");
    ui::Node empty_root = ui::make_root("shell.settings");
    build_settings(empty_root, ctx, area, &search);
    CHECK(find_node(empty_root, "settings/search/empty") != nullptr);
    CHECK(find_node(empty_root, "settings/theme") == nullptr);
    CHECK(find_node(empty_root, "settings/preview") != nullptr);

    // 未激活/空指针：原完整树（分区标题 + 全部设置项）
    ui::Node full = ui::make_root("shell.settings");
    build_settings(full, ctx, area);
    CHECK(find_node(full, "settings/search") == nullptr);
    CHECK(find_node(full, "settings/section_0") != nullptr);
    CHECK(find_node(full, "settings/theme") != nullptr);
    CHECK(find_node(full, "settings/back") != nullptr);
}



TEST(shell_settings_theme_sample_uses_theme_tokens) {
    SettingsContext ctx;
    ctx.lang = Lang::zh;
    ctx.theme.bg = Color{11, 1, 1};
    ctx.theme.surface = Color{12, 2, 2};
    ctx.theme.surface_alt = Color{13, 3, 3};
    ctx.theme.text = Color{14, 4, 4};
    ctx.theme.text_dim = Color{15, 5, 5};
    ctx.theme.accent = Color{16, 6, 6};
    ctx.theme.border = Color{17, 7, 7};
    ctx.theme.border_focus = Color{18, 8, 8};
    ctx.theme.selection_bg = Color{19, 9, 9};
    ctx.theme.selection_fg = Color{20, 10, 10};
    ctx.theme.warning = Color{21, 11, 11};
    ctx.theme.danger = Color{22, 12, 12};
    ctx.theme.glyphs.h = U'=';
    ctx.theme.glyphs.tl = U'[';
    ctx.theme.glyphs.tr = U']';
    ctx.theme.glyphs.v = U'!';
    ctx.theme.glyphs.bl = U'{';
    ctx.theme.glyphs.br = U'}';
    ctx.theme.glyphs.cursor = U'\u2192';
    ctx.theme.glyphs.scroll_thumb = U'#';
    ctx.theme.glyphs.scroll_track = U'.';
    ctx.theme.glyphs.table_rule = U'\u2500';

    const ui::Rect area{7, 11, 72, 37};
    ui::Node root = ui::make_root("shell.settings");
    build_settings(root, ctx, area);
    ui::measure(root, area.w, ctx.theme);
    ui::arrange(root, area, ctx.theme);

    const ui::Node* sample = find_node(root, "settings/theme/sample");
    CHECK(sample != nullptr);
    CHECK_EQ(sample->props.title, std::string("主题样张"));
    CHECK_EQ(int(sample->props.border), int(ui::Border::single));
    CHECK(sample->props.opaque);
    CHECK(!sample->focusable);  // 样张非交互，不抢设置焦点

    const Color expected[12] = {
        ctx.theme.bg,          ctx.theme.surface,      ctx.theme.surface_alt,
        ctx.theme.text,        ctx.theme.text_dim,     ctx.theme.accent,
        ctx.theme.border,      ctx.theme.border_focus, ctx.theme.selection_bg,
        ctx.theme.selection_fg, ctx.theme.warning,      ctx.theme.danger,
    };
    for (int i = 0; i < 12; ++i) {
        const ui::Node* swatch =
            find_node(root, "settings/theme/swatch_" + std::to_string(i));
        CHECK(swatch != nullptr);
        CHECK(swatch->rect.w >= 2);  // 色块必须真有 2 列宽（空格文本不能被量成 0）
        CHECK(swatch->props.has_bg);
        CHECK_EQ(int(swatch->props.bg.r), int(expected[i].r));
        CHECK_EQ(int(swatch->props.bg.g), int(expected[i].g));
        CHECK_EQ(int(swatch->props.bg.b), int(expected[i].b));
    }

    const ui::Node* glyphs = find_node(root, "settings/theme/glyphs");
    CHECK(glyphs != nullptr);
    CHECK(glyphs->props.text.find("=") != std::string::npos);
    CHECK(glyphs->props.text.find("[") != std::string::npos);
    CHECK(glyphs->props.text.find("]") != std::string::npos);
    CHECK(glyphs->props.text.find("!") != std::string::npos);
    CHECK(glyphs->props.text.find("}") != std::string::npos);
    CHECK(glyphs->props.text.find("\u2192") != std::string::npos);
    CHECK(glyphs->props.text.find("#") != std::string::npos);
    CHECK(glyphs->props.text.find(".") != std::string::npos);
    CHECK(glyphs->props.text.find("\u2500") != std::string::npos);

    CHECK(find_node(root, "settings/theme/title")->props.accent);
    CHECK(!find_node(root, "settings/theme/body")->props.dim);
    CHECK(find_node(root, "settings/theme/dim")->props.dim);
    const ui::Node* selected = find_node(root, "settings/theme/selected");
    CHECK(selected != nullptr);
    CHECK_EQ(int(selected->props.bg.r), 19);
    CHECK_EQ(int(selected->props.fg.r), 20);
    const ui::Node* bar = find_node(root, "settings/theme/bar");
    CHECK(bar != nullptr);
    CHECK_EQ(bar->props.ratio, 0.6f);

    // 样张在设置行区域内、不压到底部字体预览
    const ui::Node* preview = find_node(root, "settings/preview");
    CHECK(preview != nullptr);
    CHECK(sample->rect.y + sample->rect.h <= preview->rect.y);
    CHECK(sample->rect.x >= area.x && sample->rect.x + sample->rect.w <= area.x + area.w);

    // 搜索态保持紧凑：不插样张（旧搜索文本/布局不膨胀）
    SettingsSearch search;
    settings_search_begin(search);
    settings_search_apply_text(search, "音量");
    ui::Node filtered = ui::make_root("shell.settings");
    build_settings(filtered, ctx, area, &search);
    CHECK(find_node(filtered, "settings/theme/sample") == nullptr);
}

TEST(shell_about_view_uses_version_and_host_keys) {
    const ui::Rect area{7, 11, 72, 37};
    ui::Theme theme;

    ui::Node zh = ui::make_root("shell.about");
    build_about(zh, Lang::zh, area);
    ui::measure(zh, area.w, theme);
    ui::arrange(zh, area, theme);

    const ui::Node* product = find_node(zh, "about/product");
    CHECK(product != nullptr);
    CHECK(product->props.text.find(kProductName) != std::string::npos);
    CHECK(product->props.text.find(kVersion) != std::string::npos);
    CHECK(find_node(zh, "about/build") != nullptr);
    CHECK(find_node(zh, "about/ops/settings") != nullptr);
    CHECK(find_node(zh, "about/ops/search") != nullptr);
    CHECK(find_node(zh, "about/ops/about") != nullptr);
    CHECK(find_node(zh, "about/ops/f12") != nullptr);
    CHECK(find_node(zh, "about/content/body") != nullptr);
    CHECK(find_node(zh, "about/credits/body") != nullptr);
    CHECK(find_node(zh, "about/licenses") != nullptr);
    CHECK(find_node(zh, "about/hint") != nullptr);
    CHECK(find_node(zh, "about/rule0") != nullptr);

    ui::Node en = ui::make_root("shell.about");
    build_about(en, Lang::en, area);
    CHECK_EQ(find_node(en, "about/ops/title")->props.text, std::string("BASIC CONTROLS"));
    CHECK_EQ(find_node(en, "about/credits/title")->props.text, std::string("CREDITS"));
}

TEST(shell_controls_rows_show_effective_physical_keys) {
    // 默认（无映射）：每个动作显示同名物理键
    controls::ScreenState state;
    const ui::Rect content = content_rect();
    ui::Node root = build_controls(state, content, Lang::zh);
    const ui::Node* row0 = find_node(root, controls::row_id(0));
    CHECK(row0 != nullptr);
    CHECK(row0->props.text.find("LEFT") != std::string::npos);
    CHECK(row0->props.text.find("< left >") != std::string::npos);
    CHECK(find_node(root, controls::kBackId) != nullptr);

    // 多物理键到同一动作 + 一条改绑：按物理键名字典序显示
    state.set_bindings({{"h", "left"}, {"left", "left"}, {"space", "a"}});
    ui::Node root2 = build_controls(state, content, Lang::en);
    const ui::Node* row = find_node(root2, controls::row_id(0));
    CHECK(row->props.text.find("h, left") != std::string::npos);
    const ui::Node* row_a = find_node(root2, controls::row_id(4));
    CHECK(row_a->props.text.find("space") != std::string::npos);
}

TEST(shell_controls_capture_flow_and_conflict) {
    controls::ScreenState state;
    const std::map<std::string, std::string> bindings{
        {"h", "right"}, {"space", "a"}, {"left", "left"}};
    state.set_bindings(bindings);
    state.select(0);  // left
    CHECK_EQ(std::string(state.selected_action()), std::string("left"));

    state.begin_capture();
    CHECK(state.capturing());
    // 捕获态树：提示目标动作 + 取消按钮
    ui::Node capture = build_controls(state, content_rect(), Lang::en);
    CHECK(find_node(capture, "controls/capture_hint") != nullptr);
    CHECK(find_node(capture, "controls/capture_hint")->props.text.find("left") != std::string::npos);
    CHECK(find_node(capture, controls::kCancelId) != nullptr);

    // h 原来绑在 right：覆盖并返回旧动作；捕获结束
    const std::string replaced = state.apply_capture("h");
    CHECK_EQ(replaced, std::string("right"));
    CHECK(!state.capturing());
    CHECK_EQ(state.bindings().at("h"), std::string("left"));

    // 绑回同名键 = 删除显式映射（保持配置文件干净）
    state.select(0);
    state.begin_capture();
    CHECK(state.apply_capture("left").empty());
    CHECK(state.bindings().find("left") == state.bindings().end());

    // 物理键 = 自己的动作且在别处有旧绑定时，也会报告被覆盖的动作
    state.select(2);  // up
    state.begin_capture();
    CHECK_EQ(state.apply_capture("space"), std::string("a"));
    CHECK_EQ(state.bindings().at("space"), std::string("up"));
}

TEST(shell_tape_clipboard_code_normalization) {
    // 剪贴板里的码常带换行/空格/小写；粘贴前统一去空白并转大写，
    // 合法性判断与输入页的过滤（0-9/A-F）是同一套
    CHECK_EQ(tape::ScreenState::compact_code(" a1\r\nB2\t"), std::string("A1B2"));
    CHECK_EQ(tape::ScreenState::compact_code(""), std::string(""));
    CHECK(tape::ScreenState::is_valid_code("0123456789ABCDEF"));
    CHECK(!tape::ScreenState::is_valid_code(""));
    CHECK(!tape::ScreenState::is_valid_code("A1G2"));
    CHECK(!tape::ScreenState::is_valid_code("a1b2"));  // compact 后才是合法输入
}

TEST(shell_tape_clipboard_result_rows) {
    tape::ScreenState state;
    state.set_tape("SNAKE", "A1B2", true);
    state.set_result(tape::ScreenState::Result::copied);
    ui::Node root = build_tape(state, content_rect(), Lang::en, "");
    const ui::Node* result = find_node(root, "tape/result");
    CHECK(result != nullptr);
    CHECK_EQ(result->props.text, std::string(tr(Lang::en, Msg::tape_copied)));

    state.set_result(tape::ScreenState::Result::clipboard_invalid);
    root = build_tape(state, content_rect(), Lang::zh, "");
    result = find_node(root, "tape/result");
    CHECK(result != nullptr);
    CHECK_EQ(result->props.text, std::string(tr(Lang::zh, Msg::tape_clipboard_invalid)));
}

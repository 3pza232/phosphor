// 外壳界面（声明式迁移后）的纯逻辑测试：磁带码界面的元素树几何与页面语义。
// 与 test_ui.cpp 同一套路：Frame/Node 直接排布到网格，不依赖 GL/Lua。
//
// 只测"能写进单元测试的部分"：暂停菜单与 Mod 浮窗的构建函数是 Shell 的私有实现
// （依赖整机状态），它们由 tools/shell_golden.py 的逐字节基线覆盖。

#include "harness.hpp"

#include "core/input.hpp"
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

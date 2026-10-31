// UI 组件库的纯逻辑测试：布局、焦点、输入事件、设置界面几何。
// 不依赖 GL/Lua：Frame 直接画到 Screen 上，所以这些是真正的单元测试。

#include "harness.hpp"

#include "core/input.hpp"
#include "core/screen.hpp"
#include "shell/messages.hpp"
#include "shell/settings_view.hpp"
#include "ui/frame.hpp"
#include "ui/toast.hpp"
#include "ui/layout.hpp"

#include <string>

using namespace phos;

namespace {

ui::Node* find_node(ui::Node& root, const std::string& id) {
    if (root.id == id) return &root;
    for (ui::Node& child : root.children)
        if (ui::Node* found = find_node(child, id)) return found;
    return nullptr;
}

TEST(ui_scroll_horizontal_clip_and_follow) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Frame frame("h", state, theme, ui::Rect{0, 0, 8, 4}, &input);
    ui::Node& scroll = frame.root().add_scroll("hs", 2);
    scroll.props.width = 4;
    scroll.props.scroll_x = 2;  // 显式横向初值：只露出第 3 列起
    scroll.add_text("row", "ABCDEF");
    frame.run();

    Screen screen(8, 4);
    frame.paint(screen);
    const std::string shown = screen.to_text();
    CHECK(shown.find("CDEF") != std::string::npos);
    CHECK(shown.find("AB") == std::string::npos);

    // 焦点横向出视口时自动跟随（按钮显式宽 6 > 视口 4）
    ui::Frame frame2("h2", state, theme, ui::Rect{0, 0, 8, 4}, &input);
    ui::Node& wide = frame2.root().add_scroll("hs2", 2);
    wide.props.width = 4;
    ui::Node& button = wide.add(ui::Kind::button, "wide");
    button.props.width = 6;
    button.props.text = "ABCDEF";
    frame2.run();
    CHECK_EQ(state.screen("h2").widgets["hs2"].scroll_x, 2);
}

} // namespace

TEST(ui_layout_column_and_padding) {
    ui::Theme theme;
    ui::Node root = ui::make_root("root");
    root.props.padding = ui::Insets{1, 2, 1, 2};
    root.add_text("a", "hello");
    root.add_text("b", "x");
    ui::Rect area{10, 5, 20, 10};
    ui::measure(root, area.w, theme);
    ui::arrange(root, area, theme);

    const ui::Node* a = find_node(root, "a");
    CHECK_EQ(a->rect.x, 11);
    CHECK_EQ(a->rect.y, 7);
    CHECK_EQ(a->rect.w, 18);  // stretch：撑满内容宽
    CHECK_EQ(a->rect.h, 1);
    const ui::Node* b = find_node(root, "b");
    CHECK_EQ(b->rect.y, 8);
}

TEST(ui_scroll_viewport_clips_and_offsets) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Rect area{0, 0, 12, 10};
    ui::Frame frame("t", state, theme, area, &input);
    ui::Node& scroll = frame.root().add_scroll("sc", 3);
    scroll.props.scroll = 2;  // 显式偏移：从第 3 项开始显示
    scroll.props.gap = 0;
    for (int i = 0; i < 5; ++i) scroll.add_text("r" + std::to_string(i), std::to_string(i));
    frame.run();

    Screen screen(12, 10);
    frame.paint(screen);
    const std::string text = screen.to_text();
    CHECK(text.find("2") != std::string::npos);
    CHECK(text.find("3") != std::string::npos);
    CHECK(text.find("4") != std::string::npos);
    CHECK(text.find("0") == std::string::npos);  // 偏移到视口外的行不画
    CHECK(text.find("1") == std::string::npos);
}

TEST(ui_scroll_follows_focused_child) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Rect area{0, 0, 12, 10};
    ui::Frame frame("t", state, theme, area, &input);
    ui::Node& scroll = frame.root().add_scroll("sc", 3);
    scroll.props.gap = 0;
    for (int i = 0; i < 5; ++i) scroll.add(ui::Kind::button, "b" + std::to_string(i)).props.text =
        std::to_string(i);
    frame.run();
    CHECK_EQ(frame.focused_id(), std::string("b0"));

    for (int i = 0; i < 4; ++i) {
        input.set_key("down", true);
        frame.run();
        input.next_frame();
        input.set_key("down", false);
        input.next_frame();
    }
    CHECK_EQ(frame.focused_id(), std::string("b4"));
    CHECK_EQ(state.screen("t").widgets["sc"].scroll, 2);  // 视口 3 行：滚到 2..4

    Screen screen(12, 10);
    frame.paint(screen);
    const std::string shown = screen.to_text();
    CHECK(shown.find("4") != std::string::npos);
    CHECK(shown.find("0") == std::string::npos);
}

TEST(ui_toast_push_expire_and_paint) {
    ui::Theme theme;
    ui::Toasts toasts;
    CHECK(toasts.empty());

    toasts.push("SAVED", 1.0f);
    CHECK_EQ(toasts.size(), size_t(1));

    Screen screen(60, 20);
    toasts.paint(screen, theme, ui::Rect{0, 0, 60, 20});
    CHECK(screen.to_text().find("SAVED") != std::string::npos);

    toasts.update(0.6f);
    CHECK_EQ(toasts.size(), size_t(1));
    toasts.update(0.6f);
    CHECK(toasts.empty());

    Screen blank(60, 20);
    toasts.paint(blank, theme, ui::Rect{0, 0, 60, 20});
    CHECK(blank.to_text().find("SAVED") == std::string::npos);
}

TEST(ui_grid_measure_and_arrange) {
    ui::Theme theme;
    ui::Node root = ui::make_root("root");
    ui::Node& grid = root.add_grid("g", 2);
    grid.props.gap = 1;
    for (int i = 0; i < 4; ++i) grid.add_text("c" + std::to_string(i), "x");
    ui::Rect area{2, 1, 21, 8};
    ui::measure(root, area.w, theme);
    ui::arrange(root, area, theme);

    // 2 列 4 项 → 2 行、每行高 1、行间 1 格
    CHECK_EQ(grid.natural_h, 3);
    const ui::Node* c0 = find_node(root, "c0");
    const ui::Node* c1 = find_node(root, "c1");
    const ui::Node* c2 = find_node(root, "c2");
    CHECK_EQ(c0->rect.x, 2);
    CHECK_EQ(c1->rect.x, 13);  // (21 - 1) / 2 = 10 列宽，间隔 1
    CHECK_EQ(c0->rect.w, 10);
    CHECK_EQ(c2->rect.y, 3);   // 第二行（行高 1 + 间隔 1）
}

TEST(ui_table_column_widths) {
    ui::Props props;
    props.columns = {"A", "SCORE"};
    props.rows = {{"1", "1200"}, {"2", "90"}};
    const auto natural = ui::table_column_widths(props, 0);
    CHECK_EQ(natural.size(), 2u);
    CHECK_EQ(natural[0], 1);
    CHECK_EQ(natural[1], 5);

    const auto stretched = ui::table_column_widths(props, 20);
    int total = 2;  // 列间固定 2 格
    for (int width : stretched) total += width;
    CHECK_EQ(total, 20);  // 余量均摊后铺满可用宽度

    props.widths = {3, 0};
    const auto fixed = ui::table_column_widths(props, 0);
    CHECK_EQ(fixed[0], 3);
    CHECK_EQ(fixed[1], 5);
}

TEST(ui_table_measure) {
    ui::Theme theme;
    ui::Node root = ui::make_root("root");
    ui::Node& table = root.add_table("t");
    table.props.columns = {"RANK", "NAME"};
    table.props.rows = {{"1", "A"}, {"2", "B"}};
    ui::Rect area{0, 0, 40, 10};
    ui::measure(root, area.w, theme);
    CHECK_EQ(table.natural_h, 4);  // 表头 + 分隔线 + 2 行
    CHECK_EQ(table.natural_w, 4 + 2 + 4);  // RANK / NAME 各 4，列间 2
}

TEST(ui_layout_grow_distributes_leftover) {
    ui::Theme theme;
    ui::Node root = ui::make_root("root");
    root.add_text("top", "t");
    ui::Node& fill = root.add(ui::Kind::spacer, "fill");
    fill.props.grow = 1;
    ui::Node& bottom = root.add_text("bottom", "b");
    bottom.props.grow = 1;
    ui::Rect area{0, 0, 10, 10};
    ui::measure(root, area.w, theme);
    ui::arrange(root, area, theme);

    const ui::Node* f = find_node(root, "fill");
    const ui::Node* b = find_node(root, "bottom");
    CHECK_EQ(f->rect.y, 1);
    CHECK_EQ(b->rect.y, 1 + f->rect.h);
    CHECK_EQ(b->rect.y + b->rect.h, 10);
}

TEST(ui_focus_order_and_events) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Rect area{0, 0, 20, 10};
    ui::Frame frame("t", state, theme, area, &input);
    frame.root().add_option("one", "ONE");
    frame.root().add_option("two", "TWO");
    frame.root().add_text("label", "L");

    // 与主循环一致的按键序列：按下 → 这一帧 run → 推进输入帧 → 松开
    auto press = [&](const char* key) {
        input.set_key(key, true);
        auto events = frame.run();
        input.next_frame();
        input.set_key(key, false);
        input.next_frame();
        return events;
    };

    CHECK(frame.run().empty());
    CHECK_EQ(frame.focused_id(), std::string("one"));

    press("down");
    CHECK_EQ(frame.focused_id(), std::string("two"));

    const auto events = press("right");
    CHECK_EQ(events.size(), size_t(1));
    CHECK_EQ(int(events[0].kind), int(ui::EventKind::changed));
    CHECK_EQ(events[0].delta, 1);
}

TEST(ui_tab_moves_focus_out_of_list) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Rect area{0, 0, 20, 10};
    ui::Frame frame("t", state, theme, area, &input);
    ui::Node& list = frame.root().add_list("list", {"a", "b"});
    list.props.height = 2;
    frame.root().add_checkbox("chk", "C");
    frame.run();
    CHECK_EQ(frame.focused_id(), std::string("list"));

    input.set_key("tab", true);
    frame.run();
    input.next_frame();
    input.set_key("tab", false);
    input.next_frame();
    CHECK_EQ(frame.focused_id(), std::string("chk"));
}

TEST(ui_list_cursor_wraps_and_scrolls) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Rect area{0, 0, 10, 3};
    ui::Frame frame("t", state, theme, area, &input);
    ui::Node& list = frame.root().add_list("list", {"a", "b", "c", "d"});
    list.props.height = 3;  // 视口高度由声明给出（与外壳的固定面板一致）
    frame.run();
    CHECK_EQ(frame.focused_id(), std::string("list"));

    input.set_key("up", true);
    auto events = frame.run();
    input.next_frame();
    input.set_key("up", false);
    input.next_frame();
    CHECK(events.empty());
    // 光标从 0 回绕到最后一行；视口 3 行，滚动窗口应跟到 1
    CHECK_EQ(state.screen("t").widgets["list"].cursor, 3);
    CHECK_EQ(state.screen("t").widgets["list"].scroll, 1);

    input.set_key("start", true);
    events = frame.run();
    input.next_frame();
    input.set_key("start", false);
    input.next_frame();
    CHECK_EQ(events.size(), size_t(1));
    CHECK_EQ(events[0].index, 3);
}

TEST(ui_list_hold_repeats) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Rect area{0, 0, 10, 4};
    ui::Frame frame("t", state, theme, area, &input);
    ui::Node& list = frame.root().add_list("list", {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9"});
    list.props.height = 4;
    frame.run();
    CHECK_EQ(frame.focused_id(), std::string("list"));

    input.set_key("down", true);
    frame.run();  // 点按那一帧：光标 0 → 1
    CHECK_EQ(state.screen("t").widgets["list"].cursor, 1);

    // 按住不足延迟：不再移动
    for (int i = 0; i < 12; ++i) {
        input.next_frame();
        frame.run();
    }
    CHECK_EQ(state.screen("t").widgets["list"].cursor, 1);

    // 到延迟后开始每 3 帧一格
    for (int i = 0; i < 6; ++i) {
        input.next_frame();
        frame.run();
    }
    CHECK_EQ(state.screen("t").widgets["list"].cursor, 2);
    for (int i = 0; i < 3; ++i) {
        input.next_frame();
        frame.run();
    }
    CHECK_EQ(state.screen("t").widgets["list"].cursor, 3);

    // 松键后重复计时清零：再次点按只走一格
    input.next_frame();
    input.set_key("down", false);
    frame.run();
    input.next_frame();
    input.set_key("down", true);
    frame.run();
    CHECK_EQ(state.screen("t").widgets["list"].cursor, 4);
}

TEST(ui_settings_geometry_matches_shell_layout) {
    SettingsContext ctx;
    ctx.lang = Lang::zh;

    ui::Theme theme;
    ui::State state;
    Input input;
    const ui::Rect area{7, 11, 72, 37};
    ui::Frame frame("shell.settings", state, theme, area, &input);
    build_settings(frame.root(), ctx, area);
    frame.run();

    const ui::Node* preview = find_node(frame.root(), "settings/preview");
    CHECK(preview != nullptr);
    CHECK_EQ(preview->rect.x, 9);
    CHECK_EQ(preview->rect.y, 38);
    CHECK_EQ(preview->rect.w, 68);
    CHECK_EQ(preview->rect.h, 6);

    const ui::Node* cjk = find_node(frame.root(), "settings/preview/cjk");
    CHECK(cjk != nullptr);
    CHECK_EQ(cjk->rect.y, 41);

    const ui::Node* theme_row = find_node(frame.root(), "settings/theme");
    CHECK(theme_row != nullptr);
    CHECK_EQ(theme_row->rect.y, 12);  // 首行是分区标题，第一项在它下一行
    CHECK_EQ(theme_row->rect.x, 7);
}
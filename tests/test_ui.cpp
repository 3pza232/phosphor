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

TEST(ui_scroll_draws_position_bars) {
    ui::Theme theme;
    ui::State state;
    Input input;

    // 纵向溢出：右侧一列应有轨道/滑块
    ui::Frame frame("v", state, theme, ui::Rect{0, 0, 10, 4}, &input);
    ui::Node& scroll = frame.root().add_scroll("vs", 2);
    scroll.props.width = 6;
    for (int i = 0; i < 5; ++i) scroll.add_text("r" + std::to_string(i), std::to_string(i));
    frame.run();
    Screen vertical(10, 4);
    frame.paint(vertical);
    int vertical_marks = 0;
    for (int y = 0; y < 2; ++y) {
        const char32_t ch = vertical.at(5, y).ch;  // inner 宽 6 → 最后一列 x=5
        if (ch == theme.glyphs.scroll_thumb || ch == theme.glyphs.scroll_track) ++vertical_marks;
    }
    CHECK_EQ(vertical_marks, 2);

    // 横向溢出：底部一行应有轨道/滑块
    ui::Frame frame2("h", state, theme, ui::Rect{0, 0, 10, 4}, &input);
    ui::Node& wide = frame2.root().add_scroll("hs", 2);
    wide.props.width = 6;
    wide.add_text("row", "ABCDEFGHIJ");
    frame2.run();
    Screen horizontal(10, 4);
    frame2.paint(horizontal);
    int horizontal_marks = 0;
    for (int x = 0; x < 6; ++x) {
        const char32_t ch = horizontal.at(x, 1).ch;  // inner 高 2 → 最后一行 y=1
        if (ch == theme.glyphs.scroll_thumb || ch == theme.glyphs.scroll_track) ++horizontal_marks;
    }
    CHECK(horizontal_marks > 0);

    // 关掉滚动条：同一个屏不应再出现指示字符
    ui::Frame frame3("off", state, theme, ui::Rect{0, 0, 10, 4}, &input);
    ui::Node& off = frame3.root().add_scroll("off", 2);
    off.props.width = 6;
    off.props.scrollbar = false;
    for (int i = 0; i < 5; ++i) off.add_text("o" + std::to_string(i), std::to_string(i));
    frame3.run();
    Screen none(10, 4);
    frame3.paint(none);
    CHECK_EQ(int(none.at(5, 0).ch), int(U' '));
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

TEST(ui_nested_scroll_clips_and_follows_levels) {
    // 外层 scroll（视口 3 行）套内层 scroll（视口 2 行）：
    // 内层自己滚自己的，外层只在焦点真的出到外层视口外时才跟着滚
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Frame frame("nested", state, theme, ui::Rect{0, 0, 10, 5}, &input);
    ui::Node& outer = frame.root().add_scroll("outer", 3);
    outer.props.gap = 0;
    outer.add_text("head", "HEAD");
    ui::Node& inner = outer.add_scroll("inner", 2);
    inner.props.gap = 0;
    for (int i = 0; i < 4; ++i)
        inner.add(ui::Kind::button, "b" + std::to_string(i)).props.text = "B" + std::to_string(i);
    outer.add_text("tail", "TAIL");
    frame.run();
    CHECK_EQ(frame.focused_id(), std::string("b0"));

    auto press = [&](const char* key) {
        input.set_key(key, true);
        frame.run();
        input.next_frame();
        input.set_key(key, false);
        input.next_frame();
    };
    auto& widgets = state.screen("nested").widgets;
    CHECK_EQ(widgets["outer"].scroll, 0);
    CHECK_EQ(widgets["inner"].scroll, 0);

    // b0 → b1：两层都还在视口内，不滚
    press("down");
    CHECK_EQ(frame.focused_id(), std::string("b1"));
    CHECK_EQ(widgets["outer"].scroll, 0);
    CHECK_EQ(widgets["inner"].scroll, 0);

    // b1 → b2：内层先滚 1 行；外层视口底边刚好被顶到，也滚 1 行
    press("down");
    CHECK_EQ(frame.focused_id(), std::string("b2"));
    CHECK_EQ(widgets["inner"].scroll, 1);
    CHECK_EQ(widgets["outer"].scroll, 1);

    // b2 → b3：只内层再滚，外层停住（只在需要的层级滚）
    press("down");
    CHECK_EQ(frame.focused_id(), std::string("b3"));
    CHECK_EQ(widgets["inner"].scroll, 2);
    CHECK_EQ(widgets["outer"].scroll, 1);

    Screen bottom(10, 5);
    frame.paint(bottom);
    const std::string bottom_text = bottom.to_text();
    CHECK(bottom_text.find("B2") != std::string::npos);
    CHECK(bottom_text.find("B3") != std::string::npos);
    CHECK(bottom_text.find("B0") == std::string::npos);  // 两层裁剪叠加：内层顶出视口
    CHECK(bottom_text.find("B1") == std::string::npos);
    // 外层视口最右列是滚动条（内层条同列会被外层覆盖，这层语义由外层指示）
    bool track = false, thumb = false;
    for (int y = 0; y < 3; ++y) {
        track = track || bottom.at(9, y).ch == theme.glyphs.scroll_track;
        thumb = thumb || bottom.at(9, y).ch == theme.glyphs.scroll_thumb;
    }
    CHECK(track);
    CHECK(thumb);

    // 往回：b2→b1 时内层滚回 1、外层先回 0；回到 b0 两层都归 0
    press("up");
    CHECK_EQ(frame.focused_id(), std::string("b2"));
    press("up");
    CHECK_EQ(frame.focused_id(), std::string("b1"));
    CHECK_EQ(widgets["inner"].scroll, 1);
    CHECK_EQ(widgets["outer"].scroll, 0);
    press("up");
    CHECK_EQ(frame.focused_id(), std::string("b0"));
    CHECK_EQ(widgets["inner"].scroll, 0);
    CHECK_EQ(widgets["outer"].scroll, 0);

    Screen top(10, 5);
    frame.paint(top);
    CHECK(top.to_text().find("HEAD") != std::string::npos);
    CHECK(top.to_text().find("B0") != std::string::npos);
}

TEST(ui_grid_margins_and_unequal_row_heights) {
    // cols=2 / gap=1；第一行有 2 行高 + 四边 margin 的 spacer，第二行是普通 text
    ui::Theme theme;
    ui::Node root = ui::make_root("root");
    ui::Node& grid = root.add_grid("g", 2);
    grid.props.gap = 1;
    ui::Node& tall = grid.add(ui::Kind::spacer, "tall");
    tall.props.height = 2;
    tall.props.margin = ui::Insets{1, 1, 1, 1};
    grid.add_text("b", "B");
    grid.add_text("c", "C");
    ui::Node& shifted = grid.add(ui::Kind::spacer, "shifted");
    shifted.props.height = 1;
    shifted.props.margin.l = 2;

    const ui::Rect area{2, 1, 21, 10};
    ui::measure(root, area.w, theme);
    ui::arrange(root, area, theme);

    // 行高取 max(内容高 + 上下 margin)：第一行 = 2+1+1 = 4，第二行 = 1，行间 gap = 1
    CHECK_EQ(grid.natural_h, 6);
    const ui::Node* t = find_node(root, "tall");
    const ui::Node* b = find_node(root, "b");
    const ui::Node* c = find_node(root, "c");
    const ui::Node* s = find_node(root, "shifted");
    CHECK_EQ(t->rect.x, 3);   // grid.x(2) + margin.l(1)
    CHECK_EQ(t->rect.y, 2);   // grid.y(1) + margin.t(1)
    CHECK_EQ(t->rect.w, 8);   // cell 10 - margin.l/r
    CHECK_EQ(t->rect.h, 2);   // 内容高，不含 margin
    CHECK_EQ(b->rect.x, 13);  // 第二列：2 + (10 + 1)
    CHECK_EQ(b->rect.y, 1);
    CHECK_EQ(c->rect.y, 6);   // 1 + 行高 4 + gap 1
    CHECK_EQ(s->rect.x, 15);  // 13 + margin.l(2)
    CHECK_EQ(s->rect.w, 8);   // cell 10 - margin.l(2)
}

TEST(ui_table_widths_and_alignment) {
    // 显式 widths 是固定宽；只有自适应列（0/缺省）参与余量摊分
    ui::Props props;
    props.columns = {"A", "B"};
    props.rows = {{"x", "12345"}};
    props.widths = {4, 0};
    const auto natural = ui::table_column_widths(props, 0);
    CHECK_EQ(natural.size(), 2u);
    CHECK_EQ(natural[0], 4);
    CHECK_EQ(natural[1], 5);
    const auto exact = ui::table_column_widths(props, 4 + 5 + 2);
    CHECK_EQ(exact[0], 4);  // 刚够自然宽度：不摊
    CHECK_EQ(exact[1], 5);

    const auto stretched = ui::table_column_widths(props, 20);
    // 20 - (4+5+2) = 9 全部给自适应列 B（A 是固定宽）→ {4, 14}
    CHECK_EQ(stretched[0], 4);
    CHECK_EQ(stretched[1], 14);

    // 对齐与截断：固定 4/4/4 三列，列间固定 2 格
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Frame frame("table", state, theme, ui::Rect{0, 0, 16, 5}, &input);
    ui::Node& table = frame.root().add_table("tbl");
    table.props.columns = {"A", "B", "C"};
    table.props.widths = {4, 4, 4};
    table.props.col_align = {ui::Align::start, ui::Align::center, ui::Align::end};
    table.props.rows = {{"L", "M", "R"}, {"ABCDEFGH", "x", "12345"}};
    frame.run();

    Screen screen(16, 5);
    frame.paint(screen);
    CHECK_EQ(screen.at(0, 0).ch, U'A');
    CHECK_EQ(screen.at(7, 0).ch, U'B');   // 6 + (4-1)/2
    CHECK_EQ(screen.at(15, 0).ch, U'C');  // 12 + (4-1)
    CHECK_EQ(screen.at(0, 2).ch, U'L');
    CHECK_EQ(screen.at(7, 2).ch, U'M');
    CHECK_EQ(screen.at(15, 2).ch, U'R');
    // 超长单元格：width=4 时 ellipsis 截成 3 个字符 + '…'
    CHECK_EQ(screen.at(0, 3).ch, U'A');
    CHECK_EQ(screen.at(3, 3).ch, U'\u2026');
    CHECK_EQ(screen.at(12, 3).ch, U'1');
    CHECK_EQ(screen.at(15, 3).ch, U'\u2026');
    // 表头下自动分隔线
    CHECK_EQ(screen.at(0, 1).ch, U'\u2500');
    CHECK_EQ(screen.at(15, 1).ch, U'\u2500');
}

TEST(ui_option_left_right_confirm_and_bounds) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Frame frame("opt", state, theme, ui::Rect{0, 0, 10, 2}, &input);
    frame.root().add_option("quality", "QUALITY");
    frame.run();
    CHECK_EQ(frame.focused_id(), std::string("quality"));

    auto press = [&](const char* key) {
        input.set_key(key, true);
        const auto events = frame.run();
        input.next_frame();
        input.set_key(key, false);
        input.next_frame();
        return events;
    };
    auto left = press("left");
    CHECK_EQ(left.size(), 1u);
    CHECK_EQ(int(left[0].kind), int(ui::EventKind::changed));
    CHECK_EQ(left[0].delta, -1);
    CHECK(!left[0].confirm);

    auto right = press("right");
    CHECK_EQ(right.size(), 1u);
    CHECK_EQ(right[0].delta, 1);
    CHECK(!right[0].confirm);

    auto confirm = press("start");
    CHECK_EQ(confirm.size(), 1u);
    CHECK_EQ(confirm[0].delta, 1);
    CHECK(confirm[0].confirm);  // 确认键是"进一档"，不是切换

    // 左右同时按：方向不清，引擎不发事件（值由卡带持有，不存在越界加减）
    input.set_key("left", true);
    input.set_key("right", true);
    const auto both = frame.run();
    CHECK(both.empty());
    input.next_frame();
    input.set_key("left", false);
    input.set_key("right", false);
    input.next_frame();
}

TEST(ui_field_typing_limit_backspace_and_ime) {
    ui::Theme theme;
    ui::State state;
    Input input;
    ui::Frame frame("field", state, theme, ui::Rect{0, 0, 12, 1}, &input);
    ui::Node& field = frame.root().add_field("name", "hint");
    field.props.max_chars = 3;
    field.props.width = 8;
    frame.run();
    CHECK_EQ(frame.focused_id(), std::string("name"));
    CHECK(frame.ime_requested());  // 文本域聚焦：这一帧请求 IME

    input.push_text("abcdef");  // max_chars=3：只收前三个码点
    frame.run();
    CHECK_EQ(frame.field_text("name"), std::string("abc"));
    input.next_frame();

    input.push_text("x\by");  // x 被限长拒绝；\b 删掉 c；y 追加
    frame.run();
    CHECK_EQ(frame.field_text("name"), std::string("aby"));
    input.next_frame();

    input.push_text("\b\u4E2D");  // 删掉 y 后追加一个全角字（按码点计数）
    frame.run();
    CHECK_EQ(frame.field_text("name"), std::string("ab\u4E2D"));
    input.next_frame();

    input.set_key("start", true);
    const auto events = frame.run();
    input.next_frame();
    input.set_key("start", false);
    input.next_frame();
    CHECK_EQ(events.size(), 1u);
    CHECK_EQ(int(events[0].kind), int(ui::EventKind::submitted));
    CHECK_EQ(events[0].text, std::string("ab\u4E2D"));

    // paint-only 帧（input == nullptr）：只排布/绘制，不能请求 IME，也不能消费文本
    ui::Frame paint_only("field", state, theme, ui::Rect{0, 0, 12, 1}, nullptr);
    ui::Node& paint_field = paint_only.root().add_field("name", "hint");
    paint_field.props.max_chars = 3;
    paint_field.props.width = 8;
    paint_only.run();
    CHECK(!paint_only.ime_requested());
    CHECK_EQ(paint_only.field_text("name"), std::string("ab\u4E2D"));

    Screen screen(12, 1);
    paint_only.paint(screen);
    CHECK(screen.to_text().find("ab\u4E2D") != std::string::npos);
}

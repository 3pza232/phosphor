// UI 组件库的纯逻辑测试：布局、焦点、输入事件、设置界面几何。
// 不依赖 GL/Lua：Frame 直接画到 Screen 上，所以这些是真正的单元测试。

#include "harness.hpp"

#include "core/input.hpp"
#include "core/screen.hpp"
#include "shell/messages.hpp"
#include "shell/settings_view.hpp"
#include "ui/frame.hpp"
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
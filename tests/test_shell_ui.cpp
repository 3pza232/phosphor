// 外壳界面（声明式迁移后）的纯逻辑测试：磁带码界面的元素树几何与页面语义。
// 与 test_ui.cpp 同一套路：Frame/Node 直接排布到网格，不依赖 GL/Lua。
//
// 只测"能写进单元测试的部分"：暂停菜单与 Mod 浮窗的构建函数是 Shell 的私有实现
// （依赖整机状态），它们由 tools/shell_golden.py 的逐字节基线覆盖。

#include "harness.hpp"

#include "core/input.hpp"
#include "shell/layout.hpp"
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

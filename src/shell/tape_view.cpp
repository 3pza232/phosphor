#include "shell/tape_view.hpp"

#include "core/text.hpp"
#include "shell/layout.hpp"

#include <algorithm>
#include <cstdio>
#include <utility>
#include <vector>

namespace phos::tape {

namespace {

/// 查看页：码本体按显示宽度折行后的各行，可分页滚动
void draw_view(Screen& screen, int left, int top, int rows, int status_row,
               const std::vector<std::string>& lines, int scroll_in, Lang lang,
               const ui::Style& style) {
    ui::print(screen, left, top, tr(lang, Msg::tape_code_label), style.dim, style.bg);
    const int first = top + 1;
    const int visible = rows - 1;  // 标题占掉一行
    const int total = static_cast<int>(lines.size());
    const int scroll = std::clamp(scroll_in, 0, std::max(0, total - visible));

    // 位置行用 %d 格式化：文案在文案表里（含参数顺序），这里只填数字
    char position[128];
    std::snprintf(position, sizeof(position), tr(lang, Msg::tape_scroll), scroll + 1, total);
    ui::print(screen, left, status_row - 1, position, style.dim, style.bg);

    for (int row = 0; row < visible && scroll + row < total; ++row)
        ui::print(screen, left, first + row, lines[static_cast<size_t>(scroll + row)], style.fg,
                  style.bg);
}

/// 输入页：把玩家敲进去的码逐行画出来（已输入位数由 typed 给出）
void draw_edit(Screen& screen, int left, int top, int rows, int status_row,
               const std::vector<std::string>& lines, int typed, Lang lang,
               const ui::Style& style) {
    ui::print(screen, left, top, tr(lang, Msg::tape_input_label), style.dim, style.bg);
    const int visible = rows - 1;
    for (int row = 0; row < visible && row < static_cast<int>(lines.size()); ++row)
        ui::print(screen, left, top + 1 + row, lines[static_cast<size_t>(row)], style.fg, style.bg);

    char typed_text[64];
    std::snprintf(typed_text, sizeof(typed_text), tr(lang, Msg::tape_typed), typed);
    ui::print(screen, left, status_row - 1, typed_text, style.dim, style.bg);
}

} // namespace

void ScreenState::set_tape(std::string cart_name, std::string code, bool available) {
    cart_ = std::move(cart_name);
    code_ = std::move(code);
    available_ = available;
}

void ScreenState::open() {
    edit_ = false;
    scroll_ = 0;
    input_.clear();
    result_ = Result::none;
}

Msg ScreenState::page_hint() const {
    // 没有存档时"输入"没有意义（敲进来也无处可写），标题栏就别显示它——
    // 页脚这时也已经换成"返回"提示，两处说的必须是同一件事
    return available_ && edit_ ? Msg::tape_edit : Msg::tape_view;
}

Msg ScreenState::footer_hint() const { return available_ ? Msg::tape_footer : Msg::tape_back_hint; }

std::string ScreenState::update(const Input& input) {
    if (input.pressed(Key::left)) edit_ = false;
    if (input.pressed(Key::right)) edit_ = true;
    // 返回走 Esc（主机保留键，由 App 转发 handle_escape），这里不绑虚拟手柄键

    if (!edit_) {
        // 查看页：↑↓ 滚动（绘制时按可见行数夹紧）
        if (input.pressed(Key::up) && scroll_ > 0) --scroll_;
        if (input.pressed(Key::down)) ++scroll_;
        return {};
    }

    // 过滤、退格、限长都在 TextInput 里（删除按码点走，中文不会被删成半个）
    input_.apply(input.text());
    if (available_ && input.pressed(Key::start) && !input_.empty()) return input_.value();
    return {};
}

void ScreenState::draw(Screen& screen, const ui::Rect& content, Lang lang, const ui::Style& style) const {
    const int left = content.x + ShellLayout::kMarginX + 2;
    const int width = content.w - 2 * (ShellLayout::kMarginX + 2);
    const int status_row = content.bottom() - ShellLayout::kFooterGap - 2;
    int y = content.y + ShellLayout::kContentTop;

    if (!available_) {
        // 页脚由外壳按 footer_hint() 画成"返回"提示
        ui::print(screen, left, y + 1, tr(lang, Msg::tape_hint_no_save), style.dim, style.bg);
        return;
    }

    ui::print(screen, left, y++, std::string(tr(lang, Msg::tape_cart)) + cart_, style.fg, style.bg);
    ++y;

    // 磁带码是长十六进制串：按可用宽度折行，屏上只画得下中间那几行
    const std::vector<std::string> lines =
        text::wrap(edit_ ? input_.value() : code_, static_cast<size_t>(width));
    const int rows = std::max(1, status_row - y - 2);  // 再扣掉标题行

    if (edit_)
        draw_edit(screen, left, y, rows, status_row, lines, static_cast<int>(input_.count()), lang,
                  style);
    else
        draw_view(screen, left, y, rows, status_row, lines, scroll_, lang, style);

    if (result_ != Result::none) {
        const Msg id = result_ == Result::ok        ? Msg::tape_ok
                       : result_ == Result::invalid ? Msg::tape_invalid
                                                    : Msg::tape_no_save;
        ui::print(screen, left, status_row, tr(lang, id), style.accent, style.bg);
    }
}

} // namespace phos::tape

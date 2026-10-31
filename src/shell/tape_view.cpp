#include "shell/tape_view.hpp"

#include "core/text.hpp"
#include "shell/layout.hpp"

#include <algorithm>
#include <cstdio>
#include <utility>
#include <vector>

namespace phos::tape {

namespace {

/// 正文块行高：与旧版面的公式同源——状态行（位置/已输入）之上空一行，再上面一整块是正文。
/// 出厂几何（h=45、kContentTop=4）下是 31 行。
int body_rows(const ui::Rect& content) {
    return std::max(1, content.h - ShellLayout::kContentTop - 10);
}

/// 查看页的滚动首行（绘制与状态行共用同一份夹紧结果）
int first_row(const std::vector<std::string>& lines, int rows, int scroll) {
    return std::clamp(scroll, 0, std::max(0, static_cast<int>(lines.size()) - rows));
}

/// 可视窗口拼成的一段码。码是十六进制（全是半角），每个折行都是满宽，所以
/// "拼接后再交给 text 组件折行"得到的分界与原来逐行相同（组件没有"文本块滚动"这一种控件）
std::string visible_code(const std::vector<std::string>& lines, int rows, int scroll) {
    const int first = first_row(lines, rows, scroll);
    std::string out;
    for (int i = first; i < static_cast<int>(lines.size()) && i < first + rows; ++i)
        out += lines[static_cast<size_t>(i)];
    return out;
}

/// 状态行：查看页是"第 N 行起 / 共 M 行"（%d 的参数顺序由文案表决定，这里只填数字）
std::string scroll_text(Lang lang, const std::vector<std::string>& lines, int rows, int scroll) {
    char text[128];
    std::snprintf(text, sizeof(text), tr(lang, Msg::tape_scroll),
                  first_row(lines, rows, scroll) + 1, static_cast<int>(lines.size()));
    return text;
}

/// 状态行：输入页是"已输入 N 位"（按码点计，中文不会算成 3 位）
std::string typed_text(Lang lang, std::string_view typed) {
    char text[64];
    std::snprintf(text, sizeof(text), tr(lang, Msg::tape_typed),
                  static_cast<int>(text::decode(typed).size()));
    return text;
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
    result_ = Result::none;
}

Msg ScreenState::page_hint() const {
    // 没有存档时"输入"没有意义（敲进来也无处可写），标题栏就别显示它——
    // 页脚这时也已经换成"返回"提示，两处说的必须是同一件事
    return available_ && edit_ ? Msg::tape_edit : Msg::tape_view;
}

Msg ScreenState::footer_hint() const { return available_ ? Msg::tape_footer : Msg::tape_back_hint; }

std::string ScreenState::compact_code(std::string_view raw) {
    std::string out;
    out.reserve(raw.size());
    for (char ch : raw) {
        if (ch == ' ' || ch == '\t' || ch == '\r' || ch == '\n') continue;
        if (ch >= 'a' && ch <= 'f') ch = static_cast<char>(ch - 'a' + 'A');
        out.push_back(ch);
    }
    return out;
}

bool ScreenState::is_valid_code(std::string_view code) {
    if (code.empty() || code.size() > kMaxChars) return false;
    for (char ch : code)
        if (!((ch >= '0' && ch <= '9') || (ch >= 'A' && ch <= 'F'))) return false;
    return true;
}

void ScreenState::update(const Input& input) {
    if (input.pressed(Key::left)) edit_ = false;
    if (input.pressed(Key::right)) edit_ = true;
    // 返回走 Esc（主机保留键，由 App 转发 handle_escape），这里不绑虚拟手柄键

    if (edit_) return;
    // 查看页：↑↓ 滚动（绘制时按可见行数夹紧）
    if (input.pressed(Key::up) && scroll_ > 0) --scroll_;
    if (input.pressed(Key::down)) ++scroll_;
}

void ScreenState::build(ui::Node& root, const ui::Rect& content, Lang lang,
                        std::string_view typed) const {
    // 行区：左缘、首行与旧版面逐格一致，改写成内边距后正文各行的位置由流式布局算
    const ui::Insets pad{ShellLayout::kMarginX + 2, ShellLayout::kContentTop,
                         ShellLayout::kMarginX + 2, 0};
    root.props.padding = pad;
    const int width = std::max(1, content.w - pad.l - pad.r);
    const int rows = body_rows(content);

    if (!available_) {
        // 页脚由外壳画成"返回"提示；正文只说一句，位置与旧版面同行（空一行后打印）
        ui::Node& gap = root.add_spacer("tape/gap_hint");
        gap.props.height = 1;
        root.add_text("tape/hint", tr(lang, Msg::tape_hint_no_save)).props.dim = true;
        return;
    }

    root.add_text("tape/cart", std::string(tr(lang, Msg::tape_cart)) + cart_);
    ui::Node& gap = root.add_spacer("tape/gap_cart");
    gap.props.height = 1;

    if (edit_) {
        root.add_text("tape/label", tr(lang, Msg::tape_input_label)).props.dim = true;
        // 过滤（只收 0-9 与 A-F）、退格、限长都在文本域里：界面不再自己判断字符
        ui::Node& field = root.add_field(kFieldId, "");
        field.props.width = width;
        field.props.filter = ui::FieldFilter::hex;
        field.props.max_chars = static_cast<int>(kMaxChars);
        // 文本域占正文首行，其余留白与查看页的正文块 + 空行等高：
        // 状态行落在同一行，切页时画面不跳
        ui::Node& fill = root.add_spacer("tape/fill");
        fill.props.height = rows;
        root.add_text("tape/status", typed_text(lang, typed)).props.dim = true;
    } else {
        root.add_text("tape/label", tr(lang, Msg::tape_code_label)).props.dim = true;
        const std::vector<std::string> lines = text::wrap(code_, static_cast<size_t>(width));
        ui::Node& body = root.add_text("tape/code", visible_code(lines, rows, scroll_));
        body.props.width = width;
        body.props.height = rows;
        body.props.lines = rows;
        body.props.overflow = ui::Overflow::wrap;
        ui::Node& gap = root.add_spacer("tape/gap_status");
        gap.props.height = 1;
        root.add_text("tape/status", scroll_text(lang, lines, rows, scroll_)).props.dim = true;
    }

    if (result_ != Result::none) {
        Msg id = Msg::tape_no_save;
        switch (result_) {
            case Result::ok: id = Msg::tape_ok; break;
            case Result::invalid: id = Msg::tape_invalid; break;
            case Result::no_save: id = Msg::tape_no_save; break;
            case Result::copied: id = Msg::tape_copied; break;
            case Result::clipboard_empty: id = Msg::tape_clipboard_empty; break;
            case Result::clipboard_invalid: id = Msg::tape_clipboard_invalid; break;
            case Result::none: break;
        }
        root.add_text("tape/result", tr(lang, id)).props.accent = true;
    }
}

} // namespace phos::tape

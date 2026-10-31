#include "shell/save_view.hpp"

#include "core/text.hpp"
#include "shell/layout.hpp"

#include <algorithm>

namespace phos::save {

namespace {

std::string row_text(const Entry& entry) {
    // 槽位/大小/时间都是数据：时间由 App 格式化好，界面只拼接
    std::string slot = entry.slot == 0 ? std::string("s0") : "s" + std::to_string(entry.slot);
    std::string size;
    if (entry.bytes >= 1024)
        size = std::to_string(entry.bytes / 1024) + " KB";
    else
        size = std::to_string(entry.bytes) + " B";
    std::string text = entry.cart_id + "  " + slot + "  " + size;
    if (!entry.modified.empty()) text += "  " + entry.modified;
    return text;
}

} // namespace

std::string ScreenState::row_id(int index) {
    return "saves/row/" + std::to_string(index);
}

void ScreenState::open() {
    selected_ = 0;
    confirm_ = false;
}

void ScreenState::set_entries(std::vector<Entry> entries) {
    entries_ = std::move(entries);
    if (selected_ >= static_cast<int>(entries_.size()))
        selected_ = entries_.empty() ? 0 : static_cast<int>(entries_.size()) - 1;
}

void ScreenState::select(int index) {
    if (index >= 0 && index < static_cast<int>(entries_.size())) selected_ = index;
}

const Entry* ScreenState::selected_entry() const {
    if (selected_ < 0 || selected_ >= static_cast<int>(entries_.size())) return nullptr;
    return &entries_[static_cast<std::size_t>(selected_)];
}

void ScreenState::build(ui::Node& root, const ui::Rect& content, Lang lang) const {
    const bool en = lang == Lang::en;
    root.props.padding = ui::Insets{ShellLayout::kMarginX + 2, ShellLayout::kContentTop,
                                    ShellLayout::kMarginX + 2, 0};

    if (confirm_) {
        // 二次确认：文案明确"不可撤销"，默认焦点在 CANCEL（组件按树序取第一个可选项，
        // 所以 CANCEL 放前面；删除是危险操作，不该一按 Enter 就落刀）
        root.add_text("saves/confirm_hint",
                      en ? "DELETE THIS SAVE FILE? THIS CANNOT BE UNDONE."
                         : "确定删除这个存档文件？此操作不可撤销。")
            .props.danger = true;
        ui::Node& gap = root.add_spacer("saves/confirm_gap");
        gap.props.height = 1;
        root.add_button(kCancelId, en ? "CANCEL" : "取消");
        root.add_button(kConfirmId, en ? "YES, DELETE" : "确认删除");
        return;
    }

    if (entries_.empty()) {
        root.add_text("saves/empty", en ? "NO SAVE FILES" : "没有存档文件").props.dim = true;
        ui::Node& gap = root.add_spacer("saves/empty_gap");
        gap.props.height = 1;
        root.add_button(kBackId, en ? "BACK" : "返回");
        return;
    }

    root.add_text("saves/hint", en ? "ENTER = VIEW TAPE CODE" : "Enter 查看导出码")
        .props.dim = true;
    // 存档一多就会溢出：列表放进滚动视口，焦点仍由 Frame 自动跟随；
    // 高度留出提示行 + 两个按钮 + 间距，避免把按钮挤出屏
    const int list_height = std::max(1, content.h - 8);
    ui::Node& list = root.add_scroll("saves/list", list_height);
    list.props.gap = 0;
    for (int i = 0; i < static_cast<int>(entries_.size()); ++i)
        list.add_option(row_id(i), row_text(entries_[static_cast<std::size_t>(i)]));
    ui::Node& gap = root.add_spacer("saves/gap");
    gap.props.height = 1;
    root.add_button(kDeleteId, en ? "DELETE SELECTED" : "删除选中存档");
    root.add_button(kBackId, en ? "BACK" : "返回");
}

} // namespace phos::save

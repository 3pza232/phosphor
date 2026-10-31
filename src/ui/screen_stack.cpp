#include "ui/screen_stack.hpp"

namespace phos::ui {

ScreenStack::ScreenStack(std::string root_id) { push(std::move(root_id)); }

void ScreenStack::push(std::string id, bool modal) {
    entries_.push_back(Entry{std::move(id), modal});
    // 回调拿一份拷贝：回调里 reset/clear 会让 entries_ 里的 id 析构，引用会悬空
    if (on_enter_) {
        const std::string entered = entries_.back().id;
        on_enter_(entered);
    }
}

bool ScreenStack::pop() {
    if (entries_.empty()) return false;
    const std::string id = std::move(entries_.back().id);
    entries_.pop_back();
    if (on_exit_) on_exit_(id);
    return true;
}

void ScreenStack::clear() {
    while (!entries_.empty()) pop();
}

void ScreenStack::reset(std::string root_id, bool modal) {
    clear();
    push(std::move(root_id), modal);
}

const std::string& ScreenStack::top() const {
    static const std::string kEmpty;
    return entries_.empty() ? kEmpty : entries_.back().id;
}

bool ScreenStack::top_modal() const { return !entries_.empty() && entries_.back().modal; }

} // namespace phos::ui

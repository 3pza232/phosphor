#pragma once

#include "core/ui.hpp"
#include "shell/layout.hpp"
#include "shell/messages.hpp"
#include "ui/element.hpp"

#include <algorithm>
#include <array>
#include <cctype>
#include <map>
#include <string>
#include <utility>
#include <vector>

namespace phos::controls {

/// 可重绑的十个动作（虚拟键名，也是卡带读取的名字）
inline constexpr std::array<const char*, 10> kActions{{
    "left", "right", "up", "down", "a", "b", "x", "y", "start", "select",
}};

inline constexpr const char* kScreenId = "shell.controls";  // ui::Frame 的屏 id
inline constexpr const char* kBackId = "controls/back";
inline constexpr const char* kCancelId = "controls/cancel_capture";

/// 动作行 id 前缀："controls/row/<下标>"
inline std::string row_id(int index) { return "controls/row/" + std::to_string(index); }

/// 某动作当前生效的**物理键**：显式映射到它的物理键；若动作同名物理键没被绑到别处，
/// 再加默认恒等键（于是"没重绑"显示为 { left }）；全被改绑时返回空表。
inline std::vector<std::string> physical_for(
    const std::map<std::string, std::string>& bindings, const std::string& action) {
    std::vector<std::string> keys;
    for (const auto& [physical, virtual_key] : bindings)
        if (virtual_key == action) keys.push_back(physical);
    // 动作同名的物理键仍走默认恒等映射时也要显示出来（没被改绑到别的动作）
    if (bindings.find(action) == bindings.end()) keys.push_back(action);
    std::sort(keys.begin(), keys.end());
    keys.erase(std::unique(keys.begin(), keys.end()), keys.end());
    return keys;
}

/// Controls 屏（settings 栈上的普通浮层）：动作列表 + 捕获下一个物理键的状态。
/// 只做视图与映射数据；真实按键捕获/落盘由 App 注入（Window 层转换）。
/// 实现放在头内：纯逻辑的视图/捕获状态可被单测直接包含。
class ScreenState {
public:
    void open();
    void set_bindings(std::map<std::string, std::string> bindings);
    const std::map<std::string, std::string>& bindings() const { return bindings_; }

    void select(int index);
    int selected() const { return selected_; }
    const char* selected_action() const;

    void begin_capture() {
        capturing_ = true;
        status_.clear();
    }
    void cancel_capture() { capturing_ = false; }
    bool capturing() const { return capturing_; }

    /// 捕获成功：物理键绑到当前选中动作。返回被覆盖的原动作（空 = 无冲突）。
    /// 物理键名 == 动作名时删除显式映射（回退恒等映射），让配置文件保持干净。
    std::string apply_capture(const std::string& physical);

    void set_status(std::string status) { status_ = std::move(status); }
    const std::string& status() const { return status_; }

    /// 声明本屏元素树：动作列表 / 捕获提示 / 冲突提示
    void build(ui::Node& root, const ui::Rect& content, Lang lang) const;

private:
    std::map<std::string, std::string> bindings_;
    int selected_ = 0;
    bool capturing_ = false;
    std::string status_;
};

inline void ScreenState::open() {
    selected_ = 0;
    capturing_ = false;
    status_.clear();
}

inline void ScreenState::set_bindings(std::map<std::string, std::string> bindings) {
    bindings_ = std::move(bindings);
    if (selected_ >= static_cast<int>(kActions.size()))
        selected_ = static_cast<int>(kActions.size()) - 1;
}

inline void ScreenState::select(int index) {
    if (index >= 0 && index < static_cast<int>(kActions.size())) selected_ = index;
}

inline const char* ScreenState::selected_action() const {
    return kActions[static_cast<std::size_t>(selected_)];
}

inline std::string ScreenState::apply_capture(const std::string& physical) {
    if (!capturing_ || physical.empty()) return {};
    const std::string action = selected_action();
    std::string replaced;
    const auto it = bindings_.find(physical);
    if (it != bindings_.end() && it->second != action) replaced = it->second;

    if (physical == action) {
        bindings_.erase(physical);  // 恒等映射：不写冗余条目
    } else {
        bindings_[physical] = action;  // 同一物理键已绑别的动作：覆盖（返回 replaced 供提示）
    }
    capturing_ = false;
    return replaced;
}

namespace detail {
inline std::string row_text(const std::map<std::string, std::string>& bindings,
                            const std::string& action) {
    std::string text = action;
    for (char& ch : text) ch = static_cast<char>(toupper(static_cast<unsigned char>(ch)));
    text += "  < ";
    const std::vector<std::string> keys = physical_for(bindings, action);
    if (keys.empty()) text += "—";
    for (std::size_t i = 0; i < keys.size(); ++i) text += (i == 0 ? "" : ", ") + keys[i];
    text += " >";
    return text;
}
} // namespace detail

inline void ScreenState::build(ui::Node& root, const ui::Rect& content, Lang lang) const {
    const bool en = lang == Lang::en;
    root.props.padding = ui::Insets{ShellLayout::kMarginX + 2, ShellLayout::kContentTop,
                                    ShellLayout::kMarginX + 2, 0};

    if (capturing_) {
        root.add_text("controls/capture_hint",
                      (en ? "PRESS A KEY FOR " : "按下要绑定的物理键，目标动作：") +
                          std::string(selected_action()))
            .props.accent = true;
        root.add_text("controls/capture_cancel_hint", en ? "Esc = CANCEL" : "Esc = 取消")
            .props.dim = true;
        ui::Node& gap = root.add_spacer("controls/capture_gap");
        gap.props.height = 1;
        root.add_button(kCancelId, en ? "CANCEL" : "取消捕获");
        return;
    }

    root.add_text("controls/hint", en ? "ENTER = REBIND THIS ACTION" : "Enter = 重绑定该动作")
        .props.dim = true;
    for (int i = 0; i < static_cast<int>(kActions.size()); ++i)
        root.add_button(row_id(i), detail::row_text(bindings_, kActions[static_cast<std::size_t>(i)]));
    if (!status_.empty()) root.add_text("controls/status", status_).props.accent = true;
    ui::Node& gap = root.add_spacer("controls/gap");
    gap.props.height = 1;
    root.add_button(kBackId, en ? "BACK" : "返回");
}

} // namespace phos::controls

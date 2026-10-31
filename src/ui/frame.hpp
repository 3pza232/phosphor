#pragma once

#include "core/input.hpp"
#include "core/text_input.hpp"
#include "ui/element.hpp"
#include "ui/theme.hpp"

#include <map>
#include <memory>
#include <string>
#include <string_view>
#include <vector>

namespace phos {

class Screen;

namespace ui {

/// 单个控件的跨帧状态（其余种类无状态）。按元素 id 存放。
struct WidgetState {
    int cursor = 0;
    int scroll = 0;
    bool checked = false;
    std::unique_ptr<text::TextInput> input;
};

/// 一屏的跨帧状态：焦点 + 控件状态。屏与屏之间互不影响，切屏不会串状态。
struct ScreenState {
    std::string focus;
    std::map<std::string, WidgetState> widgets;
};

/// 全部屏的状态表。宿主持有一份，Frame 按 screen_id 定位本屏。
struct State {
    std::map<std::string, ScreenState> screens;
    ScreenState& screen(const std::string& id) { return screens[id]; }
    void forget(const std::string& id) { screens.erase(id); }
};

enum class EventKind {
    activated,  ///< 确认了一个可激活项（list/button）
    changed,    ///< 值被调整（option 的 delta / checkbox 的 flag）
    submitted,  ///< 文本域提交
    cancelled   ///< 取消键（由宿主决定退回哪一层）
};

struct Event {
    EventKind kind = EventKind::activated;
    std::string id;
    int index = -1;        ///< list：触发行下标
    int delta = 0;         ///< option：-1 / +1
    bool confirm = false;  ///< option：由确认键触发（否则是左右键）
    bool flag = false;     ///< checkbox：新状态
    std::string text;      ///< field：提交内容
};

/// 一组语义键。宿主界面与卡带界面用不同映射，控件代码只认语义。
struct Keys {
    std::vector<std::string> confirm;
    std::vector<std::string> cancel;
    std::string up = "up";
    std::string down = "down";
    std::string left = "left";
    std::string right = "right";

    static Keys host();  ///< 主机界面：Enter 确认、Esc 取消（虚拟手柄键不参与）
    static Keys pad();   ///< 卡带：A 确认、B 取消
};

/// 一帧界面：构造元素树 → run() 排布并处理输入 → paint() 画到网格。
/// 元素树每帧重建，跨帧状态只有焦点与控件值（存在 State 里）。
class Frame {
public:
    /// input 为空 = 只排布/绘制，不处理输入（宿主 update 与 draw 分离时，draw 走这条）。
    Frame(std::string screen_id, State& state, const Theme& theme, Rect area,
          const Input* input, Keys keys = Keys::host());

    Node& root() { return root_; }

    /// 测量 → 排布 → 焦点 → 输入。返回本帧事件（只在本帧有效）。
    std::vector<Event> run();

    /// 按本帧布局绘制到网格。
    void paint(Screen& screen) const;

    bool ime_requested() const { return ime_requested_; }
    const std::string& focused_id() const { return focused_id_; }

    bool checked(std::string_view id) const;
    void set_checked(std::string_view id, bool value);
    const std::string& field_text(std::string_view id) const;
    void set_field_text(std::string_view id, std::string value);

private:
    WidgetState& widget(std::string_view id);
    const WidgetState* find_widget(std::string_view id) const;
    void handle_focus_nav(std::vector<Node*>& focusables, std::vector<Event>& events,
                          bool up, bool down, bool left, bool right, bool confirm, bool cancel);

    std::string screen_id_;
    State& state_;
    const Theme& theme_;
    Rect area_;
    const Input* input_;
    Keys keys_;
    Node root_;
    std::string focused_id_;
    bool ime_requested_ = false;
    mutable std::string scratch_text_;  ///< field_text 的只读回退值
};

} // namespace ui
} // namespace phos
#pragma once

#include "core/color.hpp"
#include "core/ui.hpp"

#include <string>
#include <vector>

namespace phos {

class Screen;

namespace ui {

struct Theme;

/// 瞬时提示（toast）：底边居中浮一条消息，几秒后自动消失。
///
/// 与场景/模态不同，它**不接管输入**、不冻结世界，只借用画面底部几行；
/// 计时由宿主每帧推进（UI 层不持有全局时钟），因此单测可以精确控制帧数。
class Toasts {
public:
    void push(std::string text, float seconds = 1.6f);
    /// 推进计时并丢掉过期项。dt <= 0 不推进（暂停帧）。
    void update(float dt);
    void clear();
    bool empty() const { return entries_.empty(); }
    size_t size() const { return entries_.size(); }

    /// 画最新一条：底边居中的不透明小窗，不遮住游戏主体。
    void paint(Screen& screen, const Theme& theme, Rect area) const;

private:
    struct Entry {
        std::string text;
        float ttl = 0.f;
    };
    std::vector<Entry> entries_;
};

} // namespace ui
} // namespace phos
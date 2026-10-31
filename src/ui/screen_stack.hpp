#pragma once

#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace phos::ui {

/// 通用屏幕栈：给界面层表达"上一屏"的返回关系（外壳浮层、卡带浮窗都可复用）。
///
/// 纯数据结构，不依赖 shell/app：
///   - 每屏是任意字符串 id（ShellMode 名、场景名…）；
///   - push/pop/top/depth/clear，push 时可标 modal（只做标记，不吞输入——输入策略归调用方）；
///   - 可选 on_enter/on_exit 回调：push 后、pop/clear 每个条目出栈时各回调一次，便于
///     "进屏初始化、出屏清理"；回调只收到 id，不触碰栈状态，避免回调里重入改栈。
///
/// 栈不强制非空：pop 空栈返回 false。调用方若需要"永久根屏"，自行保证（Shell 用
/// reset(root) 把 boot/shelf/paused 这类根屏重置进栈，而不是当作 push 叠加）。
class ScreenStack {
public:
    using Callback = std::function<void(const std::string&)>;

    ScreenStack() = default;
    explicit ScreenStack(std::string root_id);

    /// 入栈并回调 on_enter(id)。modal 只记录在栈顶条目上，供 top_modal() 查询。
    void push(std::string id, bool modal = false);
    /// 出栈并回调 on_exit(id)；空栈返回 false（不回调）。
    bool pop();
    /// 清空所有屏：从栈顶向下逐个回调 on_exit；随后栈为空。
    void clear();
    /// 清空后压入一个根屏（boot/shelf/paused 这类"重置到某一屏"的语义）。
    void reset(std::string root_id, bool modal = false);

    /// 栈顶 id；空栈返回空串（静态对象，引用始终有效）。
    const std::string& top() const;
    bool empty() const { return entries_.empty(); }
    int depth() const { return static_cast<int>(entries_.size()); }
    bool top_modal() const;

    void set_on_enter(Callback callback) { on_enter_ = std::move(callback); }
    void set_on_exit(Callback callback) { on_exit_ = std::move(callback); }

private:
    struct Entry {
        std::string id;
        bool modal = false;
    };
    std::vector<Entry> entries_;
    Callback on_enter_;
    Callback on_exit_;
};

} // namespace phos::ui

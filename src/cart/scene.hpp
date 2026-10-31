#pragma once

#include "core/defaults.hpp"

#include <sol/sol.hpp>

#include <string>
#include <vector>

namespace phos {

/// 一个场景 = 卡带压入栈的"一层界面/模态"：可选 update/draw 与进入/退出回调。
///
/// 引擎负责的只有三件事：**推进顺序**（栈顶先收到 update）、**绘制顺序**（底 → 顶）、
/// **世界是否暂停**（栈顶声明 pause_world 时跳过卡带 update）。输入怎么解释仍归卡带
/// ——场景的 draw 里通常调用 phos.ui.render，update 里读事件/按键。
struct SceneEntry {
    std::string id;
    bool modal = false;        ///< 语义标记：压在下面的场景不该再响应输入（卡带自判）
    bool pause_world = false;  ///< 栈顶为真时，引擎跳过卡带 update（世界冻结）
    bool audio_pause = false;  ///< 栈上存在时为真时，引擎暂停音频（出栈后恢复）
    sol::protected_function update;
    sol::protected_function draw;
    sol::protected_function on_enter;
    sol::protected_function on_exit;
};

/// 卡带场景栈：随卡带生命周期（Cartridge 持有），不跨卡带。
class SceneStack {
public:
    /// 栈深上限：每层都是一次脚本调用 + 一次绘制，深栈没有正当用途
    static constexpr size_t kMaxDepth = 8;

    /// 压栈并执行 on_enter()。失败（回调报错）时栈不变。
    bool push(SceneEntry entry, std::string& err);
    /// 弹栈并执行 on_exit(result)；result 可为 nil。失败时仍然出栈（避免卡在坏场景里）。
    bool pop(sol::object result, std::string& err);
    /// 清空（不执行回调：宿主正在拆卡带，宿主不会为脚本的退出钩子兜底）
    void clear() { scenes_.clear(); }

    SceneEntry* top();
    const SceneEntry* top() const;
    /// 底 → 顶的只读清单（观测用：agent 的 state.query.scenes）
    const std::vector<SceneEntry>& entries() const { return scenes_; }
    size_t depth() const { return scenes_.size(); }
    /// 栈上是否有声明 pause_world 的场景（不只是栈顶：压着菜单时世界就该停）
    bool pause_world() const;
    bool wants_audio_pause() const;

    /// 只推进栈顶场景；没有 update 时什么也不做
    bool update(float dt, std::string& err);
    /// 从底到顶依次绘制（每层自己决定画什么、画在哪）
    bool draw(std::string& err);

private:
    /// 脚本回调里可能 push/pop（例如暂停菜单的 on_exit 又开新场景）。回调执行期间
    /// 直接改栈会让"正在调用的那层"被销毁，因此操作先排队、回调返回后再落地。
    struct Pending {
        bool push = false;
        SceneEntry entry;
        sol::object result;
        bool has_result = false;
    };
    void drain(std::string& err);

    std::vector<SceneEntry> scenes_;
    std::vector<Pending> pending_;
    int busy_ = 0;  ///< >0 = 正在执行脚本回调（此时只排队，不动栈）
};

} // namespace phos
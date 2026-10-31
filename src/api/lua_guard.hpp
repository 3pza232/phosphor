#pragma once

#include <chrono>

struct lua_State;

namespace phos::lua_guard {

/// 单次脚本调用的墙钟预算（毫秒）。超过即抛一个普通 Lua 错误，走既有的
/// "脚本出错 → 安全停止"通道。它是**每次进入脚本**的预算（init / update / draw /
/// require / manifest / 内容包脚本各算一次），不是每帧预算。
inline constexpr int kDefaultBudgetMs = 100;

/// 每多少条 VM 指令查一次时钟（≈0.1 ms；相对 Lua 解释器开销可忽略）
inline constexpr int kHookStep = 20000;

/// 给一个 lua_State 装指令计数钩子。幂等：同一个 state 只需装一次。
/// 未装钩子的 state 上使用 BudgetScope 不会崩，但也没有预算（只对主线程生效）。
void attach(lua_State* state);

/// RAII 预算：进入脚本前构造、离开时恢复外层预算。可嵌套，嵌套时取**更紧**的那个，
/// 于是"卡带 update → require 子模块"不会因为内层放宽预算而突破外层承诺。
class BudgetScope {
public:
    explicit BudgetScope(int budget_ms = kDefaultBudgetMs);
    ~BudgetScope();
    BudgetScope(const BudgetScope&) = delete;
    BudgetScope& operator=(const BudgetScope&) = delete;

private:
    int outer_depth_ = 0;
    int outer_budget_ms_ = 0;
    std::chrono::steady_clock::time_point outer_deadline_{};
};

/// 把沙箱里的 print 重定向到主机日志（tag 为前缀，例如 "cart" / "pack"）。
/// 卡带的 stdout 属于机器可读输出（--dump-screen / dump-every），不能被其内容污染。
void redirect_print(lua_State* state, const char* tag);

} // namespace phos::lua_guard
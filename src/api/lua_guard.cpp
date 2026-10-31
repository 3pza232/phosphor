// Lua 是 C 库：必须按 C 链接方式声明，否则符号名字被 C++ 修饰、链接期全部找不到
extern "C" {
#include <lauxlib.h>
#include <lua.h>
}

#include "api/lua_guard.hpp"

#include "core/log.hpp"

#include <chrono>
#include <string>

namespace phos::lua_guard {

namespace {

// 脚本只在主线程执行：预算用线程局部量，不为单线程路径引入锁。
// depth > 0 = 正处在一次受预算保护的脚本调用里。
thread_local int t_depth = 0;
thread_local int t_budget_ms = 0;
thread_local std::chrono::steady_clock::time_point t_deadline{};

void budget_hook(lua_State* state, lua_Debug*) {
    if (t_depth == 0) return;
    if (std::chrono::steady_clock::now() < t_deadline) return;
    luaL_error(state, "script exceeded %d ms in one call (watchdog)", t_budget_ms);
}

int log_print(lua_State* state) {
    const char* tag = static_cast<const char*>(lua_touserdata(state, lua_upvalueindex(1)));
    std::string line;
    const int count = lua_gettop(state);
    for (int i = 1; i <= count; ++i) {
        size_t length = 0;
        const char* text = luaL_tolstring(state, i, &length);
        if (i > 1) line += '\t';
        line.append(text ? text : "", text ? length : 0);
        lua_pop(state, 1);
    }
    log::info(std::string("[") + (tag ? tag : "script") + "] " + line);
    return 0;
}

} // namespace

void attach(lua_State* state) {
    if (state) lua_sethook(state, budget_hook, LUA_MASKCOUNT, kHookStep);
}

BudgetScope::BudgetScope(int budget_ms)
    : outer_depth_(t_depth), outer_budget_ms_(t_budget_ms), outer_deadline_(t_deadline) {
    const int budget = budget_ms > 0 ? budget_ms : kDefaultBudgetMs;
    auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(budget);
    int effective = budget;
    if (outer_depth_ > 0) {
        // 嵌套：不放松外层的承诺
        if (outer_deadline_ < deadline) deadline = outer_deadline_;
        if (outer_budget_ms_ < effective) effective = outer_budget_ms_;
    }
    t_deadline = deadline;
    t_budget_ms = effective;
    ++t_depth;
}

BudgetScope::~BudgetScope() {
    t_depth = outer_depth_;
    t_budget_ms = outer_budget_ms_;
    t_deadline = outer_deadline_;
}

void redirect_print(lua_State* state, const char* tag) {
    if (!state) return;
    lua_pushlightuserdata(state, const_cast<char*>(tag ? tag : "script"));
    lua_pushcclosure(state, log_print, 1);
    lua_setglobal(state, "print");
}

} // namespace phos::lua_guard
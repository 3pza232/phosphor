#include "api/lua_sandbox.hpp"

#include "api/lua_guard.hpp"

namespace phos::lua_sandbox {

namespace {

/// 摘掉 base 自带的文件与动态加载入口：沙箱里的脚本没有 IO 能力，也不在这里拼二进制块。
/// loadstring 是 Lua 5.1 的名字，5.4 已无——写出来是为了让"二进制块也禁"的意图留在代码里
void strip_file_and_load(sol::state& lua) {
    lua["dofile"] = sol::nil;
    lua["loadfile"] = sol::nil;
    lua["load"] = sol::nil;
    lua["loadstring"] = sol::nil;
}

} // namespace

void open(sol::state& lua, std::initializer_list<sol::lib> libraries, const char* print_tag) {
    // open_libraries 的可变参数版无法从 initializer_list 展开；逐个打开与一次打开等价
    // （每个库各自 requiref，互不依赖顺序）
    for (const sol::lib library : libraries) lua.open_libraries(library);
    strip_file_and_load(lua);
    // 钩子必须在任何脚本之前装好：入口脚本自己就可能死循环（预算由调用方的 BudgetScope 给）
    lua_guard::attach(lua.lua_state());
    if (print_tag != nullptr) lua_guard::redirect_print(lua.lua_state(), print_tag);
}

Localized read_localized(const sol::object& value) {
    Localized out;
    if (value.is<std::string>()) {
        out.zh = out.en = value.as<std::string>();
        return out;
    }
    if (!value.is<sol::table>()) return out;

    sol::table map = value.as<sol::table>();
    sol::object zh = map["zh"];
    sol::object en = map["en"];
    if (zh.is<std::string>()) out.zh = zh.as<std::string>();
    if (en.is<std::string>()) out.en = en.as<std::string>();
    // 只写一种语言时互补：先 zh←en、再 en←zh，于是两边要么同值、要么同空
    if (out.zh.empty()) out.zh = out.en;
    if (out.en.empty()) out.en = out.zh;
    return out;
}

Localized read_localized(const sol::table& table, const char* key) {
    // 轻量引用拷贝：在非 const 表上取下标是 sol2 里最稳的写法（与 api/lua_value 的读法一致）
    sol::table map = table;
    sol::object value = map[key];
    return read_localized(value);
}

} // namespace phos::lua_sandbox

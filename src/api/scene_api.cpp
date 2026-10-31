#include "api/scene_api.hpp"

#include "api/host_api.hpp"
#include "cart/scene.hpp"
#include "core/log.hpp"

#include <sol/sol.hpp>

#include <string>

namespace phos {

namespace {

sol::protected_function function_field(const sol::table& t, const char* key) {
    sol::object value = t[key];
    if (value.is<sol::protected_function>()) return value.as<sol::protected_function>();
    if (value.is<sol::function>()) return value.as<sol::function>();
    return sol::protected_function();
}

bool bool_field(const sol::table& t, const char* key, bool fallback = false) {
    sol::object value = t[key];
    return value.is<bool>() ? value.as<bool>() : fallback;
}

} // namespace

void register_scene_api(sol::state& lua, HostContext& host) {
    sol::table phos = lua["phos"];
    sol::table scene = phos.create_named("scene");
    lua_State* state = lua.lua_state();  // 闭包只捕获裸 state：sol 表对象不能跨调用活到注册函数之外

    /// 压入一层场景。spec 字段：
    ///   id（缺省 "scene"）/ modal / pause_world / audio_pause（bool）
    ///   update(dt) / draw() / on_enter() / on_exit(result)（函数，均可省略）
    /// 返回 true；栈满或 on_enter 报错返回 false, err。
    scene["push"] = [&host](sol::table spec) -> std::tuple<bool, std::string> {
        if (!host.scenes) return {false, "no cart loaded"};
        SceneEntry entry;
        sol::object id = spec["id"];
        entry.id = id.is<std::string>() ? id.as<std::string>() : std::string("scene");
        entry.modal = bool_field(spec, "modal");
        entry.pause_world = bool_field(spec, "pause_world");
        entry.audio_pause = bool_field(spec, "audio_pause");
        entry.update = function_field(spec, "update");
        entry.draw = function_field(spec, "draw");
        entry.on_enter = function_field(spec, "on_enter");
        entry.on_exit = function_field(spec, "on_exit");
        std::string err;
        if (!host.scenes->push(std::move(entry), err)) return {false, err};
        return {true, std::string()};
    };

    /// 弹出栈顶并执行 on_exit(result)。空栈返回 false。
    scene["pop"] = [&host](sol::optional<sol::object> result) -> std::tuple<bool, std::string> {
        if (!host.scenes) return {false, "no cart loaded"};
        std::string err;
        const bool ok = host.scenes->pop(result.value_or(sol::nil), err);
        return {ok, ok ? std::string() : err};
    };

    scene["clear"] = [&host]() {
        if (host.scenes) host.scenes->clear();
    };

    /// 栈顶场景 id；空栈返回 nil
    scene["top"] = [&host, state]() -> sol::object {
        if (!host.scenes || !host.scenes->top()) return sol::nil;
        return sol::make_object(state, host.scenes->top()->id);
    };

    scene["depth"] = [&host]() { return host.scenes ? host.scenes->depth() : size_t(0); };

    /// 栈上是否有场景要求冻结世界 / 暂停音频（卡带可据此决定是否处理输入）
    scene["pause_world"] = [&host]() {
        return host.scenes != nullptr && host.scenes->pause_world();
    };
    scene["audio_pause"] = [&host]() {
        return host.scenes != nullptr && host.scenes->wants_audio_pause();
    };
    /// 栈上是否有声明 modal 的场景（在它之上时，下层应停止响应输入）
    scene["modal"] = [&host]() {
        if (!host.scenes || !host.scenes->top()) return false;
        return host.scenes->top()->modal;
    };
}

} // namespace phos
#include "cart/cartridge.hpp"

#include "api/inspect.hpp"
#include "api/lua_value.hpp"
#include "core/defaults.hpp"
#include "core/log.hpp"
#include "core/version.hpp"

#include <algorithm>
#include <chrono>

namespace phos {

namespace {

/// 卡带执行看门狗：防止 `while true do end` 这类失控把整机一起拖死。
/// 给卡带的 Lua 状态挂指令计数钩子，布防后再进卡带代码，超时就抛一个普通 Lua 错误——
/// 于是失控走的是既有的"卡带出错 → 安全拔卡 + 错误屏"通道
constexpr int kWatchdogStep = 20000;   // 每多少条 VM 指令查一次时钟（≈0.1ms，开销可忽略）
constexpr int kWatchdogLimitMs = 100;  // 单次卡带调用的墙钟上限

std::chrono::steady_clock::time_point g_watchdog_deadline;
bool g_watchdog_armed = false;

void watchdog_hook(lua_State* state, lua_Debug*) {
    if (!g_watchdog_armed) return;
    if (std::chrono::steady_clock::now() < g_watchdog_deadline) return;
    luaL_error(state, "cart exceeded %d ms in one call (watchdog)", kWatchdogLimitMs);
}

/// 布防/撤防成对出现，且**可嵌套**：内层结束会恢复外层的布防状态，
/// 于是"入口脚本加载 → init → 模块 require"这种层层进入不会互相撤防。
struct WatchdogScope {
    bool outer_armed_ = g_watchdog_armed;
    std::chrono::steady_clock::time_point outer_deadline_ = g_watchdog_deadline;

    WatchdogScope() {
        g_watchdog_deadline =
            std::chrono::steady_clock::now() + std::chrono::milliseconds(kWatchdogLimitMs);
        g_watchdog_armed = true;
    }
    ~WatchdogScope() {
        g_watchdog_armed = outer_armed_;
        g_watchdog_deadline = outer_deadline_;
    }
};

/// 卡带 id 的合法形状：小写字母/数字/连字符，1..64。
/// id 会拼进存档路径（saves/<id>.sav）与 <id>.phos —— 放任 ".." / ":" / 绝对路径就能
/// 越出存档目录、甚至覆盖其它卡带的存档。主机端**强制校验**，不依赖卡带自觉
bool valid_cart_id(const std::string& id) {
    if (id.empty() || id.size() > 64) return false;
    for (char c : id)
        if (!((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-')) return false;
    return true;
}

} // namespace

CartInfo parse_manifest(const std::string& manifest_text, const std::string& cart_path) {
    CartInfo info;
    info.path = cart_path;

    sol::state lua;
    lua.open_libraries(sol::lib::base, sol::lib::string, sol::lib::table);
    // manifest 也是不可信输入（而且每次扫描卡带目录都会执行）：base 自带的文件/加载
    // 函数一律摘掉，兑现 cart-format.md 的"无 IO 能力"
    lua["dofile"] = sol::nil;
    lua["loadfile"] = sol::nil;
    lua["load"] = sol::nil;

    auto result = lua.safe_script(manifest_text, &sol::script_pass_on_error);
    if (!result.valid()) {
        sol::error err = result;
        info.error = std::string("manifest.lua syntax error: ") + err.what();
        return info;
    }
    sol::object ret = result;
    if (!ret.is<sol::table>()) {
        info.error = "manifest.lua must return a table";
        return info;
    }
    sol::table t = ret.as<sol::table>();

    auto get_str = [&t](const char* key) -> std::string {
        sol::object v = t[key];
        return v.is<std::string>() ? v.as<std::string>() : std::string();
    };
    /// desc 两种写法都认：字符串（中英同文）或 { zh = …, en = … }
    auto get_localized = [&t](const char* key) -> Localized {
        Localized out;
        sol::object v = t[key];
        if (v.is<std::string>()) {
            out.zh = v.as<std::string>();
            return out;
        }
        if (v.is<sol::table>()) {
            sol::table map = v.as<sol::table>();
            sol::object zh = map["zh"];
            sol::object en = map["en"];
            if (zh.is<std::string>()) out.zh = zh.as<std::string>();
            if (en.is<std::string>()) out.en = en.as<std::string>();
            if (out.zh.empty()) out.zh = out.en;  // 只写了 en 也不至于空着
        }
        return out;
    };

    info.id = get_str("id");
    info.name = get_str("name");
    info.author = get_str("author");
    info.version = get_str("version");
    info.desc = get_localized("desc");

    info.entry = get_str("entry");

    if (info.id.empty()) info.error = "manifest missing required field: id";
    else if (!valid_cart_id(info.id))
        info.error = "manifest id must match [a-z0-9-]{1,64}: " + info.id;
    else if (info.entry.empty()) info.error = "manifest missing required field: entry";
    else info.error.clear();

    // API 世代：高于主机支持的版本直接拒绝，避免运行到一半才撞上缺失接口
    sol::object api = t["phos_api"];
    if (api.is<double>() || api.is<int>()) {
        const int requested = api.as<int>();
        if (requested > kPhosApiVersion)
            info.error = "cart needs phos API v" + std::to_string(requested) + " (host supports v" +
                         std::to_string(kPhosApiVersion) + ")";
    }

    sol::object sidebar = t["sidebar"];
    if (sidebar.is<sol::table>()) {
        sol::object w = sidebar.as<sol::table>()["w"];
        if (w.is<double>() || w.is<int>()) {
            info.sidebar_w = clamp_panel_w(w.as<int>());
        }
    }

    sol::object save = t["save"];
    if (save.is<bool>()) info.wants_save = save.as<bool>();

    // 像素图标：icon = { "...", "..." }，icon_colors = { ["#"] = {r,g,b} }
    sol::object icon = t["icon"];
    if (icon.is<sol::table>()) {
        sol::table rows = icon.as<sol::table>();
        for (size_t i = 1; i <= rows.size(); ++i) {
            sol::object v = rows[i];
            if (v.is<std::string>()) info.icon_rows.push_back(v.as<std::string>());
        }
    }
    // 与卡带精灵共用同一份"字符画取色"读取（api::read_char_color_map）：
    // 同一个 icon_colors 表在卡带架与卡带里必须解释成同一组颜色
    info.icon_colors = api::read_char_color_map(t["icon_colors"]);
    return info;
}

bool Cartridge::load(const std::string& cart_path, HostContext& host) {
    // 先摘掉上一张卡带的存档指针：下面几条早退路径不会再碰它，而调用方可能已经
    // 销毁了那个 Cartridge（成员 save_ 随之消失），留着就是悬垂指针
    host.save = nullptr;
    files_ = CartFiles::open(cart_path);
    if (!files_.valid()) {
        error_ = "cart path not found: " + cart_path;
        return false;
    }

    auto manifest_text = files_.read("manifest.lua");
    if (!manifest_text) {
        error_ = "cart missing manifest.lua";
        return false;
    }
    info_ = parse_manifest(*manifest_text, cart_path);
    if (!info_.error.empty()) {
        error_ = info_.error;
        return false;
    }

    // 存档：声明 save = true 的卡带获得私有存档空间
    if (info_.wants_save) {
        save_.open(host.save_dir, info_.id);
        host.save = &save_;
    } else {
        host.save = nullptr;
    }

    // 面板宽度必须在卡带脚本运行**之前**就位：卡带的 init() 里往往会立刻用
    // phos.panel.size() 或 phos.ui.region(..., { surface = "panel" }) 排版，
    // 那时若还是 0，卡带量到的面板尺寸就是错的——宽度是随包走的布局事实
    host.panel_w = info_.sidebar_w;
    return assemble(info_.entry, host);
}

bool Cartridge::load_entry(const std::string& pack_dir, const std::string& entry,
                           HostContext& host) {
    files_ = CartFiles::open(pack_dir);
    if (!files_.valid()) {
        error_ = "pack path not found: " + pack_dir;
        return false;
    }
    info_.id = "host-script";
    info_.name = entry;
    host.save = nullptr;  // 主机脚本不参与存档
    return assemble(entry, host);
}

bool Cartridge::assemble(const std::string& entry, HostContext& host) {
    host.cart_files = &files_;  // 包内资源（音频等）对本卡带开放
    host.cart_info = &info_;    // 身份也要在脚本之前就位：init() 里往往就要用（phos.cart）

    auto entry_src = files_.read(entry);
    if (!entry_src) {
        error_ = "entry script not found: " + entry;
        return false;
    }

    // --- 装配沙箱：白名单库 + phos.* API ---
    lua_.open_libraries(sol::lib::base, sol::lib::math, sol::lib::string,
                        sol::lib::table, sol::lib::utf8);
    // 文件与系统访问禁止（见 docs/cart-format.md 沙箱白名单）
    lua_["dofile"] = sol::nil;
    lua_["loadfile"] = sol::nil;
    lua_["load"] = sol::nil;
    lua_["loadstring"] = sol::nil;  // Lua 5.1 的名字；5.4 已无，留着写明"二进制块也禁"的意图

    // 卡带内模块加载：只允许读取本包内的 .lua，模块可拆分为多个文件
    lua_["require"] = [this](const std::string& name) { return load_module(name); };

    register_host_api(lua_, host);

    // 挂上指令计数钩子（是否布防由 WatchdogScope 决定）：入口脚本自己也可能死循环，
    // 所以加载期就布防——`require` 链同理
    lua_sethook(lua_.lua_state(), watchdog_hook, LUA_MASKCOUNT, kWatchdogStep);

    WatchdogScope entry_guard;
    auto loaded = lua_.safe_script(*entry_src, &sol::script_pass_on_error);
    if (!loaded.valid()) {
        sol::error err = loaded;
        error_ = std::string("entry script error: ") + err.what();
        return false;
    }

    auto grab = [this](const char* name) {
        sol::object fn = lua_[name];
        return fn.is<sol::protected_function>()
                   ? fn.as<sol::protected_function>()
                   : sol::protected_function();
    };
    init_fn_ = grab("init");
    update_fn_ = grab("update");
    draw_fn_ = grab("draw");

    if (init_fn_.valid())
        return call_guard("init", init_fn_);
    return true;
}

sol::object Cartridge::load_module(const std::string& name) {
    if (auto it = module_cache_.find(name); it != module_cache_.end()) return it->second;

    // 模块名 → 包内路径（"ui.panel" → "ui/panel.lua"）
    std::string path = name;
    std::replace(path.begin(), path.end(), '.', '/');

    auto source = files_.read(path + ".lua");
    if (!source) source = files_.read(path + "/init.lua");
    if (!source) {
        log::warn("[cart] module not found: " + name);
        return sol::nil;  // 返回 nil 让调用方自然报错，避免跨 C++ 帧长跳转
    }

    auto result = lua_.safe_script(*source, &sol::script_pass_on_error);
    if (!result.valid()) {
        sol::error err = result;
        log::warn("[cart] module error in " + name + ": " + std::string(err.what()));
        return sol::nil;
    }

    sol::object value = result;
    if (!value.valid() || value == sol::nil)
        value = sol::make_object(lua_.lua_state(), true);  // 无返回值视为加载成功
    module_cache_[name] = value;
    return value;
}

int Cartridge::lua_memory_kb() const {
    return lua_gc(lua_.lua_state(), LUA_GCCOUNT, 0);
}

bool Cartridge::call_guard(const char* phase, sol::protected_function& fn) {
    WatchdogScope guard;  // init / draw 等卡带入口都经这里
    auto result = fn();
    if (!result.valid()) {
        sol::error err = result;
        error_ = std::string("cart error in ") + phase + ": " + err.what();
        return false;
    }
    return true;
}

std::string Cartridge::debug_state_json() {
    sol::object candidate = lua_["debug_state"];
    if (!candidate.is<sol::function>()) return {};
    sol::protected_function call = candidate;
    WatchdogScope guard;  // 观测入口也执行卡带代码（死循环一样不该拖死主机）
    const sol::protected_function_result result = call();
    if (!result.valid()) return {};  // 观测失败不报错、不留痕
    // 深度 4：debug_state 常见的形状是"若干实体的若干字段"（表里套数组、数组里套表），
    // 深度 2 会把实体字段截成 {"__table":N}，agent 就看不到幽灵/敌人的位置了。
    // 递归带循环引用保护，给深一点是安全的
    return lua_value_to_json(result.get<sol::object>(), 4);
}

std::string Cartridge::global_json(const std::string& path) {
    if (path.empty()) return {};

    sol::object current = lua_.globals();
    size_t begin = 0;
    while (begin <= path.size()) {
        const size_t dot = path.find('.', begin);
        const std::string part =
            path.substr(begin, dot == std::string::npos ? std::string::npos : dot - begin);
        if (part.empty() || !current.is<sol::table>()) return {};
        current = current.as<sol::table>()[part];
        if (current == sol::nil) return {};
        if (dot == std::string::npos) break;
        begin = dot + 1;
    }
    return lua_value_to_json(current, 2);
}

void Cartridge::apply_palette(const Palette& palette) {
    apply_palette_to(lua_, palette);
}

bool Cartridge::update(float dt) {
    if (!update_fn_.valid()) return true;
    WatchdogScope guard;
    auto result = update_fn_(dt);
    if (!result.valid()) {
        sol::error err = result;
        error_ = std::string("cart error in update: ") + err.what();
        return false;
    }
    return true;
}

bool Cartridge::draw() {
    if (!draw_fn_.valid()) return true;
    return call_guard("draw", draw_fn_);
}

} // namespace phos

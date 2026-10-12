#pragma once

#include "api/host_api.hpp"
#include "cart/cart_files.hpp"
#include "cart/cart_info.hpp"
#include "cart/save_store.hpp"

#include <sol/sol.hpp>

#include <map>
#include <string>
#include <vector>

namespace phos {
class HostContext;
}

namespace phos {

/// 解析 manifest.lua 文本（沙箱执行，仅允许返回纯数据表）。
/// 失败时填充 info.error。
CartInfo parse_manifest(const std::string& manifest_text, const std::string& cart_path);

/// 一张已加载的卡带（或主机自带的 Lua 动画脚本，如皮肤的开机动画）：
/// 独立 Lua 沙箱 + 生命周期。主机永不因卡带而死：一切 Lua 错误被捕获。
class Cartridge {
public:
    /// 加载整张卡带（读取 manifest、校验、装配沙箱）并执行 init。
    bool load(const std::string& cart_path, HostContext& host);

    /// 加载包内任意入口脚本（用于 skin 的 boot.lua 等主机脚本，不要求 manifest）
    bool load_entry(const std::string& pack_dir, const std::string& entry, HostContext& host);

    /// 每逻辑帧调用。Lua 错误返回 false（此后卡带不可再用）。
    bool update(float dt);
    bool draw();

    const CartInfo& info() const { return info_; }
    const std::string& error() const { return error_; }
    int sidebar_width() const { return info_.sidebar_w; }

    /// 存档句柄：manifest 未声明 `save = true` 时返回 nullptr。
    /// 主机侧读存档（磁带码菜单）走这里，不必知道卡带内部怎么存
    SaveStore* save() { return info_.wants_save ? &save_ : nullptr; }

    /// Lua 堆占用（KB），供调试台观测
    int lua_memory_kb() const;

    /// agent 观测：卡带可选定义全局函数 `debug_state()`，返回其结果的 JSON 片段；
    /// 未定义或调用出错时返回空串（观测失败绝不影响主机与卡带）
    std::string debug_state_json();
    /// agent 观测：读取卡带 Lua 全局变量（点分路径，如 `score`、`cfg.level`）；
    /// 不存在或不可序列化时返回空串
    std::string global_json(const std::string& path);

    /// 色板热更新（切换主题时重写 phos.color 常量）
    void apply_palette(const Palette& palette);

private:
    bool assemble(const std::string& entry, HostContext& host);
    bool call_guard(const char* phase, sol::protected_function& fn);
    /// 卡带内模块加载：require("music") → music.lua 或 music/init.lua（带缓存）
    sol::object load_module(const std::string& name);

    sol::state lua_;
    std::map<std::string, sol::object> module_cache_;  // 声明在 lua_ 之后：先于 state 析构
    sol::protected_function init_fn_;
    sol::protected_function update_fn_;
    sol::protected_function draw_fn_;
    CartFiles files_;  // 持有包引用：卡带存活期间 API 可随时读取包内资源
    CartInfo info_;
    SaveStore save_;
    std::string error_;
};

} // namespace phos

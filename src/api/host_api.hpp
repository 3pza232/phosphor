#pragma once

#include "core/defaults.hpp"
#include "core/input.hpp"
#include "core/layered_screen.hpp"
#include "core/palette.hpp"
#include "core/screen.hpp"
#include "core/text.hpp"
#include "ui/frame.hpp"

#include <functional>
#include <map>
#include <memory>
#include <random>
#include <string>
#include <vector>

namespace sol { class state; }

namespace phos {

class Audio;
class SaveStore;
class SceneStack;
namespace ui {
class Toasts;
}
class CartFiles;
class Cartridge;
class Net;
struct CartInfo;

/// 主机运行时上下文：API 层与 App 之间的共享状态。
/// 由 App 持有并随帧更新，API 函数捕获其引用。
struct HostContext {
    Screen* screen = nullptr;
    Input* input = nullptr;
    const Palette* palette = nullptr;   // 当前主题声明的色板（phos.color 常量的来源）
    SaveStore* save = nullptr;          // 卡带存档（未声明 save 时为 nullptr）
    Audio* audio = nullptr;             // 音频子系统（可能为静音降级态）
    Net* net = nullptr;                 // 局域网联机（未接时为 nullptr，phos.net 安全空壳）
    const CartFiles* cart_files = nullptr;  // 当前卡带包（读取包内音频等资源）
    const CartInfo* cart_info = nullptr;    // 当前卡带的身份（来自 manifest.lua；见 phos.cart）
    /// 卡带侧声明式界面（phos.ui.render）的跨帧状态：焦点/滚动/勾选/文本域。
    /// 随卡带生命周期重建，不同卡带之间不串状态
    ui::State cart_ui;
    /// 最近一次 phos.ui.render 的焦点与屏 id（供 phos.ui.focus / checked / field_text 查询）
    std::string last_ui_focus;
    std::string last_ui_screen = "cart";
    /// 最近一帧卡带界面的可观测快照（扁平控件表，JSON）；agent 用 ui.list 读
    std::string cart_ui_json;
    /// 控制通道请求：下一帧把焦点移到 / 激活某个控件 id（agent 用 ui.focus / ui.activate）
    std::string pending_ui_focus;
    std::string pending_ui_activate;
    /// 卡带注册的输入动作（`phos.input.action`）：动作名 → 虚拟键列表。
    /// 未注册 = 默认映射同名虚拟键；已注册但空表 = 无绑定键（恒 false）。
    /// 按脚本会话存在，随 HostCartBinding 清理（不写全局、不持久化）
    std::map<std::string, std::vector<std::string>> input_actions;
    /// 当前卡带（供 `phos.debug.number` 把可调参数注册到它上面）。由 Cartridge 装配时挂上、
    /// 拔卡时清空；无卡带时为 nullptr，phos.debug.* 安全无效
    Cartridge* cart = nullptr;
    std::string save_dir = kSaveDir;    // 存档目录（--save-dir / 测试模式可改指向独立目录）
    double time = 0.0;                  // 卡带运行秒数
    long frame = 0;                     // 正在推进的逻辑帧号（与 state.query 的 frame 同源）
    int fps = kLogicFps;                // 实际帧率（窗口模式由主循环刷新；无头模式为逻辑帧率）
    /// 字形墨迹框查询（`phos.text.ink_box`）。窗口渲染器就绪时由 App 装配；
    /// 无头或字体未就绪时为空，调用方退回整格宽（见 core/text.hpp 的 GlyphBox）
    std::function<GlyphBox(char32_t)> glyph_metrics;
    /// 当前单元格像素边长（= 字号）：`phos.text.ink_box` 无渲染器时按它退回整格宽
    int cell_px = kCellPx;
    /// 卡带是否接管 Esc（`phos.sys.capture_escape`）：true 时 Esc 作为普通键注入卡带。
    /// 由 App 指向其成员；未接（无头）时为 nullptr，capture_escape 调用安全无效
    bool* capture_escape = nullptr;
    /// 本帧是否有输入框声明要收中文（`phos.input.field({ ime = true })` 被 feed 时置位）。
    /// App 每帧清零、帧末据此开关系统输入法。**默认关**——游戏进行中、以及不声明中文的框
    /// （含主机自带的卡带架搜索）都不该挂着输入法
    bool ime_wanted = false;
    std::string language = "zh";        // 界面语言（"zh"/"en"）：卡带据此选自己的文案
    std::mt19937 rng;                   // 确定性模式下由种子驱动

    // 内容区（"屏幕"）在网格中的位置与尺寸——卡带只见 80x45 局部坐标
    int content_x = 0, content_y = 0, content_w = kContentW, content_h = kContentH;

    // 侧栏面板：宽度 0 表示无面板（在其宿主坐标系内位于内容区右侧）
    int panel_w = 0;
    /// 侧栏面板的**默认底色**（取自当前主题的 skin.panel）：卡带 `panel.clear()` 不带色时
    /// 用它，于是右栏底色随主题、而不是透出游戏画面。由 App 每帧从主题写入
    Color panel_bg{0, 0, 0};

    /// 卡带场景栈（`phos.scene`）：由 Cartridge 持有并在此挂指针；无卡带/主机动画时为 nullptr。
    /// App 按它决定"是否跳过卡带 update、是否暂停音频、是否在卡带 draw 之后再画场景"
    SceneStack* scenes = nullptr;
    ui::Toasts* toasts = nullptr;  // 卡带的瞬时提示（App 持有并绘制）

    // 可选图层缓冲（`phos.layer`）。卡带不建层时它是空的，主循环里连一次合并都不发生；
    // 每次插卡由 App 重置，于是层随卡带生命周期
    LayeredScreen layers;

    int panel_origin_x() const { return content_x + content_w - panel_w; }
};

/// 一次"宿主脚本会话"的 RAII 绑定（卡带 / 开机动画 / 卡带架样式包）。
///
/// 生命周期归属：HostContext 里的 `save` / `cart_files` / `cart_info` / `cart` / `scenes`
/// 都指向当前脚本对象（Cartridge）——脚本装配时写入（`Cartridge::assemble`），脚本销毁前
/// 必须置空，否则 API 层手里就是悬垂指针。清理本体在 `App::unbind_host_cart()`；
/// 动作表（`input_actions`）由本对象在构造 / 析构 / 换脚本时清空。
///
/// **所有权**：卡带脚本对象由本对象持有（`std::unique_ptr<Cartridge>`）。于是"重置绑定"是一个
/// 原子语义：先清 HostContext 的脚本字段，再销毁卡带——不存在"忘了单独 reset 卡带"这条路。
/// 内置开机自检没有脚本对象，持 nullptr；开机动画 / 架子包脚本仍由 App 持有（生命周期与
/// 卡带会话不完全重叠），本对象只负责清 HostContext。
///
/// 析构顺序是契约：先 on_release() 清 HostContext，再销毁 `cart_`。卡带（Lua state /
/// 场景栈 / UI 态）析构期间，谁都不可能再从 HostContext 拿到它。
class HostCartBinding {
public:
    /// 接管 cart 的所有权（可为 nullptr：没有脚本对象的会话）。
    /// on_release 必须幂等，且不得访问正在被销毁的卡带。
    HostCartBinding(HostContext& host, std::unique_ptr<Cartridge> cart,
                    std::function<void()> on_release);
    ~HostCartBinding();
    HostCartBinding(const HostCartBinding&) = delete;
    HostCartBinding& operator=(const HostCartBinding&) = delete;

    /// 当前卡带（不转移所有权；没有脚本对象时为 nullptr）
    Cartridge* cart() const { return cart_.get(); }

    /// 同一会话内换脚本对象（重载 / 开机期间插卡）：先摘掉 HostContext 里指向旧对象的指针，
    /// 再销毁旧对象、接管新的。会话级的 UI/toast 清理不在这里做——调用方按旧时点清
    void replace_cart(std::unique_ptr<Cartridge> cart);

private:
    /// 把 cart_ 的入口挂进 HostContext（`cart_files` 仍由 Cartridge::assemble 打开包时写入）
    void install_host_entries();
    /// 只摘 HostContext 里指向脚本的 5 个指针（不动 toast / UI 态）
    void detach_host_entries();

    HostContext& host_;
    std::unique_ptr<Cartridge> cart_;
    std::function<void()> on_release_;
};

/// 向 Lua 沙箱注册 phos.* API（见 docs/api-reference.md）。
/// 这是全工程唯一允许接触 Lua 的模块。
void register_host_api(sol::state& lua, HostContext& host);

/// 将色板写入已注册的 phos.color 表（切换主题时热更新）
void apply_palette_to(sol::state& lua, const Palette& palette);

} // namespace phos
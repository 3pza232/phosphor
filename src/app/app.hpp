#pragma once

#include "app/agent_controller.hpp"
#include "app/boot_sequence.hpp"
#include "app/display_state.hpp"
#include "app/font_state.hpp"
#include "app/shelf_playback.hpp"
#include "app/sound_state.hpp"

#include "agent/cli.hpp"
#include "agent/control_channel.hpp"
#include "agent/debug_console.hpp"
#include "api/host_api.hpp"
#include "cart/cartridge.hpp"
#include "core/audio.hpp"
#include "core/config.hpp"
#include "core/crt.hpp"
#include "core/defaults.hpp"
#include "core/display.hpp"
#include "core/input.hpp"
#include "core/palette.hpp"
#include "core/screen.hpp"
#include "core/skin.hpp"
#include "net/net.hpp"
#include "pack/content_library.hpp"
#include "pack/pack.hpp"
#include "shell/shell.hpp"
#include "ui/toast.hpp"

#include <memory>
#include <string>
#include <vector>

namespace phos {

/// 应用生命周期与主循环（固定逻辑帧 + 渲染帧）。
/// 五类内容包：游戏机主题（skin，内含内容色板 palette）/ 启动动画（boot）/
/// 音效包（sound）/ 字体方案（font）/ 卡带（cart）。
class App {
public:
    /// 运行主机。返回进程退出码（约定见 agent-interface.md）。
    int run(const CliOptions& opts);

private:
    // 主循环
    int run_windowed(const CliOptions& opts);
    int run_headless(const CliOptions& opts);

    /// 推进一个逻辑帧：按当前状态分派（拔卡收缩 / 开机 / 卡带 / 外壳）
    void advance(float dt, class Renderer* renderer, class Window* window);
    /// 推进一帧并完成帧末收口：advance → frame_count_ → 定时注入释放 → 单步回包 → dump。
    /// 三个主循环（无头 / 窗口实时 / 窗口单步）共用的唯一一份步进语义，差异全由参数表达：
    /// renderer/window 无头传 nullptr；consumes_step 表示本帧是否消耗一个 time.step 待推进帧。
    void step_frame(const CliOptions& opts, class Renderer* renderer, class Window* window,
                    bool consumes_step);
    void tick_playing(float dt);
    void tick_boot(float dt);
    void tick_shell(class Renderer* renderer, class Window* window);
    bool boot_should_end() const;
    void end_boot();

    // 输入与模式
    void handle_escape();
    void handle_intent(const Shell::Intent& intent, class Renderer* renderer,
                       class Window* window);

    // 卡带
    void load_cart(int index);
    void load_cart_path(const std::string& path);
    void eject_cart();
    /// 结束当前宿主脚本会话并清空 HostContext 的脚本态（幂等）。正常路径走 RAII 绑定：
    /// 已有 script_binding_ 时 reset() 它，由 HostCartBinding 析构统一清理；没有绑定对象时
    /// （架子包的装配在 app_settings，尚未接入绑定）直接走 unbind_host_cart()。
    /// **新代码优先用 arm_script_binding + 绑定 reset**，不要再在这里加手工清理点
    void clear_host_cart();
    /// 脚本态清理的**唯一实现**：清空 HostContext 里指向脚本的字段与随脚本存在的 UI 态，
    /// 并清 toast、复位场景音频标志。由绑定析构或兼容入口调用，不要在别处内联复制一份
    void unbind_host_cart();
    /// 武装一次宿主脚本会话并**移交**脚本对象：绑定接管 cart 的所有权（nullptr = 没有
    /// 脚本对象，如内置开机自检）。已在会话中时在同一会话内换脚本对象（重载 / 开机期插卡），
    /// 不重置 UI/toast 态。于是"重置绑定" = 清 HostContext + 销毁卡带，App 不再单独 reset 卡带
    void arm_script_binding(std::unique_ptr<Cartridge> cart);
    /// 当前卡带：由 script_binding_ 持有（无卡带 / 开机 / 架子会话时为 nullptr）。
    /// 调用点自己判空；const 方法也可调用（访问器只是转发，不转移所有权）
    Cartridge* cart() const { return script_binding_ ? script_binding_->cart() : nullptr; }
    /// 重扫卡带目录并按"最近打开"重排架子（启动时与拔卡回架子后各调用一次）
    void refresh_shelf_order();

    // 子系统
    /// 音频设备初始化（必须在开机动画之前调用：这一秒内就有声音）
    void init_audio();
    /// 卡带脚本出错的统一出口：写日志（错误画面另由 shell_.show_error 负责）
    void log_cart_error(const std::string& message);

    /// 按 fonts_.effective_px() 把单元格尺寸推给渲染器、调整窗口大小（截图路径每帧现读
    /// font_px_，无需处理）。字号 = 格边长，行距随之缩放
    void apply_font_px(class Renderer* renderer, class Window* window);
    /// 设置字号：px<=0 表示"跟随字体方案"（0）；正数钳进当前方案声明的可调范围后生效并落盘
    void apply_font_size(int px, class Renderer* renderer, class Window* window);

    // 内容包应用
    void apply_skin(int index, class Window* window, class Renderer* renderer = nullptr);
    void apply_font_scheme(int index, class Renderer* renderer, class Window* window);
    void apply_boot(int index);
    void apply_sound(int index);
    /// 应用卡带架样式候选项（0=list、1=window、2+i=第 i 个 shelf 包）：
    /// 切到包时加载其 shelf.lua 并把内容区交给它绘制；切回内置或加载失败则清掉包脚本。
    /// 找不到包 / 包坏了 → 安静回退 window + 日志告警
    void apply_shelf(int select);
    /// 内容包绘制回调：把架子状态翻成 ctx 交给当前 shelf 包的 draw(ctx)；
    /// 包缺失或本帧报错则当帧回退内置样式
    void draw_shelf_content(Screen& screen, const ui::Rect& content, const ShelfView& view,
                            const ui::Style& style);
    void apply_crt(int level, class Renderer* renderer);
    void start_boot_animation();
    void save_config_now();

    /// 主机事件音：薄转发到 SoundState（音效包选择/采样缓存/播放编排都在那里）。
    /// 保留这个一行的 App 入口是因为 app_cart 等调用点在本次写权限之外
    void play_event(const std::string& event);
    /// 界面上的任意按键边沿（用于按键音）
    bool any_key_edge() const;

    /// 内容区矩形（效果与分隔线绘制共用）
    ui::Rect content_rect() const;

    // 观测（非 const：仪表盘允许直接调参，见 app.cpp 的 console 渲染）
    void fill_debug_info(DebugInfo& info);

    // 控制通道（agent 接口；实现见 app_control.cpp）
    /// 构造 AgentServices（动作回调 + 状态快照来源）；run() 启动时调用一次
    void init_agent_services();
    /// state.query 的快照：把跨子系统当前值收成纯数据（AgentController 负责排版 JSON）
    AgentState capture_agent_state() const;
    void poll_control();
    void execute_control(const ControlCommand& command);
    void complete_step_request();
    /// 落地一条 frame.read：读回当前帧缓冲（仅窗口路径），可选写 PNG，然后回包。
    /// 必须由渲染循环在 draw/draw_layers 之后、swap_buffers 之前调用——后缓冲在
    /// swap 之后即失效，读回时机只有那里是正确的
    void complete_frame_read(class Renderer* renderer);
    std::string control_state_json() const;
    /// 时间是否由控制通道驱动（此时主循环只在 time.step 时推进逻辑帧）
    bool control_time_driven() const { return control_.running() && agent_.stepping; }
    /// 注入按键的定时释放
    void release_expired_inputs();
    /// 组装窗口标题：agent 接管时明确写出"谁在操作、实时还是单步"
    std::string window_title_for_state() const;
    /// 应用一条输入动作：虚拟手柄键进 Input 并可按帧释放，主机保留键走主机语义。
    /// agent 的控制通道经此一处落地，与玩家按键语义必然一致。
    void apply_input_action(const InputAction& action, int hold_frames = 0);

    // 工具
    std::string mode_name() const;
    void maybe_dump(const CliOptions& opts, long frame) const;
    /// 运行收尾输出：屏幕文本（--dump-screen）与截图（--screenshot）
    void write_final_outputs(const CliOptions& opts) const;
    /// 当前画面写成 PNG（CPU 光栅化，无头可用）；成功填宽高，失败填 error
    bool write_screenshot(const std::string& path, int& width, int& height,
                          std::string& error) const;

    static constexpr float kLogicStep = 1.0f / static_cast<float>(kLogicFps);
    static constexpr const char* kConfigPath = "config.json";
    /// 实际配置路径（--config 可改；工具脚本据此把实测配置与用户的 config.json 隔开）
    std::string config_path_ = kConfigPath;
    /// 实际"最近打开"记录路径（--recent 可改；工具脚本据此让卡带架顺序可复现）
    std::string recent_path_ = kRecentPath;
    static constexpr const char* kCartDir = "carts";
    /// 卡带架的"最近打开"记录（见 core/config.hpp 的 load_recent）
    static constexpr const char* kRecentPath = "recent.txt";

    static constexpr const char* kFontDir = "theme/font";  // 字体方案根目录（注入 FontState）

    // 仪式感时长（秒）
    static constexpr float kInsertFlashTime = 0.30f;
    static constexpr float kEjectCollapseTime = 0.35f;

    /// 三块显示面与 CRT 参数（纯状态；合成/渲染交互仍由 App 执行），见 app/display_state.hpp
    DisplayState display_state_;
    Input input_;
    HostContext host_;
    Shell shell_;
    std::unique_ptr<Cartridge> boot_script_;
    /// 卡带架样式包脚本与动画时钟（内容区由它绘制；画家注册 / config / packs 编排仍归 App）
    ShelfPlayback shelf_playback_;

    /// 主机所处的**唯一**顶层面：开机动画 / 系统界面 / 卡带运行。三者互斥，于是"同时开机
    /// 又在玩"这类非法组合不可表示。系统界面内部的分支（设置 / 暂停 / Mod / 磁带码 /
    /// 错误屏 / 卡带架）仍由 shell 的 ShellMode 表达——本枚举只决定 App::advance 分派到
    /// 哪个 tick。默认 boot：run() 先播开机动画
    enum class Mode { boot, shelf, playing };
    Mode mode_ = Mode::boot;
    /// 读点用这两个判据（与 enum 一一对应）；写点直接赋 mode_
    bool in_boot() const { return mode_ == Mode::boot; }
    bool playing() const { return mode_ == Mode::playing; }
    /// 开机时序（已过时间/目标时长/完成判定）。脚本装载、模式切换、失败回退与 Esc 跳过仍由 App 编排
    BootSequence boot_sequence_;
    bool quit_ = false;

    Config config_;
    /// 内容包（皮肤/色板/开机动画/音效）：有什么、选中哪个，见 pack/content_library.hpp
    ContentLibrary packs_;
    /// 当前生效的色板副本：由主题的 skin.palette 解析而来，host_.palette 指向它
    Palette active_palette_;

    Audio audio_;
    /// 主机事件音与采样缓存（音效包索引仍在 packs_，配置持久化仍归 App）
    SoundState sound_state_;
    Net net_;  // 局域网联机（随卡带生命周期，见 app_cart.cpp）
    ui::Toasts toasts_;  // 卡带的瞬时提示（绘制在内容区底边，不冻结世界）

    // 仪式感动效状态
    float insert_flash_ = 0.0f;    // 插卡瞬间的电压闪烁
    float eject_collapse_ = 0.0f;  // 拔卡时的画面收缩

    // 循环指标（帧号与帧率，整个会话共享）
    float fps_ = 0.0f;
    long frame_count_ = 0;

    /// 卡带逐帧耗时（毫秒）：update / draw / 图层合成，以及约 1 秒窗口内的峰值
    /// （瞬时值抓不到偶发卡顿，而卡顿恰恰是要查的）。集中一处：换卡 / 拔卡时一次
    /// `reset()`——散落时正是漏了 `merge_ms`，拔卡后 `state.query` 还报着上一张的耗时
    struct CartTiming {
        float update_ms = 0.0f;
        float draw_ms = 0.0f;
        float update_peak_ms = 0.0f;
        float draw_peak_ms = 0.0f;
        float merge_ms = 0.0f;  // 图层合成耗时（没建层的卡带恒为 0）
        void reset() { *this = CartTiming{}; }
    };
    CartTiming timing_;
    unsigned rng_seed_ = 0;

    DebugConsole console_;
    /// 卡带注册的可调参数**分组树**（`phos.debug.number`）：每帧由 fill_debug_info 重建（文案按当前
    /// 语言解析），控制台在叶子上改值，帧末写回卡带
    DebugGroup params_root_;
    /// "打开调试台即暂停游戏"：控制台里的复选框写它，主循环据此冻结卡带
    bool pause_when_open_ = false;
    bool escape_flag_ = false;
    bool capture_escape_ = false;  // 卡带是否接管 Esc（phos.sys.capture_escape）
    /// 场景栈当前是否把音频暂停着（只在"要变"时调用 set_paused，避免与卡带自己的暂停互相盖）
    bool scene_audio_paused_ = false;
    bool settings_flag_ = false;
    bool console_flag_ = false;
    bool input_blocked_ = false;
    std::string last_error_;

    /// 字体方案状态（方案表/当前方案/字号范围/字体链）：窗口渲染与截图/基线共用同一份
    /// 路径表，所以两边字体必然一致。当前生效字号仍由 App 持有（它同时决定窗口尺寸）
    FontState fonts_;
    int font_px_ = kDefaultFontPx;  // 当前生效字号（= 单元格像素边长）

    // 运行形态（供状态查询与窗口标题使用）
    bool headless_ = false;          // true = 无窗口（agent/CI）
    int control_port_ = 0;           // 0 = 未开控制通道
    std::string window_title_;       // 当前标题（避免每帧重复设置）

    // 控制通道 + agent 会话状态
    ControlChannel control_;
    /// agent 控制通道的会话语义（单步/待回包/按键定时释放）：定义与实现见
    /// app/agent_controller.hpp；保留为 App 成员，因为主循环与换卡路径都直接读写它
    AgentSession agent_;
    /// 控制通道的语义侧：命令分发 / 单步回包 / frame.read 落地 / 按键释放 / 观察面 JSON
    AgentController agent_controller_;
    /// AgentController 的窄接口：动作回调 + 状态快照来源（不持有 App）
    AgentServices agent_services_;
    std::string cart_path_;  // 当前卡带路径（供 cart.reload）

    /// 当前宿主脚本会话的 RAII 绑定（见 api/host_api.hpp 的 HostCartBinding）。
    /// 它**持有当前卡带的所有权**（App 不直接持有卡带对象）：重置绑定 = 先清 HostContext、
    /// 再销毁卡带。声明在最后：App 析构时它**先**析构，on_release 仍能安全访问 toasts_ /
    /// scene_audio_paused_ 等成员（成员逆序析构，这行就是清理顺序的保证）
    std::unique_ptr<HostCartBinding> script_binding_;
};

} // namespace phos
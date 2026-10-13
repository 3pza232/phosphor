#pragma once

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
#include "shell/shell.hpp"

#include <map>
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
    /// 重扫卡带目录并按"最近打开"重排架子（启动时与拔卡回架子后各调用一次）
    void refresh_shelf_order();

    // 子系统
    /// 音频设备初始化（必须在开机动画之前调用：这一秒内就有声音）
    void init_audio();
    /// 卡带脚本出错的统一出口：写日志（错误画面另由 shell_.show_error 负责）
    void log_cart_error(const std::string& message);

    /// 装载字体链：wanted 为方案名，方案不可用时退回 default 并告警
    void load_font_chain(const std::string& wanted);

    // 内容包应用
    void apply_skin(int index, class Window* window, class Renderer* renderer = nullptr);
    void apply_font_scheme(int index, class Renderer* renderer);
    void apply_boot(int index);
    void apply_sound(int index);
    void apply_crt(int level, class Renderer* renderer);
    void start_boot_animation();
    void save_config_now();

    // 音频事件（音效包驱动：优先包内音频文件，否则合成音）
    void play_event(const std::string& event);
    int sample_handle_for(const std::string& event, const std::string& path);
    /// 界面上的任意按键边沿（用于按键音）
    bool any_key_edge() const;

    /// 内容区矩形（效果与分隔线绘制共用）
    ui::Rect content_rect() const;

    // 观测（非 const：仪表盘允许直接调参，见 app.cpp 的 console 渲染）
    void fill_debug_info(DebugInfo& info);

    // 控制通道（agent 接口；实现见 app_control.cpp）
    void poll_control();
    void execute_control(const ControlCommand& command);
    void complete_step_request();
    /// 落地一条 frame.read：读回当前帧缓冲（仅窗口路径），可选写 PNG，然后回包。
    /// 必须由渲染循环在 draw/draw_layers 之后、swap_buffers 之前调用——后缓冲在
    /// swap 之后即失效，读回时机只有那里是正确的
    void complete_frame_read(class Renderer* renderer);
    std::string control_state_json() const;
    std::string carts_json() const;
    std::string shelf_json() const;
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
    static constexpr const char* kCartDir = "carts";
    /// 卡带架的"最近打开"记录（见 core/config.hpp 的 load_recent）
    static constexpr const char* kRecentPath = "recent.txt";

    static constexpr const char* kFontDir = "theme/font";                // 字体方案根目录
    static constexpr const char* kDefaultFontScheme = "default";         // 出厂默认方案名

    // 仪式感时长（秒）
    static constexpr float kInsertFlashTime = 0.30f;
    static constexpr float kEjectCollapseTime = 0.35f;

    /// 三块显示面（卡带纹理视图 / 合成前底图 / 主机 chrome）与合成顺序，见 core/display.hpp
    Display display_;
    Input input_;
    HostContext host_;
    Shell shell_;
    std::unique_ptr<Cartridge> cart_;
    std::unique_ptr<Cartridge> boot_script_;

    bool playing_ = false;
    bool in_boot_ = true;
    float boot_elapsed_ = 0.0f;
    bool quit_ = false;

    Config config_;
    /// 内容包（皮肤/色板/开机动画/音效）：有什么、选中哪个，见 pack/content_library.hpp
    ContentLibrary packs_;
    /// 当前生效的色板副本：由主题的 skin.palette 解析而来，host_.palette 指向它
    Palette active_palette_;
    CrtParams active_crt_;

    Audio audio_;
    Net net_;  // 局域网联机（随卡带生命周期，见 app_cart.cpp）
    std::map<std::string, int> sample_cache_;  // 音效包内音频文件的解码句柄缓存

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
    bool escape_flag_ = false;
    bool capture_escape_ = false;  // 卡带是否接管 Esc（phos.sys.capture_escape）
    bool settings_flag_ = false;
    bool console_flag_ = false;
    bool input_blocked_ = false;
    std::string last_error_;

    // 字体：当前方案的字体链（主字体在前，回退在后）与全部可用方案名。
    // 窗口渲染与截图/基线共用同一份路径表，所以两边字体必然一致
    std::vector<std::string> font_files_;
    std::vector<std::string> font_schemes_;  // 全部可用方案（default 排最前）
    std::string font_scheme_;                // 实际生效的方案（配置指定不可用时退回 default）

    // 运行形态（供状态查询与窗口标题使用）
    bool headless_ = false;          // true = 无窗口（agent/CI）
    int control_port_ = 0;           // 0 = 未开控制通道
    std::string window_title_;       // 当前标题（避免每帧重复设置）

    // 控制通道 + agent 会话状态
    ControlChannel control_;
    /// agent 控制通道的**会话状态**（与通道的 I/O 分开：通道只管收发，这里管"会话语义"：
    /// 单步推进、待回包的请求、注入按键的定时释放）。集中一处，见 app_control.cpp
    struct AgentSession {
        bool stepping = false;        // 时间由 agent 驱动：只在 time.step 时推进逻辑帧
        int pending_steps = 0;        // 待推进的逻辑帧数
        int step_request_id = -1;     // 待回包的 time.step 请求 id
        int frame_read_id = -1;       // 待回包的 frame.read 请求 id（<0 = 无）
        std::string frame_read_path;  // frame.read 的落盘路径（空 = 只回统计）
        std::vector<std::pair<std::string, int>> pending_releases;  // 注入按键的定时释放（按名字记）
    };
    AgentSession agent_;
    std::string cart_path_;  // 当前卡带路径（供 cart.reload）
};

} // namespace phos

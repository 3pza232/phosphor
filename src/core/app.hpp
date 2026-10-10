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
#include "core/input.hpp"
#include "core/palette.hpp"
#include "core/screen.hpp"
#include "core/skin.hpp"
#include "pack/pack.hpp"
#include "shell/shell.hpp"

#include <map>
#include <memory>
#include <string>
#include <vector>

namespace phos {

/// 应用生命周期与主循环（固定逻辑帧 + 渲染帧）。
/// 四层可替换内容：游戏机主题（skin）/ 显像管滤镜（filter）/ 启动动画（boot）/ 卡带（cart）。
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
    void apply_skin(int index, class Window* window);
    void apply_filter(int index, class Renderer* renderer);
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
    std::string control_state_json() const;
    std::string carts_json() const;
    std::string shelf_json() const;
    /// 时间是否由控制通道驱动（此时主循环只在 time.step 时推进逻辑帧）
    bool control_time_driven() const { return control_.running() && control_stepping_; }
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

    // 内容目录：用户区优先，出厂区兜底（查找顺序见 content-packs.md）
    static constexpr const char* kUserSkinDir = "theme/skin";
    static constexpr const char* kUserFilterDir = "theme/palette";
    static constexpr const char* kUserBootDir = "theme/boot";
    static constexpr const char* kUserSoundDir = "theme/sound";
    // 出厂区：随主机发布的内容包的位置；用户区有同名项时用户区优先
    static constexpr const char* kFactorySkinDir = "system/skin";
    static constexpr const char* kFactoryFilterDir = "system/palette";
    static constexpr const char* kFactoryBootDir = "system/boot";
    static constexpr const char* kFactorySoundDir = "system/sound";

    // 仪式感时长（秒）
    static constexpr float kInsertFlashTime = 0.30f;
    static constexpr float kEjectCollapseTime = 0.35f;

    Screen screen_;
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
    std::vector<Skin> skins_;
    int skin_index_ = 0;
    std::vector<Palette> filters_;
    int filter_index_ = 0;
    Palette active_filter_;
    CrtParams active_crt_;
    std::vector<BootPack> boots_;
    int boot_index_ = 0;
    std::vector<SoundPack> sounds_;
    int sound_index_ = 0;

    Audio audio_;
    std::map<std::string, int> sample_cache_;  // 音效包内音频文件的解码句柄缓存

    // 仪式感动效状态
    float insert_flash_ = 0.0f;    // 插卡瞬间的电压闪烁
    float eject_collapse_ = 0.0f;  // 拔卡时的画面收缩

    // 运行指标（供仪表盘）
    float fps_ = 0.0f;
    long frame_count_ = 0;
    float cart_update_ms_ = 0.0f;
    float cart_draw_ms_ = 0.0f;
    float cart_update_peak_ms_ = 0.0f;  // 约 1 秒窗口内的峰值（瞬时值抓不到偶发卡顿）
    float cart_draw_peak_ms_ = 0.0f;
    unsigned rng_seed_ = 0;

    DebugConsole console_;
    bool escape_flag_ = false;
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

    // 控制通道状态
    ControlChannel control_;
    bool control_stepping_ = false;      // 时间由 agent 驱动的"单步模式"
    int pending_steps_ = 0;              // 待推进的逻辑帧数
    int step_request_id_ = -1;           // 待回包的 time.step 请求 id
    std::string cart_path_;              // 当前卡带路径（供 cart.reload）
    std::vector<std::pair<std::string, int>> pending_releases_;  // 注入按键的定时释放（按名字记）
};

} // namespace phos

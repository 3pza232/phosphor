#pragma once

#include "core/input.hpp"

#include <cstddef>
#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace phos {

class Cartridge;
class ControlChannel;
class LayeredScreen;
class Renderer;
class SaveStore;
class Screen;
class Shell;
struct ControlCommand;
struct HostContext;

/// 控制通道的**会话语义**（与 ControlChannel 的 I/O 分开）：单步推进、待回包请求、
/// 注入按键的定时释放。保留为独立 struct，App 直接持有；AgentController 只按事件操作它。
struct AgentSession {
    bool stepping = false;        // 时间由 agent 驱动：只在 time.step 时推进逻辑帧
    int pending_steps = 0;        // 待推进的逻辑帧数
    int step_request_id = -1;     // 待回包的 time.step 请求 id
    int frame_read_id = -1;       // 待回包的 frame.read 请求 id（<0 = 无）
    std::string frame_read_path;  // frame.read 的落盘路径（空 = 只回统计）
    std::vector<std::pair<std::string, int>> pending_releases;  // 注入按键的定时释放（按名字记）
};

/// state.query 的**快照**：App 把跨子系统的当前值收成纯数据，AgentController 只负责
/// 排版成协议 JSON。这样观察面不需要 App&，字段顺序/协议由一侧保证。
struct AgentState {
    long frame = 0;
    std::string mode;
    bool playing = false;
    bool headless = false;
    int control_port = 0;
    unsigned seed = 0;
    std::string cart_path;
    std::string last_error;
    int crt_level = 0;
    int fps = 0;
    int music_volume = 0;
    int sfx_volume = 0;
    std::string skin_id;
    std::string palette_id;
    std::string boot_id;
    std::string sound_id;
    std::string font_name;
    int font_px = 0;
    int font_max_px = 0;
    std::string language;  // 已按界面语言解析好的 "zh"/"en"
    int cursor = 0;
    std::vector<std::string> shelf_ids;   // 架上的卡带 id（玩家顺序）
    std::vector<std::string> held_keys;  // 当前按下的虚拟按键名
    std::vector<std::string> font_names;
    struct Pack {
        std::string name;  // 显示名
        std::string id;    // 稳定 id
    };
    std::vector<Pack> skins, palettes, boots, sounds, shelves;
    struct DebugParam {
        std::string name;
        std::string group;  // 分组路径（'/' 拼接）
        std::string kind;   // "integer" / "boolean" / "number"
        double value = 0.0;
    };
    std::vector<DebugParam> debug_params;
    bool has_cart = false;
    std::string cart_id, cart_name, cart_version, cart_author;
    int sidebar_w = 0;
    int lua_mem_kb = 0;
    float merge_ms = 0.0f;
    float update_ms = 0.0f, draw_ms = 0.0f;
    float update_peak_ms = 0.0f, draw_peak_ms = 0.0f;
    bool save_available = false;
    std::size_t save_entries = 0;
    /// 子系统只读视图（App 注入，不是 App 引用）：屏幕/图层/场景/音频/UI 快照等
    const HostContext* host = nullptr;
};

/// execute_control 的窄接口：动作交给 App（只有它知道 load_cart 牵动哪些子系统），
/// 状态以回调/快照提供。AgentController 不持有 App。
struct AgentServices {
    std::function<std::string()> state_json;
    std::function<const Screen*()> screen;  // 合并后的整屏（screen.read 默认来源）
    std::function<const LayeredScreen*()> layers;
    std::function<long()> frame;
    std::function<bool()> headless;
    std::function<bool(const std::string& path, int& width, int& height, std::string& error)>
        screenshot;
    std::function<SaveStore*()> save;
    std::function<Cartridge*()> cart;
    std::function<std::string()> cart_path;
    std::function<std::string()> cart_dir;  // 卡带目录（carts.scan 的扫描根）
    std::function<void(const std::string&)> load_cart;
    std::function<void()> eject_cart;
    std::function<bool()> playing;
    std::function<std::string()> last_error;
    std::function<bool()> english;  // 界面语言是否 en（参数名/文案解析共用）
    std::function<Input*()> input;
    std::function<bool(const std::string& key, bool down, InputAction& action)>
        make_input_action;
    std::function<void(const InputAction& action, int hold_frames)> apply_input;
    std::function<void()> request_quit;
    std::function<std::string()> cart_ui_json;
    std::function<void(const std::string& id, bool focus)> queue_ui;  // focus=false → activate
};

/// 控制通道的语义侧：命令分发（21 分支）、观察面 JSON、单步/取消/frame.read/按键释放胶水。
/// ControlChannel 的 I/O 与协议字段不在这里改；App 只构造 AgentServices 并转发。
class AgentController {
public:
    /// 执行一条控制通道命令：回复/错误文案/回包时机与旧 App::execute_control 逐项一致
    void execute(const ControlCommand& command, ControlChannel& channel, AgentSession& session,
                 const AgentServices& services) const;

    /// state.query 的观察面：AgentState 快照 + 会话状态 → 协议 JSON
    std::string state_json(const AgentState& state, const AgentSession& session) const;

    // --- 单步 / 取消胶水（time.step、time.resume、frame.read、input.clear） ---
    bool begin_step(AgentSession& session, int frames, int request_id, std::string& error) const;
    int abandon_step(AgentSession& session) const;
    void begin_frame_read(AgentSession& session, int request_id, const std::string& path) const;
    void clear_pending_inputs(AgentSession& session, Input& input) const;

    /// 单步推进完成：若有在途 time.step，用当前状态 JSON 回包并清 id
    void complete_step(ControlChannel& channel, AgentSession& session,
                       const std::function<std::string()>& state_json) const;
    /// frame.read 的落地时机（画完一帧、swap 之前）：读回帧/统计/可选 PNG 后回包
    void complete_frame_read(ControlChannel& channel, AgentSession& session,
                             Renderer* renderer) const;
    /// 注入按键的定时释放：每个逻辑帧调一次
    void release_expired(AgentSession& session, Input& input) const;

    /// 一次 time.step 最多推进多少逻辑帧（防止超大帧数把主机卡住）
    static constexpr int kMaxStepFrames = 100000;

    // --- 观察面小工具（App 构快照 / 其它调用点复用） ---
    static std::string layers_json(const LayeredScreen& layers);
    static std::string scenes_json(const HostContext& host);
    static std::string screen_lines_json(const Screen& screen);
    std::string carts_json(const std::string& cart_dir, bool english) const;
    std::string shelf_json(const Shell& shell) const;
};

} // namespace phos

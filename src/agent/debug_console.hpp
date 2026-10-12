#pragma once

#include "core/crt.hpp"
#include "core/defaults.hpp"

#include <string>
#include <vector>

struct GLFWwindow;

namespace phos {

/// 仪表盘展示的主机运行参数（由 App 每帧填充）。
/// `crt` 指向激活的 CRT 参数，可直接在面板中调节并即时生效。
struct DebugInfo {
    // 性能
    float fps = 0.0f;
    float frame_ms = 0.0f;
    long frame = 0;
    int logic_hz = 60;

    // 主机
    std::string mode;
    bool playing = false;
    double host_time = 0.0;
    int grid_w = 0, grid_h = 0, content_w = 0, content_h = 0, panel_w = 0;
    unsigned rng_seed = 0;

    // 卡带
    std::string cart_id, cart_name, cart_version, cart_author, cart_error;
    float update_ms = 0.0f, draw_ms = 0.0f;
    int lua_mem_kb = 0;

    // 内容包与界面
    std::string skin_name, boot_name;
    std::string shelf_style, crt_level_name;
    int music_volume = kDefaultMusicVolume, sfx_volume = kDefaultSfxVolume;

    // 输入
    std::vector<std::string> held_keys, edge_keys;

    // 可实时调节
    CrtParams* crt = nullptr;
};

/// ImGui 参数仪表盘（` 键呼出）。
/// 职责单一：观测与调节主机运行参数，不承担画面显示。
class DebugConsole {
public:
    /// 初始化 ImGui 上下文与后端。须已有当前 GL 上下文。
    bool init(GLFWwindow* window, std::string& err);
    void shutdown();

    bool open = false;

    /// 是否正在操作面板控件——仅此时阻断游戏输入
    bool wants_input() const { return wants_input_; }

    /// 每帧渲染（场景绘制后、交换缓冲前调用；open == false 时直接返回）
    void render(const DebugInfo& info);

private:
    bool initialized_ = false;
    bool wants_input_ = false;
};

} // namespace phos

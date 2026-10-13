#pragma once

#include "core/crt.hpp"
#include "core/defaults.hpp"

#include <cstddef>
#include <string>
#include <vector>

struct GLFWwindow;

namespace phos {

/// 一个可实时调的卡带参数（`phos.debug.number` 的**纯数据**快照）。
/// 控制台画滑条直接改 `value`；改动由 App 帧末写回卡带（见 App::run_windowed）
struct DebugParam {
    std::string name;      // 已按当前界面语言解析
    std::size_t index = 0; // 在卡带参数表里的下标（App 写回时用）
    DebugKind kind = DebugKind::number;  // 浮点滑条 / 整数滑条 / 复选框
    float value = 0.0f;
    float min = 0.0f, max = 1.0f, step = 0.01f;
    bool readable = true;  // get 取不到值的项只展示名字，不画控件
    bool changed = false;  // 控制台改过：置位，App 据此写回
};

/// 参数分组树：文件夹式折叠层级。顶层 `params` 直接显示，`groups` 是默认关闭的折叠节点
struct DebugGroup {
    std::string label;
    std::vector<DebugParam> params;
    std::vector<DebugGroup> groups;
};

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
    /// 卡带注册的可调参数**分组树**（`phos.debug.number`）。App 每帧重建（文案已按当前语言解析），
    /// 控制台递归渲染——分组折叠默认关闭，将来新增的组 / 参数自动出现
    DebugGroup* params_root = nullptr;
    /// "打开面板即暂停游戏"开关：控制台写、App 读（是否冻结卡带）
    bool* pause_when_open = nullptr;
};

/// ImGui 参数仪表盘（` 键呼出）。
/// 职责单一：观测与调节主机运行参数，不承担画面显示。
class DebugConsole {
public:
    /// 初始化 ImGui 上下文与后端。须已有当前 GL 上下文。
    /// font_files 是引擎字体链（主字体在前、CJK 回退在后）：用于给面板一份**带 CJK 字形**的字体
    /// （否则卡带注册的中文参数名会显示成 `????`）。为空则用 ImGui 默认字体。
    bool init(GLFWwindow* window, const std::vector<std::string>& font_files, std::string& err);
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

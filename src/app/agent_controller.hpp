#pragma once

#include "core/screen.hpp"

#include <functional>
#include <string>
#include <utility>
#include <vector>

namespace phos {

class ControlChannel;
class Input;
class Renderer;
class Shell;
struct HostContext;
class LayeredScreen;

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

/// 控制通道的语义侧（S1 阶段五从 App 抽出的独立部分）：
/// 单步回包 / frame.read 落地 / 按键定时释放 / 观察面 JSON。
/// **命令分发（execute_control）暂留 App**：它要触达 load_cart/eject/screenshot/input/
/// debug/quit 等十余个动作，按任务要求不硬拆；下一步用 AgentServices 回调注入再搬。
/// ControlChannel 的 I/O 与协议字段不在这里改。
class AgentController {
public:
    /// 单步推进完成：若有在途 time.step，用当前状态 JSON 回包并清 id。
    /// state_json 由 App 提供（它是 App 的完整观察面，不属于会话状态机）
    void complete_step(ControlChannel& channel, AgentSession& session,
                       const std::function<std::string()>& state_json) const;

    /// frame.read 的落地时机（画完一帧、swap 之前）：读回帧、统计亮度、可选写 PNG，
    /// 然后回包或回错误。无 renderer / read_frame 失败时按协议报错
    void complete_frame_read(ControlChannel& channel, AgentSession& session,
                             Renderer* renderer) const;

    // --- 单步 / 取消胶水（time.step、time.resume、frame.read、input.clear） ---
    /// 登记一次 time.step：一次最多 kMaxStepFrames 帧；已有在途请求则返回 false 并填 error
    bool begin_step(AgentSession& session, int frames, int request_id, std::string& error) const;
    /// time.resume：放弃在途 time.step（返回被放弃的请求 id，无则 -1），并回到实时推进
    int abandon_step(AgentSession& session) const;
    /// 登记 pending 的 frame.read（真正读回在渲染循环的画完一帧后）
    void begin_frame_read(AgentSession& session, int request_id, const std::string& path) const;
    /// input.clear：释放全部按键并清掉定时释放表
    void clear_pending_inputs(AgentSession& session, Input& input) const;

    /// 注入按键的定时释放：每个逻辑帧调一次
    void release_expired(AgentSession& session, Input& input) const;

    /// 一次 time.step 最多推进多少逻辑帧（防止超大帧数把主机卡住）
    static constexpr int kMaxStepFrames = 100000;

    // --- 观察面 JSON（agent 读取的状态视图） ---
    /// 图层清单 → JSON 数组（z 升序，与合成次序一致）
    static std::string layers_json(const LayeredScreen& layers);
    /// 卡带场景栈 → JSON 数组（底 → 顶）
    static std::string scenes_json(const HostContext& host);
    /// 屏幕文本 → JSON 字符串数组
    static std::string screen_lines_json(const Screen& screen);
    /// 磁盘上的卡带清单 JSON（carts.scan；与 --scan --json 共用 cart_json 实现）
    std::string carts_json(const std::string& cart_dir, bool english) const;
    /// 架子顺序 JSON（玩家眼里的"最近打开优先"，与磁盘扫描顺序不同）
    std::string shelf_json(const Shell& shell) const;
};

} // namespace phos

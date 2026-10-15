#pragma once

#include <memory>
#include <string>
#include <vector>

namespace phos {

/// 局域网联机传输层：TCP 星型房间（主机中继）+ UDP 局域网发现 + RTT 心跳。
///
/// 只做**传输**：连接生命周期、房间（对端列表）、收发消息、发现、可观测。
/// **不定义同步模型**——锁步 / 行动中继 / 主机权威由卡带自己在 `send`/`poll` 上实现
/// （见 docs/engine/networking.md）。未调用 host/join 时完全休眠（不占端口、不起线程）。
///
/// 线程模型：主线程只把消息压进/取出队列；网络 I/O 全在后台线程（`platform/socket` 的
/// select 循环）。与 core/audio、agent/control_channel 同一套"主线程不阻塞"的心智。
class Net {
public:
    /// 开房 / 加入参数。所有字段有合理默认。
    struct Options {
        int port = 7770;             // 游戏 TCP 端口
        std::string name = "player"; // 本端显示名
        int max_peers = 8;           // 主机最多接受的客人数
        int discovery_port = 45454;  // 局域网发现（UDP）端口
        bool discoverable = true;    // 主机是否响应发现查询
    };
    struct PeerInfo {
        int id = 0;
        std::string name;
        std::string address;
        double rtt_ms = -1.0;  // <0 = 未知
    };
    /// 一条收到的游戏消息。`data_json` 是 JSON 文本（可能为空串），由 API 层转成 Lua 表。
    struct Message {
        int from = 0;
        std::string kind;
        std::string data_json;
    };
    /// 连接变化事件（与游戏消息分开队列）。
    struct Event {
        std::string type;  // "connected" / "disconnected"
        int peer = 0;
        std::string name;
    };
    /// 发现到的一个房间。`open` = 房主是否还接受加入（开局后置 false）。
    struct Discovered {
        std::string name;
        std::string address;
        int port = 0;
        int players = 0;
        bool open = true;
    };

    Net();
    ~Net();
    Net(const Net&) = delete;
    Net& operator=(const Net&) = delete;

    /// 开始开房。失败返回 false 并填 err（端口占用等）。
    bool host(const Options& opts, std::string& err);
    /// 连接到主机。失败返回 false 并填 err。
    bool join(const std::string& address, const Options& opts, std::string& err);
    /// 离开 / 关房：关闭所有连接并停止后台线程。可重复调用。
    void stop();

    // --- 可观测 ---
    std::string status() const;   // "off" | "hosting" | "connecting" | "connected" | "error"
    std::string error() const;    // 最近一次错误串（无则 ""）
    bool hosting() const;
    bool connected() const;       // 主机=已开房；客人=已连上主机
    int self_id() const;
    int host_id() const;          // 主机对端 id（恒 1；未联机 0）
    int port() const;
    std::string local_ip() const;
    std::vector<PeerInfo> peers() const;

    // --- 消息 ---
    /// 发给对端 `to`（0 = 广播给除自己外的所有人）。data_json 为空串表示无数据。
    bool send(int to, const std::string& kind, const std::string& data_json);
    /// 取走自上次调用以来收到的消息（每次调用清空）。
    std::vector<Message> poll();
    /// 取走连接事件（每次调用清空）。
    std::vector<Event> poll_events();

    /// 广播查询并收集应答（有界阻塞，单位毫秒）。
    std::vector<Discovered> discover(int timeout_ms);

    /// 更新房间对外广播的信息（供"局域网发现"的应答用）。主机开局后调 `set_room_open(false)`，
    /// 搜索方就能在列表里看到"游戏中"并据此拒绝加入。只对主机的发现应答有意义。
    void set_room_name(const std::string& name);
    void set_room_open(bool open);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace phos

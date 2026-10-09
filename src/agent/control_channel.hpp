#pragma once

#include "agent/json_lite.hpp"

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace phos {

/// 一条来自控制通道的命令
struct ControlCommand {
    int id = 0;              // 请求 id（回包时原样带回；0 = 无 id 的通知）
    std::string name;        // 命令名
    json::Object args;       // 扁平参数对象
};

/// 本地控制通道：newline-delimited JSON over TCP（仅监听 127.0.0.1）。
///
/// 线程模型：一个后台线程负责 accept/recv，收到的命令行入队；
/// 主线程每帧 drain 队列并执行（宿主状态只在主线程被触碰）。
/// 回包与事件由任意线程发送，内部加锁串行化。
class ControlChannel {
public:
    ControlChannel();
    ~ControlChannel();
    ControlChannel(const ControlChannel&) = delete;
    ControlChannel& operator=(const ControlChannel&) = delete;

    /// 监听本地端口。失败返回 false 并填 err。
    bool start(uint16_t port, std::string& err);
    void stop();

    bool running() const;
    uint16_t port() const;
    /// 是否有客户端连接（agent 可用于判断握手完成）
    bool connected() const;

    /// 主线程每帧调用：取走并清空待处理命令
    std::vector<ControlCommand> take_commands();

    /// 回包：payload_json 为 JSON 片段（可为空串），形如 {"frame":12}
    void reply(int id, const std::string& payload_json);
    void reply_error(int id, const std::string& message);
    /// 主动事件推送（卡带装载/错误等）
    void send_event(const std::string& name, const std::string& payload_json);

private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace phos

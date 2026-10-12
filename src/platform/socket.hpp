#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace phos::net {

#if defined(_WIN32)
using socket_t = std::uintptr_t;
inline constexpr socket_t kInvalidSocket = static_cast<socket_t>(~static_cast<std::uintptr_t>(0));
#else
using socket_t = int;
inline constexpr socket_t kInvalidSocket = -1;
#endif

/// 进程级 socket 初始化（Winsock 走 WSAStartup，其余平台空操作）。可重复调用。
void socket_startup();

/// RAII socket 句柄：析构即关闭。移动语义，不可拷贝。
class Socket {
public:
    Socket() = default;
    explicit Socket(socket_t fd) : fd_(fd) {}
    ~Socket() { close(); }

    Socket(Socket&& other) noexcept : fd_(other.fd_) { other.fd_ = kInvalidSocket; }
    Socket& operator=(Socket&& other) noexcept {
        if (this != &other) {
            close();
            fd_ = other.fd_;
            other.fd_ = kInvalidSocket;
        }
        return *this;
    }
    Socket(const Socket&) = delete;
    Socket& operator=(const Socket&) = delete;

    bool valid() const { return fd_ != kInvalidSocket; }
    socket_t native() const { return fd_; }
    void close();
    /// 放弃所有权（调用方负责关闭）
    socket_t release() {
        const socket_t fd = fd_;
        fd_ = kInvalidSocket;
        return fd;
    }

private:
    socket_t fd_ = kInvalidSocket;
};

/// 创建 + 绑定 + 监听的 TCP 套接字（非阻塞）。失败返回无效 Socket 并填 err。
Socket tcp_listen(const std::string& bind_ip, int port, int backlog, std::string& err);
/// 连接主机（阻塞，带超时，成功后转为非阻塞）。失败返回无效 Socket 并填 err。
Socket tcp_connect(const std::string& host, int port, int connect_timeout_ms, std::string& err);
/// 接受一个连接（应在监听套接字可读时调用）。无连接时返回无效 Socket 且 err 为空。
Socket tcp_accept(const Socket& listener, std::string& err);
/// 设为非阻塞；失败填 err。
bool set_nonblocking(const Socket& s, std::string& err);
/// 关闭 Nagle 算法（小包低延迟）。
void set_nodelay(const Socket& s);
/// 允许地址快速重用（重启绑定）。
void set_reuse_addr(const Socket& s);
/// 发出去多少算多少（非阻塞）：返回写入字节数；-1 = 出错，0 = 写缓冲满（稍后重试）。
int send_some(const Socket& s, const void* data, int len);
/// 收多少算多少（非阻塞）。返回：>0 = 字节数；0 = 对端正常关闭；-1 = 出错；-2 = 暂无数据
/// （would-block）。调用方应把 -2 当作"这次没读到"而非断开——`select` 偶有假就绪。
int recv_some(const Socket& s, void* buffer, int len);

/// 打开 UDP 套接字并绑定到 bind_port（0 = 任意端口）；enable_broadcast 打开 SO_BROADCAST。
Socket udp_open(int bind_port, bool enable_broadcast, std::string& err);
/// 该 UDP 套接字实际绑定的端口（bind_port 传 0 时用它可以拿到内核分配的端口）。
int udp_local_port(const Socket& s);
/// 发送 UDP 数据报到 ip:port；返回字节数或 -1。
int udp_send_to(const Socket& s, const std::string& ip, int port, const void* data, int len);
/// 接收一个 UDP 数据报（不阻塞）；返回字节数或 -1，并填来源地址。
int udp_recv_from(const Socket& s, std::string& from_ip, int& from_port, void* buffer, int max_len);

/// select 就绪查询：返回在一组套接字里可读/可写的子集。timeout_ms < 0 表示阻塞等待。
struct SelectResult {
    std::vector<socket_t> readable;
    std::vector<socket_t> writable;
};
SelectResult select_wait(const std::vector<socket_t>& reads, const std::vector<socket_t>& writes,
                         int timeout_ms);

/// 本机在局域网里的 IPv4 地址（尽力而为：取第一个非回环地址；失败返回 "127.0.0.1"）。
std::string local_address();

/// 关闭套接字的一个方向（让正在等待它的 select 立刻返回）。关闭连接时用。
void shutdown_socket(const Socket& s);

} // namespace phos::net

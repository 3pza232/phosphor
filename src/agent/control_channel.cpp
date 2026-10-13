#include "agent/control_channel.hpp"

#include "core/log.hpp"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <netinet/in.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#include <atomic>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <thread>

namespace phos {

namespace {

#ifdef _WIN32
using Socket = SOCKET;
constexpr Socket kInvalidSocket = INVALID_SOCKET;

/// Winsock 生命周期（进程级一次）
struct WinsockGuard {
    WinsockGuard() {
        WSADATA data;
        WSAStartup(MAKEWORD(2, 2), &data);
    }
    ~WinsockGuard() { WSACleanup(); }
};

void ensure_winsock() {
    static WinsockGuard guard;
    (void)guard;
}

void close_socket(Socket s) {
    if (s != kInvalidSocket) closesocket(s);
}
#else
using Socket = int;
constexpr Socket kInvalidSocket = -1;

void ensure_winsock() {}
void close_socket(Socket s) {
    if (s != kInvalidSocket) ::close(s);
}
#endif

/// 单条命令队列的上限：主线程每帧才排空一次，突发命令不能无限堆积
constexpr size_t kMaxQueuedCommands = 1024;

/// 单行上限（含缓冲）：防御畸形/恶意输入把内存吃光
constexpr size_t kMaxLineBytes = 1u << 20;

/// 逐行切分（NDJSON）的结果
enum class LineResult { line, eof, too_long };

LineResult read_line(Socket socket, std::string& buffer, std::string& line) {
    while (true) {
        const size_t newline = buffer.find('\n');
        if (newline != std::string::npos) {
            line = buffer.substr(0, newline);
            buffer.erase(0, newline + 1);
            if (!line.empty() && line.back() == '\r') line.pop_back();
            return LineResult::line;
        }
        if (buffer.size() > kMaxLineBytes) return LineResult::too_long;
        char chunk[1024];
        const int received = ::recv(socket, chunk, sizeof(chunk), 0);
        if (received <= 0) return LineResult::eof;
        buffer.append(chunk, static_cast<size_t>(received));
    }
}

} // namespace

struct ControlChannel::Impl {
    Socket listener = kInvalidSocket;
    Socket client = kInvalidSocket;
    uint16_t port = 0;
    std::atomic<bool> running{false};
    std::atomic<bool> stopping{false};
    std::atomic<bool> connected{false};
    std::thread thread;

    std::mutex queue_mutex;
    std::vector<ControlCommand> queue;

    std::mutex send_mutex;
    /// 保护 client **句柄本身**（不覆盖阻塞调用）：后台线程换连接、stop() 关闭连接、
    /// 发送方取句柄都要走它。不这么做会出现"关的是上一个连接的句柄"这类竞态
    std::mutex client_mutex;

    Socket current_client() {
        std::lock_guard<std::mutex> lock(client_mutex);
        return client;
    }

    void send_line(const std::string& line) {
        const Socket target = current_client();  // 取一次句柄：发送期间连接可能已被换掉
        if (target == kInvalidSocket) return;
        std::lock_guard<std::mutex> lock(send_mutex);
        const std::string payload = line + "\n";
        size_t sent = 0;
        while (sent < payload.size()) {
            // 发送前先看可写：对端只连不读时 TCP 发送缓冲会满、send 会一直阻塞——
            // 而这条路径跑在**主线程**上，堵住就等于整个主循环停摆。宁可丢弃这段回包
            fd_set writable;
            FD_ZERO(&writable);
            FD_SET(target, &writable);
            timeval timeout{0, 200 * 1000};  // 200ms
#ifdef _WIN32
            const int ready = ::select(0, nullptr, &writable, nullptr, &timeout);
#else
            const int ready = ::select(target + 1, nullptr, &writable, nullptr, &timeout);
#endif
            if (ready <= 0) {
                log::warn("control: reply dropped (peer not reading)");
                return;
            }
            const int written = ::send(target, payload.data() + sent,
                                       static_cast<int>(payload.size() - sent), 0);
            if (written <= 0) return;
            sent += static_cast<size_t>(written);
        }
    }

    void handle_line(const std::string& line) {
        if (line.empty()) return;

        ControlCommand command;
        std::string err;
        if (!command.args.parse(line, err)) {
            send_line("{\"id\":0,\"ok\":false,\"error\":" +
                      json::quote("malformed command: " + err) + "}");
            return;
        }
        command.id = command.args.integer("id", 0);
        command.name = command.args.str("cmd");
        if (command.name.empty()) {
            send_line("{\"id\":" + std::to_string(command.id) +
                      ",\"ok\":false,\"error\":\"missing 'cmd'\"}");
            return;
        }
        std::lock_guard<std::mutex> lock(queue_mutex);
        if (queue.size() >= kMaxQueuedCommands) {
            // 队列满（命令突发而来、主线程还没排空）：明确回错，而不是无限堆积吃内存
            send_line("{\"id\":" + std::to_string(command.id) +
                      ",\"ok\":false,\"error\":\"command queue full\"}");
            return;
        }
        queue.push_back(std::move(command));
    }

    /// 后台线程：接受连接 → 逐行读取 → 断线后回到 accept
    void serve() {
        while (!stopping.load()) {
            sockaddr_in address{};
            address.sin_family = AF_INET;
            address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
            address.sin_port = htons(port);

#ifdef _WIN32
            int addr_len = sizeof(address);
#else
            socklen_t addr_len = sizeof(address);
#endif
            Socket accepted = ::accept(listener, reinterpret_cast<sockaddr*>(&address), &addr_len);
            if (accepted == kInvalidSocket) break;  // 监听套接字已关闭

            {
                std::lock_guard<std::mutex> lock(client_mutex);
                client = accepted;
            }
            connected.store(true);
            send_line("{\"event\":\"hello\",\"protocol\":1,\"port\":" + std::to_string(port) + "}");

            std::string buffer;
            std::string line;
            bool keep = true;
            while (!stopping.load() && keep) {
                switch (read_line(accepted, buffer, line)) {
                    case LineResult::line:
                        handle_line(line);
                        break;
                    case LineResult::too_long:
                        // 单行超限：回一条错误再断开——静默丢弃会让对端以为命令被吞了
                        send_line("{\"id\":0,\"ok\":false,\"error\":\"line too long\"}");
                        keep = false;
                        break;
                    case LineResult::eof:
                        keep = false;
                        break;
                }
            }

            connected.store(false);
            // 关闭权归"仍持有该句柄的一方"：stop() 可能已经抢先收走并关掉了它
            bool mine = false;
            {
                std::lock_guard<std::mutex> lock(client_mutex);
                if (client == accepted) {
                    client = kInvalidSocket;
                    mine = true;
                }
            }
            if (mine) close_socket(accepted);
        }
    }
};

ControlChannel::ControlChannel() : impl_(std::make_unique<Impl>()) {}

ControlChannel::~ControlChannel() { stop(); }

bool ControlChannel::start(uint16_t port, std::string& err) {
    if (impl_->running.load()) return true;
    ensure_winsock();

    impl_->port = port;
    impl_->listener = ::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
    if (impl_->listener == kInvalidSocket) {
        err = "socket() failed";
        return false;
    }

    // 允许快速重启绑定
    int reuse = 1;
    ::setsockopt(impl_->listener, SOL_SOCKET, SO_REUSEADDR,
                 reinterpret_cast<const char*>(&reuse), sizeof(reuse));

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);  // 仅本机：控制通道不对外暴露
    address.sin_port = htons(port);

    if (::bind(impl_->listener, reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        err = "bind failed on port " + std::to_string(port);
        close_socket(impl_->listener);
        impl_->listener = kInvalidSocket;
        return false;
    }
    if (::listen(impl_->listener, 1) != 0) {
        err = "listen failed on port " + std::to_string(port);
        close_socket(impl_->listener);
        impl_->listener = kInvalidSocket;
        return false;
    }

    impl_->stopping.store(false);
    impl_->running.store(true);
    impl_->thread = std::thread([this] { impl_->serve(); });
    return true;
}

void ControlChannel::stop() {
    if (!impl_ || !impl_->running.load()) return;

    impl_->stopping.store(true);
    Socket client = kInvalidSocket;
    {
        std::lock_guard<std::mutex> lock(impl_->client_mutex);
        client = impl_->client;
        impl_->client = kInvalidSocket;  // 先摘牌：后台线程不会再重复关它
    }
    if (client != kInvalidSocket) {
        ::shutdown(client, 2);  // 让阻塞中的 recv 立即返回
        close_socket(client);
    }
    if (impl_->listener != kInvalidSocket) {
        close_socket(impl_->listener);  // 让阻塞中的 accept 立即返回
        impl_->listener = kInvalidSocket;
    }
    if (impl_->thread.joinable()) impl_->thread.join();

    impl_->running.store(false);
    impl_->connected.store(false);
}

bool ControlChannel::running() const { return impl_ && impl_->running.load(); }

bool ControlChannel::connected() const { return impl_ && impl_->connected.load(); }

uint16_t ControlChannel::port() const { return impl_ ? impl_->port : 0; }

std::vector<ControlCommand> ControlChannel::take_commands() {
    std::vector<ControlCommand> out;
    if (!impl_) return out;
    std::lock_guard<std::mutex> lock(impl_->queue_mutex);
    out.swap(impl_->queue);
    return out;
}

void ControlChannel::reply(int id, const std::string& payload_json) {
    if (!impl_) return;
    std::string line = "{\"id\":" + std::to_string(id) + ",\"ok\":true";
    if (!payload_json.empty()) line += "," + payload_json;
    line += "}";
    impl_->send_line(line);
}

void ControlChannel::reply_error(int id, const std::string& message) {
    if (!impl_) return;
    impl_->send_line("{\"id\":" + std::to_string(id) + ",\"ok\":false,\"error\":" +
                     json::quote(message) + "}");
}

void ControlChannel::send_event(const std::string& name, const std::string& payload_json) {
    if (!impl_) return;
    std::string line = "{\"event\":" + json::quote(name);
    if (!payload_json.empty()) line += "," + payload_json;
    line += "}";
    impl_->send_line(line);
}

} // namespace phos

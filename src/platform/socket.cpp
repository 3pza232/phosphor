#include "platform/socket.hpp"

#ifdef _WIN32
#include <winsock2.h>
#include <ws2tcpip.h>
#else
#include <arpa/inet.h>
#include <cerrno>
#include <fcntl.h>
#include <netdb.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/socket.h>
#include <unistd.h>
#endif

#include <cstring>

namespace phos::net {

namespace {

/// 上一次 socket 调用的错误码 → 人可读的短串
std::string last_socket_error() {
#ifdef _WIN32
    return "wsa error " + std::to_string(WSAGetLastError());
#else
    return std::string(std::strerror(errno));
#endif
}

bool would_block() {
#ifdef _WIN32
    return WSAGetLastError() == WSAEWOULDBLOCK;
#else
    return errno == EWOULDBLOCK || errno == EAGAIN;
#endif
}

void close_native(socket_t fd) {
    if (fd == kInvalidSocket) return;
#ifdef _WIN32
    ::closesocket(fd);
#else
    ::close(fd);
#endif
}

/// 关闭套接字的某方向（让阻塞/select 立刻返回）。Windows 无 SHUT_RDWR 常量差异。
void shutdown_native(socket_t fd) {
    if (fd == kInvalidSocket) return;
#ifdef _WIN32
    ::shutdown(fd, SD_BOTH);
#else
    ::shutdown(fd, SHUT_RDWR);
#endif
}

} // namespace

void Socket::close() {
    close_native(fd_);
    fd_ = kInvalidSocket;
}

void socket_startup() {
#ifdef _WIN32
    static const bool once = [] {
        WSADATA data;
        WSAStartup(MAKEWORD(2, 2), &data);
        return true;
    }();
    (void)once;
#endif
}

bool set_nonblocking(const Socket& s, std::string& err) {
#ifdef _WIN32
    u_long mode = 1;
    if (ioctlsocket(s.native(), FIONBIO, &mode) != 0) {
        err = "ioctlsocket FIONBIO failed: " + last_socket_error();
        return false;
    }
#else
    const int flags = fcntl(s.native(), F_GETFL, 0);
    if (flags < 0 || fcntl(s.native(), F_SETFL, flags | O_NONBLOCK) < 0) {
        err = "fcntl O_NONBLOCK failed: " + last_socket_error();
        return false;
    }
#endif
    return true;
}

void set_nodelay(const Socket& s) {
    const int one = 1;
    ::setsockopt(s.native(), IPPROTO_TCP, TCP_NODELAY,
                 reinterpret_cast<const char*>(&one), sizeof(one));
}

void set_reuse_addr(const Socket& s) {
    const int one = 1;
    ::setsockopt(s.native(), SOL_SOCKET, SO_REUSEADDR,
                 reinterpret_cast<const char*>(&one), sizeof(one));
}

Socket tcp_listen(const std::string& bind_ip, int port, int backlog, std::string& err) {
    socket_startup();
    Socket s(::socket(AF_INET, SOCK_STREAM, IPPROTO_TCP));
    if (!s.valid()) {
        err = "socket() failed: " + last_socket_error();
        return {};
    }
    set_reuse_addr(s);

    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_port = htons(static_cast<unsigned short>(port));
    const std::string bind = bind_ip.empty() ? "0.0.0.0" : bind_ip;
    if (::inet_pton(AF_INET, bind.c_str(), &address.sin_addr) != 1) {
        err = "bad bind address: " + bind;
        return {};
    }
    if (::bind(s.native(), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        err = "bind " + bind + ":" + std::to_string(port) + " failed: " + last_socket_error();
        return {};
    }
    if (::listen(s.native(), backlog) != 0) {
        err = "listen failed: " + last_socket_error();
        return {};
    }
    if (!set_nonblocking(s, err)) return {};
    return s;
}

Socket tcp_connect(const std::string& host, int port, int connect_timeout_ms, std::string& err) {
    socket_startup();
    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    hints.ai_protocol = IPPROTO_TCP;
    addrinfo* results = nullptr;
    const std::string port_str = std::to_string(port);
    if (::getaddrinfo(host.c_str(), port_str.c_str(), &hints, &results) != 0 || !results) {
        err = "cannot resolve host: " + host;
        return {};
    }

    Socket s;
    for (addrinfo* it = results; it != nullptr; it = it->ai_next) {
        Socket candidate(::socket(it->ai_family, it->ai_socktype, it->ai_protocol));
        if (!candidate.valid()) continue;
        set_nodelay(candidate);
        std::string nberr;
        if (!set_nonblocking(candidate, nberr)) continue;

        const int rc = ::connect(candidate.native(), it->ai_addr, static_cast<int>(it->ai_addrlen));
        if (rc != 0 && !would_block()) {
            continue;  // 立刻失败：试下一个地址
        }
        if (rc != 0) {
            // 进行中：等可写，再看 SO_ERROR
            SelectResult ready = select_wait({}, {candidate.native()}, connect_timeout_ms);
            if (ready.writable.empty()) {
                continue;
            }
            int so_error = 0;
#ifdef _WIN32
            int len = sizeof(so_error);
#else
            socklen_t len = sizeof(so_error);
#endif
            ::getsockopt(candidate.native(), SOL_SOCKET, SO_ERROR,
                         reinterpret_cast<char*>(&so_error), &len);
            if (so_error != 0) {
                continue;
            }
        }
        s = std::move(candidate);
        break;
    }
    ::freeaddrinfo(results);
    if (!s.valid()) {
        err = "connect " + host + ":" + std::to_string(port) + " failed";
    }
    return s;
}

Socket tcp_accept(const Socket& listener, std::string& err) {
    sockaddr_in address{};
#ifdef _WIN32
    int addr_len = sizeof(address);
#else
    socklen_t addr_len = sizeof(address);
#endif
    Socket client(::accept(listener.native(), reinterpret_cast<sockaddr*>(&address), &addr_len));
    if (!client.valid()) {
        if (!would_block()) err = "accept failed: " + last_socket_error();
        return {};
    }
    set_nodelay(client);
    std::string nberr;
    set_nonblocking(client, nberr);  // 失败就用阻塞的，问题不大
    return client;
}

int send_some(const Socket& s, const void* data, int len) {
#ifdef _WIN32
    const int n = ::send(s.native(), static_cast<const char*>(data), len, 0);
#else
    const ssize_t n = ::send(s.native(), data, static_cast<size_t>(len), 0);
#endif
    if (n < 0 && would_block()) return 0;
    if (n < 0) return -1;
    return static_cast<int>(n);
}

int recv_some(const Socket& s, void* buffer, int len) {
#ifdef _WIN32
    const int n = ::recv(s.native(), static_cast<char*>(buffer), len, 0);
#else
    const ssize_t n = ::recv(s.native(), buffer, static_cast<size_t>(len), 0);
#endif
    if (n < 0 && would_block()) return -2;  // 暂无数据（非错误）
    if (n < 0) return -1;
    return static_cast<int>(n);
}

Socket udp_open(int bind_port, bool enable_broadcast, std::string& err) {
    socket_startup();
    Socket s(::socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP));
    if (!s.valid()) {
        err = "udp socket() failed: " + last_socket_error();
        return {};
    }
    set_reuse_addr(s);
    if (enable_broadcast) {
        const int one = 1;
        ::setsockopt(s.native(), SOL_SOCKET, SO_BROADCAST,
                     reinterpret_cast<const char*>(&one), sizeof(one));
    }
    sockaddr_in address{};
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_ANY);
    address.sin_port = htons(static_cast<unsigned short>(bind_port));
    if (::bind(s.native(), reinterpret_cast<sockaddr*>(&address), sizeof(address)) != 0) {
        err = "udp bind :" + std::to_string(bind_port) + " failed: " + last_socket_error();
        return {};
    }
    if (!set_nonblocking(s, err)) return {};
    return s;
}

int udp_local_port(const Socket& s) {
    sockaddr_in address{};
#ifdef _WIN32
    int len = sizeof(address);
#else
    socklen_t len = sizeof(address);
#endif
    if (::getsockname(s.native(), reinterpret_cast<sockaddr*>(&address), &len) != 0) return 0;
    return ntohs(address.sin_port);
}

int udp_send_to(const Socket& s, const std::string& ip, int port, const void* data, int len) {
    sockaddr_in to{};
    to.sin_family = AF_INET;
    to.sin_port = htons(static_cast<unsigned short>(port));
    if (::inet_pton(AF_INET, ip.c_str(), &to.sin_addr) != 1) return -1;
#ifdef _WIN32
    const int n = ::sendto(s.native(), static_cast<const char*>(data), len, 0,
                           reinterpret_cast<sockaddr*>(&to), sizeof(to));
#else
    const ssize_t n = ::sendto(s.native(), data, static_cast<size_t>(len), 0,
                               reinterpret_cast<sockaddr*>(&to), sizeof(to));
#endif
    return static_cast<int>(n);
}

int udp_recv_from(const Socket& s, std::string& from_ip, int& from_port, void* buffer, int max_len) {
    sockaddr_in from{};
#ifdef _WIN32
    int from_len = sizeof(from);
#else
    socklen_t from_len = sizeof(from);
#endif
#ifdef _WIN32
    const int n = ::recvfrom(s.native(), static_cast<char*>(buffer), max_len, 0,
                             reinterpret_cast<sockaddr*>(&from), &from_len);
#else
    const ssize_t n = ::recvfrom(s.native(), buffer, static_cast<size_t>(max_len), 0,
                                 reinterpret_cast<sockaddr*>(&from), &from_len);
#endif
    if (n < 0) return -1;
    char text[INET_ADDRSTRLEN] = {0};
    inet_ntop(AF_INET, &from.sin_addr, text, sizeof(text));
    from_ip = text;
    from_port = ntohs(from.sin_port);
    return static_cast<int>(n);
}

SelectResult select_wait(const std::vector<socket_t>& reads, const std::vector<socket_t>& writes,
                         int timeout_ms) {
    SelectResult result;
    fd_set read_set;
    fd_set write_set;
    FD_ZERO(&read_set);
    FD_ZERO(&write_set);
    socket_t max_fd = 0;
    for (socket_t fd : reads) {
        FD_SET(fd, &read_set);
        if (fd > max_fd) max_fd = fd;
    }
    for (socket_t fd : writes) {
        FD_SET(fd, &write_set);
        if (fd > max_fd) max_fd = fd;
    }

    timeval tv{};
    timeval* tv_ptr = nullptr;
    if (timeout_ms >= 0) {
        tv.tv_sec = timeout_ms / 1000;
        tv.tv_usec = (timeout_ms % 1000) * 1000;
        tv_ptr = &tv;
    }

#ifdef _WIN32
    const int rc = ::select(0, &read_set, &write_set, nullptr, tv_ptr);
#else
    const int rc = ::select(static_cast<int>(max_fd) + 1, &read_set, &write_set, nullptr, tv_ptr);
#endif
    if (rc <= 0) return result;

    for (socket_t fd : reads)
        if (FD_ISSET(fd, &read_set)) result.readable.push_back(fd);
    for (socket_t fd : writes)
        if (FD_ISSET(fd, &write_set)) result.writable.push_back(fd);
    return result;
}

std::string local_address() {
    socket_startup();
    char hostname[256] = {0};
    if (::gethostname(hostname, sizeof(hostname) - 1) != 0) return "127.0.0.1";

    addrinfo hints{};
    hints.ai_family = AF_INET;
    hints.ai_socktype = SOCK_STREAM;
    addrinfo* results = nullptr;
    if (::getaddrinfo(hostname, nullptr, &hints, &results) != 0 || !results) {
        return "127.0.0.1";
    }
    std::string fallback = "127.0.0.1";
    for (addrinfo* it = results; it != nullptr; it = it->ai_next) {
        auto* address = reinterpret_cast<sockaddr_in*>(it->ai_addr);
        char text[INET_ADDRSTRLEN] = {0};
        inet_ntop(AF_INET, &address->sin_addr, text, sizeof(text));
        const std::string ip = text;
        if (ip.rfind("127.", 0) != 0 && ip != "0.0.0.0") {
            fallback = ip;
            break;
        }
    }
    ::freeaddrinfo(results);
    return fallback;
}

// 供 Net 在关闭对端时立刻打断 select —— 与 platform/socket 同处，避免外部直接碰系统调用
void shutdown_socket(const Socket& s) { shutdown_native(s.native()); }

} // namespace phos::net

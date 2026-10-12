#include "net/net.hpp"

#include "core/json_lite.hpp"
#include "core/log.hpp"
#include "platform/socket.hpp"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <deque>
#include <map>
#include <mutex>
#include <sstream>
#include <thread>

namespace phos {

namespace {

constexpr int kRecvChunk = 4096;
constexpr int kMaxFrame = 16 * 1024;      // 单帧上限：坏客户端不能撑爆内存
constexpr size_t kMaxIncoming = 1024;     // 收件队列上限：满了丢最旧
constexpr int kSelectTimeoutMs = 20;      // select 超时：够短以保响应，够长以省 CPU
constexpr int kPingIntervalMs = 1000;     // 心跳间隔（同时算 RTT、判掉线）
constexpr int kPeerTimeoutMs = 5000;      // 连续这么久没心跳就判掉线
constexpr const char* kMagic = "PHOSPT";  // 发现报文标识

constexpr int kHostId = 1;                // 主机对端 id 恒为 1

void append_u32_be(std::string& out, std::uint32_t value) {
    out.push_back(static_cast<char>((value >> 24) & 0xFF));
    out.push_back(static_cast<char>((value >> 16) & 0xFF));
    out.push_back(static_cast<char>((value >> 8) & 0xFF));
    out.push_back(static_cast<char>(value & 0xFF));
}

std::uint32_t read_u32_be(const unsigned char* p) {
    return (static_cast<std::uint32_t>(p[0]) << 24) | (static_cast<std::uint32_t>(p[1]) << 16) |
           (static_cast<std::uint32_t>(p[2]) << 8) | static_cast<std::uint32_t>(p[3]);
}

/// [uint32 大端长度][载荷]
std::string make_frame(const std::string& payload) {
    std::string frame;
    frame.reserve(payload.size() + 4);
    append_u32_be(frame, static_cast<std::uint32_t>(payload.size()));
    frame += payload;
    return frame;
}

/// 信封（第一段）与数据（第二段）用换行分隔：信封是紧凑 JSON（无裸换行），
/// 数据段可以含数组/嵌套——原样透传，不做二次解析。
std::string make_payload(const std::string& envelope_json, const std::string& data_json) {
    return envelope_json + "\n" + data_json;
}

} // namespace

struct Net::Impl {
    enum class Role { off, hosting, connecting, connected };

    struct Peer {
        int id = 0;
        net::Socket sock;
        std::string name;
        std::string address;
        std::string inbuf;                  // 接收分帧缓冲
        std::vector<unsigned char> outbuf;  // 待发送字节
        bool hello = false;                 // 是否已完成握手
        double rtt_ms = -1.0;
        std::uint32_t ping_seq = 0;
        bool ping_pending = false;
        std::chrono::steady_clock::time_point ping_sent{};
        std::chrono::steady_clock::time_point last_seen{};
    };
    struct Out {
        int to = 0;
        std::string kind;
        std::string data;
    };

    Options opts;
    // role / self_id 会被 worker（握手完成）与主线程（status/connected）同时读写：用原子
    std::atomic<Role> role{Role::off};
    std::atomic<int> self_id{0};
    int local_port = 0;
    // 房间对外广播的信息（发现应答用）：可被主机在开局时改（open=false）
    mutable std::mutex room_mtx;
    std::string room_name;
    bool room_open = true;

    // worker 独占：连接与缓冲
    net::Socket listener;
    net::Socket udp;
    // 唤醒套接字：主线程 send 入队后往它写一个字节，把卡在 select 里的 worker 立刻叫醒。
    // 没有它，入队的包最多要等一个 kSelectTimeoutMs 才上路；对"每帧都要往对端发一次"
    // 这类延迟敏感用法，这点延迟可能超过一个逻辑帧，表现为周期性掉帧。超时此时退化为空闲兜底。
    net::Socket wake;
    int wake_port = 0;
    std::map<int, Peer> conns;     // 主机：各客人；客人：{1: 主机}
    int next_id = 2;

    std::thread worker;
    std::atomic<bool> running{false};

    // 主线程可见快照
    mutable std::mutex state_mtx;
    std::string last_error;
    std::map<int, PeerInfo> peer_snapshot;

    std::mutex in_mtx;
    std::deque<Message> incoming;
    std::mutex ev_mtx;
    std::deque<Event> events;
    std::mutex out_mtx;
    std::deque<Out> outgoing;

    // ---- 主线程可见快照维护（worker 调用，持 state_mtx） ----
    void refresh_snapshot() {
        std::lock_guard<std::mutex> lock(state_mtx);
        peer_snapshot.clear();
        for (const auto& [id, peer] : conns) {
            if (id == self_id) continue;
            PeerInfo info;
            info.id = id;
            info.name = peer.name;
            info.address = peer.address;
            info.rtt_ms = peer.rtt_ms;
            peer_snapshot[id] = info;
        }
    }
    void set_error(const std::string& message) {
        std::lock_guard<std::mutex> lock(state_mtx);
        last_error = message;
    }
    void push_message(int from, const std::string& kind, const std::string& data) {
        std::lock_guard<std::mutex> lock(in_mtx);
        if (incoming.size() >= kMaxIncoming) incoming.pop_front();
        incoming.push_back(Message{from, kind, data});
    }
    void push_event(const std::string& type, int peer, const std::string& name) {
        std::lock_guard<std::mutex> lock(ev_mtx);
        events.push_back(Event{type, peer, name});
    }

    // ---- 发送 ----
    void queue_to(Peer& peer, const std::string& payload) {
        const std::string frame = make_frame(payload);
        size_t sent = 0;
        while (sent < frame.size()) {
            const int n = net::send_some(peer.sock, frame.data() + sent,
                                         static_cast<int>(frame.size() - sent));
            if (n <= 0) break;
            sent += static_cast<size_t>(n);
        }
        if (sent < frame.size()) {
            peer.outbuf.insert(peer.outbuf.end(), frame.begin() + static_cast<long>(sent),
                               frame.end());
        }
    }

    void broadcast_raw(int except_id, const std::string& payload) {
        for (auto& [id, peer] : conns) {
            if (id == except_id || !peer.hello) continue;
            queue_to(peer, payload);
        }
    }

    // 主线程入队后叫醒 worker（见 wake 成员注释）。非阻塞、幂等：多叫一次只是多读一个字节
    void wake_worker() {
        if (wake.valid() && wake_port > 0) {
            const char one = 1;
            net::udp_send_to(wake, "127.0.0.1", wake_port, &one, 1);
        }
    }

    // ---- 信封处理 ----
    std::string route_msg_envelope(int from, int to, const std::string& kind) {
        std::ostringstream env;
        env << "{\"t\":\"msg\",\"from\":" << from << ",\"k\":" << json::quote(kind) << "}";
        return env.str();
    }

    void forward_from(int from, int to, const std::string& kind, const std::string& data) {
        if (to == 0) {
            // 广播给除发送者外的所有人
            for (auto& [id, peer] : conns) {
                if (id == from || !peer.hello || id == self_id) continue;
                queue_to(peer, make_payload(route_msg_envelope(from, 0, kind), data));
            }
            if (from != self_id) push_message(from, kind, data);
        } else if (to == self_id || to == kHostId) {
            push_message(from, kind, data);  // 发给主机（本机）或自己
        } else {
            const auto it = conns.find(to);
            if (it != conns.end() && it->second.hello) {
                queue_to(it->second, make_payload(route_msg_envelope(from, to, kind), data));
            }
        }
    }

    void handle_envelope(int peer_id, const std::string& payload) {
        const size_t split = payload.find('\n');
        const std::string envelope = split == std::string::npos ? payload : payload.substr(0, split);
        const std::string data = split == std::string::npos ? std::string() : payload.substr(split + 1);

        json::Object env;
        std::string err;
        if (!env.parse(envelope, err)) {
            log::warn("net: bad envelope dropped: " + err);
            return;
        }
        const std::string type = env.str("t");

        if (type == "hello" && role == Role::hosting) {
            auto it = conns.find(peer_id);
            if (it == conns.end()) return;
            it->second.name = env.str("name", "player");
            it->second.hello = true;
            // 告知对方它的 id
            {
                std::ostringstream welcome;
                welcome << "{\"t\":\"welcome\",\"id\":" << peer_id << "}";
                queue_to(it->second, make_payload(welcome.str(), ""));
            }
            // 向全体广播新客人，并把已有客人告诉新客人
            {
                std::ostringstream add;
                add << "{\"t\":\"peer_add\",\"id\":" << peer_id << ",\"name\":"
                    << json::quote(it->second.name) << "}";
                broadcast_raw(peer_id, make_payload(add.str(), ""));
            }
            for (auto& [id, peer] : conns) {
                if (id == peer_id || !peer.hello || id == kHostId) continue;
                std::ostringstream add;
                add << "{\"t\":\"peer_add\",\"id\":" << id << ",\"name\":"
                    << json::quote(peer.name) << "}";
                queue_to(it->second, make_payload(add.str(), ""));
            }
            push_event("connected", peer_id, it->second.name);
            refresh_snapshot();
            return;
        }
        if (type == "welcome" && role == Role::connecting) {
            self_id = env.integer("id", 0);
            role = Role::connected;
            if (auto it = conns.find(kHostId); it != conns.end()) it->second.hello = true;
            push_event("connected", kHostId, "host");
            refresh_snapshot();
            return;
        }
        if (type == "peer_add" && role == Role::connected) {
            const int id = env.integer("id", 0);
            if (id == 0 || id == self_id) return;
            Peer peer;
            peer.id = id;
            peer.name = env.str("name", "player");
            peer.hello = true;
            peer.last_seen = std::chrono::steady_clock::now();
            conns[id] = std::move(peer);
            push_event("connected", id, conns[id].name);
            refresh_snapshot();
            return;
        }
        if (type == "peer_remove" && role == Role::connected) {
            const int id = env.integer("id", 0);
            if (auto it = conns.find(id); it != conns.end()) {
                push_event("disconnected", id, it->second.name);
                conns.erase(it);
                refresh_snapshot();
            }
            return;
        }
        if (type == "msg") {
            if (role == Role::hosting) {
                const int to = env.integer("to", 0);
                forward_from(peer_id, to, env.str("k"), data);
            } else {
                push_message(env.integer("from", 0), env.str("k"), data);
            }
            return;
        }
        if (type == "ping") {
            std::ostringstream pong;
            pong << "{\"t\":\"pong\",\"seq\":" << env.integer("seq", 0) << "}";
            if (auto it = conns.find(peer_id); it != conns.end())
                queue_to(it->second, make_payload(pong.str(), ""));
            return;
        }
        if (type == "pong") {
            if (auto it = conns.find(peer_id); it != conns.end() && it->second.ping_pending) {
                const auto elapsed = std::chrono::steady_clock::now() - it->second.ping_sent;
                it->second.rtt_ms =
                    std::chrono::duration<double, std::milli>(elapsed).count();
                it->second.ping_pending = false;
            }
            return;
        }
        // 其余类型忽略
    }

    void drop_peer(int id, bool notify) {
        const auto it = conns.find(id);
        if (it == conns.end()) return;
        const std::string name = it->second.name;
        net::shutdown_socket(it->second.sock);
        it->second.sock.close();
        conns.erase(it);
        if (role == Role::hosting) {
            std::ostringstream rem;
            rem << "{\"t\":\"peer_remove\",\"id\":" << id << "}";
            broadcast_raw(id, make_payload(rem.str(), ""));
        }
        if (notify) push_event("disconnected", id, name);
        refresh_snapshot();
    }

    void read_peer(Peer& peer) {
        unsigned char buffer[kRecvChunk];
        const int n = net::recv_some(peer.sock, buffer, kRecvChunk);
        if (n == 0) {
            drop_peer(peer.id, role != Role::connecting);
            return;
        }
        if (n == -2) return;  // 假就绪（select 说可读却无数据）：跳过，别当掉线
        if (n < 0) {
            drop_peer(peer.id, role != Role::connecting);
            return;
        }
        peer.last_seen = std::chrono::steady_clock::now();
        peer.inbuf.append(reinterpret_cast<char*>(buffer), static_cast<size_t>(n));

        // 分帧
        while (peer.inbuf.size() >= 4) {
            const auto* p = reinterpret_cast<const unsigned char*>(peer.inbuf.data());
            const std::uint32_t len = read_u32_be(p);
            if (len == 0 || len > kMaxFrame) {
                log::warn("net: frame length out of range; dropping peer");
                drop_peer(peer.id, true);
                return;
            }
            if (peer.inbuf.size() < 4 + len) break;
            const std::string payload = peer.inbuf.substr(4, len);
            peer.inbuf.erase(0, 4 + len);
            handle_envelope(peer.id, payload);
            // handle_envelope 可能移除了这个 peer（peer 引用失效）：重新查找
            if (conns.find(peer.id) == conns.end()) return;
        }
    }

    void drain_outgoing() {
        std::deque<Out> batch;
        {
            std::lock_guard<std::mutex> lock(out_mtx);
            batch.swap(outgoing);
        }
        for (const Out& out : batch) {
            if (role == Role::hosting) {
                forward_from(self_id, out.to, out.kind, out.data);
            } else if (role == Role::connected) {
                if (out.to == self_id) {
                    push_message(self_id, out.kind, out.data);
                    continue;
                }
                auto it = conns.find(kHostId);
                if (it == conns.end()) continue;
                std::ostringstream env;
                env << "{\"t\":\"msg\",\"to\":" << out.to << ",\"k\":" << json::quote(out.kind)
                    << "}";
                queue_to(it->second, make_payload(env.str(), out.data));
            }
        }
    }

    void tick_pings() {
        const auto now = std::chrono::steady_clock::now();
        for (auto& [id, peer] : conns) {
            // 只对**真正建立连接**的对端做心跳/判超时。星型拓扑里客人也会从 peer_add 得知
            // 其他客人，那些"已知对端"没有自己的 socket（消息经主机转发）；对它们发心跳
            // 永远收不到 pong，只会被误判掉线。读写循环同理，都按有没有 socket 区分。
            if (!peer.sock.valid()) continue;
            if (!peer.hello) continue;
            if (peer.ping_pending) {
                if (now - peer.ping_sent > std::chrono::milliseconds(kPeerTimeoutMs)) {
                    log::warn("net: peer " + std::to_string(id) + " timed out");
                    drop_peer(id, true);
                    return;  // conns 已变，下一轮再处理
                }
                continue;
            }
            if (now - peer.last_seen < std::chrono::milliseconds(kPingIntervalMs)) continue;
            peer.ping_seq += 1;
            peer.ping_pending = true;
            peer.ping_sent = now;
            std::ostringstream ping;
            ping << "{\"t\":\"ping\",\"seq\":" << peer.ping_seq << "}";
            queue_to(peer, make_payload(ping.str(), ""));
        }
    }

    void handle_udp() {
        char buffer[1024];
        std::string from_ip;
        int from_port = 0;
        const int n = net::udp_recv_from(udp, from_ip, from_port, buffer, sizeof(buffer));
        if (n <= 0) return;
        json::Object query;
        std::string err;
        if (!query.parse(std::string(buffer, static_cast<size_t>(n)), err)) return;
        if (query.str("magic") != kMagic) return;
        if (query.integer("q", 0) != 1 || !opts.discoverable) return;

        int players = 1;
        for (const auto& [id, peer] : conns)
            if (peer.hello) players += 1;
        std::string room_name;
        bool room_open = true;
        {
            std::lock_guard<std::mutex> lock(room_mtx);
            room_name = this->room_name;
            room_open = this->room_open;
        }
        std::ostringstream beacon;
        beacon << "{\"magic\":" << json::quote(kMagic) << ",\"name\":" << json::quote(room_name)
               << ",\"port\":" << opts.port << ",\"players\":" << players
               << ",\"open\":" << (room_open ? "true" : "false") << "}";
        const std::string payload = beacon.str();
        net::udp_send_to(udp, from_ip, from_port, payload.data(),
                         static_cast<int>(payload.size()));
    }

    void worker_loop() {
        using clock = std::chrono::steady_clock;
        auto next_ping = clock::now();

        while (running.load()) {
            std::vector<net::socket_t> reads;
            std::vector<net::socket_t> writes;
            if (role == Role::hosting && listener.valid()) reads.push_back(listener.native());
            if (role == Role::hosting && udp.valid()) reads.push_back(udp.native());
            if (wake.valid()) reads.push_back(wake.native());
            for (auto& [id, peer] : conns) {
                if (!peer.sock.valid()) continue;
                reads.push_back(peer.sock.native());
                if (!peer.outbuf.empty()) writes.push_back(peer.sock.native());
            }

            const net::SelectResult ready = net::select_wait(reads, writes, kSelectTimeoutMs);

            // 唤醒字节：只为把这次循环立刻拉起来 drain outgoing，读掉即可
            if (wake.valid() &&
                std::find(ready.readable.begin(), ready.readable.end(), wake.native()) !=
                    ready.readable.end()) {
                char drain[64];
                std::string from_ip;
                int from_port = 0;
                while (net::udp_recv_from(wake, from_ip, from_port, drain, sizeof(drain)) > 0) {}
            }

            // 客人：连上后第一件事是发 hello
            if (role == Role::connecting) {
                if (auto it = conns.find(kHostId); it != conns.end() && !it->second.hello) {
                    std::ostringstream hello;
                    hello << "{\"t\":\"hello\",\"name\":" << json::quote(opts.name) << "}";
                    queue_to(it->second, make_payload(hello.str(), ""));
                    it->second.last_seen = clock::now();
                }
            }

            // 新连接
            if (role == Role::hosting && listener.valid() &&
                std::find(ready.readable.begin(), ready.readable.end(), listener.native()) !=
                    ready.readable.end()) {
                for (;;) {
                    std::string err;
                    net::Socket client = net::tcp_accept(listener, err);
                    if (!client.valid()) {
                        if (!err.empty()) log::warn("net: accept: " + err);
                        break;
                    }
                    if (static_cast<int>(conns.size()) >= opts.max_peers) {
                        log::warn("net: room full, rejecting a connection");
                        continue;  // client 析构即关闭
                    }
                    Peer peer;
                    peer.id = next_id++;
                    peer.sock = std::move(client);
                    peer.address = "?";
                    peer.last_seen = clock::now();
                    conns[peer.id] = std::move(peer);
                }
            }

            // 发现查询
            if (role == Role::hosting && udp.valid() &&
                std::find(ready.readable.begin(), ready.readable.end(), udp.native()) !=
                    ready.readable.end()) {
                handle_udp();
            }

            // 读对端
            std::vector<int> readable_ids;
            for (const auto& [id, peer] : conns) {
                if (peer.sock.valid() &&
                    std::find(ready.readable.begin(), ready.readable.end(), peer.sock.native()) !=
                        ready.readable.end()) {
                    readable_ids.push_back(id);
                }
            }
            for (int id : readable_ids) {
                const auto it = conns.find(id);
                if (it != conns.end()) read_peer(it->second);
            }

            // 写对端
            for (const auto& [id, peer] : conns) {
                if (!peer.sock.valid()) continue;  // 已知对端（无连接）不在这里发
                if (peer.outbuf.empty()) continue;
                if (std::find(ready.writable.begin(), ready.writable.end(), peer.sock.native()) ==
                    ready.writable.end()) {
                    continue;
                }
                auto it = conns.find(id);
                if (it == conns.end()) continue;
                const int n = net::send_some(it->second.sock, it->second.outbuf.data(),
                                             static_cast<int>(it->second.outbuf.size()));
                if (n > 0) {
                    it->second.outbuf.erase(it->second.outbuf.begin(),
                                            it->second.outbuf.begin() + n);
                } else if (n < 0) {
                    drop_peer(id, true);
                }
            }

            drain_outgoing();

            if (clock::now() >= next_ping) {
                next_ping = clock::now() + std::chrono::milliseconds(kPingIntervalMs);
                tick_pings();
            }
        }
    }

    void start_worker() {
        if (!wake.valid()) {
            std::string wake_err;
            wake = net::udp_open(0, false, wake_err);
            wake_port = wake.valid() ? net::udp_local_port(wake) : 0;
        }
        running.store(true);
        worker = std::thread([this] { worker_loop(); });
    }

    void reset() {
        running.store(false);
        // 先 shutdown（唤醒 worker 里的 select），**join 之后再 close**：在 worker 仍在
        // select 这些句柄时 close 会 use-after-close。shutdown 只断方向，句柄还没关。
        if (listener.valid()) net::shutdown_socket(listener);
        for (auto& [id, peer] : conns)
            if (peer.sock.valid()) net::shutdown_socket(peer.sock);
        if (worker.joinable()) worker.join();
        listener.close();
        udp.close();
        wake.close();
        wake_port = 0;
        for (auto& [id, peer] : conns) peer.sock.close();
        conns.clear();
        {
            std::lock_guard<std::mutex> lock(state_mtx);
            peer_snapshot.clear();
        }
        {
            std::lock_guard<std::mutex> lock(in_mtx);
            incoming.clear();
        }
        {
            std::lock_guard<std::mutex> lock(ev_mtx);
            events.clear();
        }
        {
            std::lock_guard<std::mutex> lock(out_mtx);
            outgoing.clear();
        }
        role = Role::off;
        self_id = 0;
        local_port = 0;
    }
};

Net::Net() : impl_(std::make_unique<Impl>()) {}

Net::~Net() { stop(); }

bool Net::host(const Options& opts, std::string& err) {
    stop();
    impl_->opts = opts;
    impl_->listener = net::tcp_listen("0.0.0.0", opts.port, opts.max_peers, err);
    if (!impl_->listener.valid()) {
        impl_->role = Impl::Role::off;
        impl_->set_error(err);
        return false;
    }
    if (opts.discoverable) {
        std::string udp_err;
        impl_->udp = net::udp_open(opts.discovery_port, true, udp_err);
        if (!impl_->udp.valid()) {
            // 发现不可用不算致命：房间仍可手动加入
            log::warn("net: discovery unavailable: " + udp_err);
        }
    }
    impl_->role = Impl::Role::hosting;
    impl_->self_id = kHostId;
    impl_->local_port = opts.port;
    {
        std::lock_guard<std::mutex> lock(impl_->room_mtx);
        impl_->room_name = opts.name;
        impl_->room_open = true; // 新开的房默认可加入；开局时由卡带置 false
    }
    impl_->start_worker();
    log::info("net: hosting on port " + std::to_string(opts.port) + " as " + opts.name);
    return true;
}

bool Net::join(const std::string& address, const Options& opts, std::string& err) {
    stop();
    impl_->opts = opts;
    net::Socket sock = net::tcp_connect(address, opts.port, 3000, err);
    if (!sock.valid()) {
        impl_->role = Impl::Role::off;
        impl_->set_error(err);
        return false;
    }
    Impl::Peer host_peer;
    host_peer.id = kHostId;
    host_peer.sock = std::move(sock);
    host_peer.address = address;
    host_peer.last_seen = std::chrono::steady_clock::now();
    impl_->conns[kHostId] = std::move(host_peer);
    impl_->role = Impl::Role::connecting;
    impl_->local_port = opts.port;
    impl_->start_worker();
    log::info("net: joining " + address + ":" + std::to_string(opts.port) + " as " + opts.name);
    return true;
}

void Net::stop() {
    if (!impl_) return;
    impl_->reset();
}

std::string Net::status() const {
    switch (impl_->role.load()) {
        case Impl::Role::hosting: return "hosting";
        case Impl::Role::connecting: return "connecting";
        case Impl::Role::connected: return "connected";
        case Impl::Role::off:
            std::lock_guard<std::mutex> lock(impl_->state_mtx);
            return impl_->last_error.empty() ? "off" : "error";
    }
    return "off";
}

std::string Net::error() const {
    std::lock_guard<std::mutex> lock(impl_->state_mtx);
    return impl_->last_error;
}

bool Net::hosting() const { return impl_->role == Impl::Role::hosting; }

bool Net::connected() const {
    return impl_->role == Impl::Role::hosting || impl_->role == Impl::Role::connected;
}

int Net::self_id() const { return impl_->self_id; }

int Net::host_id() const {
    return impl_->role == Impl::Role::off ? 0 : kHostId;
}

int Net::port() const { return impl_->local_port; }

std::string Net::local_ip() const { return net::local_address(); }

std::vector<Net::PeerInfo> Net::peers() const {
    std::lock_guard<std::mutex> lock(impl_->state_mtx);
    std::vector<PeerInfo> out;
    out.reserve(impl_->peer_snapshot.size());
    for (const auto& [id, info] : impl_->peer_snapshot) out.push_back(info);
    return out;
}

bool Net::send(int to, const std::string& kind, const std::string& data_json) {
    if (impl_->role == Impl::Role::off || impl_->role == Impl::Role::connecting) return false;
    if (kind.rfind("net.", 0) == 0) return false;  // 保留前缀
    if (data_json.size() > static_cast<size_t>(kMaxFrame - 256)) return false;  // 见上：帧上限预留
    {
        std::lock_guard<std::mutex> lock(impl_->out_mtx);
        impl_->outgoing.push_back(Impl::Out{to, kind, data_json});
    }
    impl_->wake_worker();  // 立刻叫醒 worker 去发，别等 select 超时（见 wake 成员注释）
    return true;
}

std::vector<Net::Message> Net::poll() {
    std::vector<Message> out;
    std::lock_guard<std::mutex> lock(impl_->in_mtx);
    out.reserve(impl_->incoming.size());
    while (!impl_->incoming.empty()) {
        out.push_back(std::move(impl_->incoming.front()));
        impl_->incoming.pop_front();
    }
    return out;
}

std::vector<Net::Event> Net::poll_events() {
    std::vector<Event> out;
    std::lock_guard<std::mutex> lock(impl_->ev_mtx);
    out.reserve(impl_->events.size());
    while (!impl_->events.empty()) {
        out.push_back(std::move(impl_->events.front()));
        impl_->events.pop_front();
    }
    return out;
}

std::vector<Net::Discovered> Net::discover(int timeout_ms) {
    std::vector<Discovered> found;
    std::string err;
    net::Socket udp = net::udp_open(0, true, err);
    if (!udp.valid()) return found;

    std::ostringstream query;
    query << "{\"magic\":" << json::quote(kMagic) << ",\"q\":1}";
    const std::string payload = query.str();
    const int port = impl_->opts.discovery_port > 0 ? impl_->opts.discovery_port : 45454;
    net::udp_send_to(udp, "255.255.255.255", port, payload.data(),
                     static_cast<int>(payload.size()));
    net::udp_send_to(udp, "127.0.0.1", port, payload.data(), static_cast<int>(payload.size()));

    const auto deadline = std::chrono::steady_clock::now() + std::chrono::milliseconds(timeout_ms);
    while (std::chrono::steady_clock::now() < deadline) {
        const auto remaining = std::chrono::duration_cast<std::chrono::milliseconds>(
                                   deadline - std::chrono::steady_clock::now())
                                   .count();
        if (remaining <= 0) break;
        const net::SelectResult ready = net::select_wait({udp.native()}, {},
                                                         static_cast<int>(remaining));
        if (ready.readable.empty()) continue;
        char buffer[1024];
        std::string from_ip;
        int from_port = 0;
        const int n = net::udp_recv_from(udp, from_ip, from_port, buffer, sizeof(buffer));
        if (n <= 0) continue;
        json::Object beacon;
        std::string parse_err;
        if (!beacon.parse(std::string(buffer, static_cast<size_t>(n)), parse_err)) continue;
        if (beacon.str("magic") != kMagic) continue;
        Discovered entry;
        entry.name = beacon.str("name");
        entry.address = from_ip;
        entry.port = beacon.integer("port", 0);
        entry.players = beacon.integer("players", 0);
        entry.open = beacon.flag("open", true); // 旧版主机没有这一项：按"可加入"算
        // 去重按 **name + port**（房间身份），不按来源 IP：同一台主机会同时收到
        // 广播查询与回环查询，各答一次——两次的来源 IP 不同（局域网 IP vs 127.0.0.1），
        // 但房间名与端口一样。按 (address, port) 去重会把同一个房间显示成两个。
        const bool dup = std::any_of(found.begin(), found.end(), [&](const Discovered& d) {
            return d.port == entry.port && d.name == entry.name;
        });
        if (!dup) found.push_back(std::move(entry));
    }
    return found;
}

void Net::set_room_name(const std::string& name) {
    if (!impl_) return;
    std::lock_guard<std::mutex> lock(impl_->room_mtx);
    impl_->room_name = name;
}

void Net::set_room_open(bool open) {
    if (!impl_) return;
    std::lock_guard<std::mutex> lock(impl_->room_mtx);
    impl_->room_open = open;
}

} // namespace phos

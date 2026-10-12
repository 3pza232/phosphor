#include "api/net_api.hpp"

#include "api/host_api.hpp"
#include "api/inspect.hpp"
#include "api/lua_value.hpp"
#include "core/text.hpp"
#include "net/net.hpp"

#include <sol/sol.hpp>

#include <cmath>
#include <cstdlib>
#include <string>

namespace phos {

namespace {

/// JSON 文本 → Lua 值。与 `lua_value_to_json`（inspect.*）成对：那个负责 Lua→JSON，
/// 这个负责反向。支持对象/数组/字符串/整数/小数/布尔/null；`\uXXXX` 转 UTF-8。
struct JsonToLua {
    sol::state_view lua;
    std::string_view text;
    std::size_t pos = 0;
    bool ok = true;
    std::string error;
    int depth = 0;
    /// 嵌套深度上限：远端可发上千层 [ / { ，无上限递归会爆栈
    static constexpr int kMaxDepth = 64;

    void skip_ws() {
        while (pos < text.size()) {
            const char c = text[pos];
            if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
                ++pos;
            } else {
                break;
            }
        }
    }
    bool eat(char c) {
        skip_ws();
        if (pos < text.size() && text[pos] == c) {
            ++pos;
            return true;
        }
        return false;
    }
    void fail(const char* message) {
        if (ok) {
            ok = false;
            error = message;
        }
    }
    sol::object nil() { return sol::make_object(lua, sol::nil); }

    bool parse(std::string& out_string) {
        skip_ws();
        if (pos >= text.size() || text[pos] != '"') {
            fail("expected string");
            return false;
        }
        ++pos;
        out_string.clear();
        while (pos < text.size()) {
            const char c = text[pos++];
            if (c == '"') return true;
            if (c != '\\') {
                out_string += c;
                continue;
            }
            if (pos >= text.size()) break;
            const char esc = text[pos++];
            switch (esc) {
                case '"': out_string += '"'; break;
                case '\\': out_string += '\\'; break;
                case '/': out_string += '/'; break;
                case 'b': out_string += '\b'; break;
                case 'f': out_string += '\f'; break;
                case 'n': out_string += '\n'; break;
                case 'r': out_string += '\r'; break;
                case 't': out_string += '\t'; break;
                case 'u': {
                    if (pos + 4 > text.size()) {
                        fail("bad \\u escape");
                        return false;
                    }
                    unsigned cp = 0;
                    for (int k = 0; k < 4; ++k) {
                        const char h = text[pos++];
                        cp <<= 4;
                        if (h >= '0' && h <= '9') cp |= static_cast<unsigned>(h - '0');
                        else if (h >= 'a' && h <= 'f') cp |= static_cast<unsigned>(h - 'a' + 10);
                        else if (h >= 'A' && h <= 'F') cp |= static_cast<unsigned>(h - 'A' + 10);
                        else {
                            fail("bad hex in \\u");
                            return false;
                        }
                    }
                    text::append_utf8(out_string, static_cast<char32_t>(cp));
                    break;
                }
                default: fail("bad escape"); return false;
            }
        }
        fail("unterminated string");
        return false;
    }

    sol::object value() {
        skip_ws();
        if (pos >= text.size()) {
            fail("unexpected end");
            return nil();
        }
        switch (text[pos]) {
            case '{': return object();
            case '[': return array();
            case '"': {
                std::string s;
                if (!parse(s)) return nil();
                return sol::make_object(lua, s);
            }
            case 't': {
                if (text.compare(pos, 4, "true") == 0) {
                    pos += 4;
                    return sol::make_object(lua, true);
                }
                fail("bad literal");
                return nil();
            }
            case 'f': {
                if (text.compare(pos, 5, "false") == 0) {
                    pos += 5;
                    return sol::make_object(lua, false);
                }
                fail("bad literal");
                return nil();
            }
            case 'n': {
                if (text.compare(pos, 4, "null") == 0) {
                    pos += 4;
                    return nil();
                }
                fail("bad literal");
                return nil();
            }
            default: return number();
        }
    }

    sol::object object() {
        if (depth >= kMaxDepth) {
            fail("json nested too deep");
            return nil();
        }
        ++depth;
        struct Pop { int& d; ~Pop() { --d; } } pop{depth};
        eat('{');
        sol::table table = lua.create_table();
        if (eat('}')) return sol::make_object(lua, table);
        for (;;) {
            std::string key;
            if (!parse(key)) return nil();
            if (!eat(':')) {
                fail("expected ':'");
                return nil();
            }
            sol::object v = value();
            if (!ok) return nil();
            table[key] = v;
            if (eat(',')) continue;
            if (eat('}')) break;
            fail("expected ',' or '}'");
            return nil();
        }
        return sol::make_object(lua, table);
    }

    sol::object array() {
        if (depth >= kMaxDepth) {
            fail("json nested too deep");
            return nil();
        }
        ++depth;
        struct Pop { int& d; ~Pop() { --d; } } pop{depth};
        eat('[');
        sol::table table = lua.create_table();
        if (eat(']')) return sol::make_object(lua, table);
        std::size_t index = 1;
        for (;;) {
            sol::object v = value();
            if (!ok) return nil();
            table[index++] = v;
            if (eat(',')) continue;
            if (eat(']')) break;
            fail("expected ',' or ']'");
            return nil();
        }
        return sol::make_object(lua, table);
    }

    sol::object number() {
        skip_ws();
        const std::size_t start = pos;
        while (pos < text.size()) {
            const char c = text[pos];
            if ((c >= '0' && c <= '9') || c == '-' || c == '+' || c == '.' || c == 'e' ||
                c == 'E') {
                ++pos;
            } else {
                break;
            }
        }
        if (start == pos) {
            fail("bad number");
            return nil();
        }
        const std::string token(text.substr(start, pos - start));
        const bool integral = token.find_first_of(".eE") == std::string::npos;
        if (integral) {
            return sol::make_object(lua, static_cast<long long>(std::strtoll(token.c_str(), nullptr, 10)));
        }
        return sol::make_object(lua, std::strtod(token.c_str(), nullptr));
    }
};

sol::object json_to_lua(sol::state_view lua, std::string_view text, std::string& error) {
    JsonToLua reader{lua, text};
    sol::object value = reader.value();
    if (!reader.ok) {
        error = reader.error;
        return sol::make_object(lua, sol::nil);
    }
    return value;
}

Net::Options read_options(const sol::optional<sol::table>& opts) {
    Net::Options options;
    if (!opts) return options;
    const sol::table table = *opts;
    // 端口/对端数来自脚本：越界值丢弃、回退默认，免得把非法值塞进 socket 调用
    auto port_of = [](int v, int fallback) { return (v < 0 || v > 65535) ? fallback : v; };
    options.port =
        port_of(static_cast<int>(api::read_number(table, "port", options.port)), options.port);
    options.discovery_port =
        port_of(static_cast<int>(api::read_number(table, "discovery_port", options.discovery_port)),
                options.discovery_port);
    const int peers = static_cast<int>(api::read_number(table, "max_peers", options.max_peers));
    options.max_peers = peers < 1 ? options.max_peers : (peers > 64 ? 64 : peers);
    sol::object name = table["name"];
    if (name.is<std::string>()) options.name = name.as<std::string>();
    sol::object discoverable = table["discoverable"];
    if (discoverable.is<bool>()) options.discoverable = discoverable.as<bool>();
    return options;
}

} // namespace

void register_net_api(sol::state& lua, HostContext& host) {
    sol::table phos = lua["phos"];
    sol::table net = phos.create_named("net");
    Net* engine = host.net;

    // 未接引擎（理论上不会发生）时给出安全空壳，卡带照常跑
    if (!engine) {
        net["host"] = [](sol::optional<sol::table>) { return false; };
        net["join"] = [](const std::string&, sol::optional<sol::table>) { return false; };
        net["stop"] = []() {};
        net["status"] = []() { return std::string("off"); };
        net["error"] = []() { return std::string("networking unavailable"); };
        net["role"] = []() { return std::string("none"); };
        net["self_id"] = []() { return 0; };
        net["host_id"] = []() { return 0; };
        net["port"] = []() { return 0; };
        net["local_ip"] = []() { return std::string(); };
        net["connected"] = []() { return false; };
        net["peers"] = [&lua]() { return lua.create_table(); };
        net["send"] = [](int, const std::string&, sol::optional<sol::object>) { return false; };
        net["broadcast"] = [](const std::string&, sol::optional<sol::object>) { return false; };
        net["poll"] = [&lua]() { return lua.create_table(); };
        net["events"] = [&lua]() { return lua.create_table(); };
        net["discover"] = [&lua](sol::optional<double>) { return lua.create_table(); };
        net["set_room"] = [](sol::optional<sol::table>) {};
        return;
    }

    net["host"] = [engine](sol::optional<sol::table> opts) {
        std::string err;
        return engine->host(read_options(opts), err);
    };
    net["join"] = [engine](const std::string& address, sol::optional<sol::table> opts) {
        std::string err;
        return engine->join(address, read_options(opts), err);
    };
    net["stop"] = [engine]() { engine->stop(); };
    net["status"] = [engine]() { return engine->status(); };
    net["error"] = [engine]() { return engine->error(); };
    net["role"] = [engine]() -> std::string {
        if (engine->hosting()) return "host";
        const std::string status = engine->status();
        if (status == "connecting" || status == "connected") return "client";
        return "none";
    };
    net["self_id"] = [engine]() { return engine->self_id(); };
    net["host_id"] = [engine]() { return engine->host_id(); };
    net["port"] = [engine]() { return engine->port(); };
    net["local_ip"] = [engine]() { return engine->local_ip(); };
    net["connected"] = [engine]() { return engine->connected(); };

    net["peers"] = [engine, &lua]() {
        sol::table out = lua.create_table();
        int index = 1;
        for (const Net::PeerInfo& peer : engine->peers()) {
            sol::table entry = lua.create_table();
            entry["id"] = peer.id;
            entry["name"] = peer.name;
            entry["address"] = peer.address;
            entry["rtt_ms"] = peer.rtt_ms;
            out[index++] = entry;
        }
        return out;
    };

    net["send"] = [engine](int to, const std::string& kind, sol::optional<sol::object> data) {
        const std::string json = data ? lua_value_to_json(*data, 8) : std::string();
        return engine->send(to, kind, json);
    };
    net["broadcast"] = [engine](const std::string& kind, sol::optional<sol::object> data) {
        const std::string json = data ? lua_value_to_json(*data, 8) : std::string();
        return engine->send(0, kind, json);
    };

    net["poll"] = [engine, &lua]() {
        sol::table out = lua.create_table();
        int index = 1;
        for (const Net::Message& message : engine->poll()) {
            sol::table entry = lua.create_table();
            entry["from"] = message.from;
            entry["kind"] = message.kind;
            if (message.data_json.empty()) {
                entry["data"] = lua.create_table();
            } else {
                std::string err;
                entry["data"] = json_to_lua(lua, message.data_json, err);
            }
            out[index++] = entry;
        }
        return out;
    };

    net["events"] = [engine, &lua]() {
        sol::table out = lua.create_table();
        int index = 1;
        for (const Net::Event& event : engine->poll_events()) {
            sol::table entry = lua.create_table();
            entry["type"] = event.type;
            entry["peer"] = event.peer;
            entry["name"] = event.name;
            out[index++] = entry;
        }
        return out;
    };

    net["discover"] = [engine, &lua](sol::optional<double> seconds) {
        // 秒数来自脚本：NaN/负数/超大都会让 static_cast<int> 成 UB，先钳到 [0, 5]
        double s = seconds.value_or(0.5);
        if (!std::isfinite(s) || s < 0.0) s = 0.0;
        if (s > 5.0) s = 5.0;
        const int timeout_ms = static_cast<int>(s * 1000.0);
        sol::table out = lua.create_table();
        int index = 1;
        for (const Net::Discovered& room : engine->discover(timeout_ms)) {
            sol::table entry = lua.create_table();
            entry["name"] = room.name;
            entry["address"] = room.address;
            entry["port"] = room.port;
            entry["players"] = room.players;
            entry["open"] = room.open;
            out[index++] = entry;
        }
        return out;
    };

    // 更新房间对外广播（发现应答）：主机开局后 set_room({ open = false })，搜索方看到"游戏中"
    net["set_room"] = [engine](sol::optional<sol::table> opts) {
        if (!opts) return;
        sol::object name = (*opts)["name"];
        if (name.is<std::string>()) engine->set_room_name(name.as<std::string>());
        sol::object open = (*opts)["open"];
        if (open.is<bool>()) engine->set_room_open(open.as<bool>());
    };
}

} // namespace phos

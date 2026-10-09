#include "agent/json_lite.hpp"

#include <cctype>
#include <cstdio>
#include <cstdlib>

namespace phos::json {

namespace {

struct Scanner {
    std::string_view text;
    size_t pos = 0;
    bool ok = true;
    std::string err;

    bool eof() const { return pos >= text.size(); }
    char peek() const { return eof() ? '\0' : text[pos]; }

    void fail(std::string why) {
        if (ok) {
            ok = false;
            err = std::move(why);
        }
    }

    void skip_ws() {
        while (!eof() && std::isspace(static_cast<unsigned char>(text[pos]))) ++pos;
    }
};

std::string parse_string(Scanner& s) {
    std::string out;
    if (s.peek() != '"') {
        s.fail("expected string");
        return out;
    }
    ++s.pos;
    while (!s.eof()) {
        const char c = s.text[s.pos++];
        if (c == '"') return out;
        if (c != '\\') {
            out += c;
            continue;
        }
        if (s.eof()) break;
        switch (const char esc = s.text[s.pos++]) {
            case 'n': out += '\n'; break;
            case 't': out += '\t'; break;
            case 'r': out += '\r'; break;
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case 'u':
                // 命令参数不含非 ASCII；跳过四位转义
                for (int i = 0; i < 4 && !s.eof(); ++i) ++s.pos;
                break;
            default: out += esc; break;
        }
    }
    s.fail("unterminated string");
    return out;
}

/// 跳过一个复合值（对象/数组），并把 scanner 停在它之后
void skip_value(Scanner& s) {
    s.skip_ws();
    const char open = s.peek();
    if (open != '{' && open != '[') {
        while (!s.eof() && s.peek() != ',' && s.peek() != '}') ++s.pos;
        return;
    }

    const char close = open == '{' ? '}' : ']';
    int depth = 0;
    while (!s.eof()) {
        const char c = s.text[s.pos++];
        if (c == '"') {
            --s.pos;
            parse_string(s);
            if (!s.ok) return;
            continue;
        }
        if (c == open) ++depth;
        else if (c == close && --depth == 0) return;
    }
    s.fail("unterminated nested value");
}

std::string trim(std::string text) {
    size_t begin = 0, end = text.size();
    while (begin < end && std::isspace(static_cast<unsigned char>(text[begin]))) ++begin;
    while (end > begin && std::isspace(static_cast<unsigned char>(text[end - 1]))) --end;
    return text.substr(begin, end - begin);
}

} // namespace

std::string escape(std::string_view text) {
    std::string out;
    out.reserve(text.size() + 8);
    for (char c : text) {
        switch (c) {
            case '"': out += "\\\""; break;
            case '\\': out += "\\\\"; break;
            case '\n': out += "\\n"; break;
            case '\r': out += "\\r"; break;
            case '\t': out += "\\t"; break;
            default:
                if (static_cast<unsigned char>(c) < 0x20) out += ' ';
                else out += c;
        }
    }
    return out;
}

std::string quote(std::string_view text) { return "\"" + escape(text) + "\""; }

bool Object::parse(std::string_view text, std::string& err) {
    values_.clear();
    duplicates_.clear();
    Scanner s{text};

    s.skip_ws();
    if (s.peek() != '{') {
        err = "expected '{'";
        return false;
    }
    ++s.pos;

    while (true) {
        s.skip_ws();
        if (s.eof()) {
            err = "unexpected end of object";
            return false;
        }
        if (s.peek() == '}') {
            ++s.pos;
            return true;
        }
        if (s.peek() == ',') {
            ++s.pos;
            continue;
        }

        std::string key = parse_string(s);
        if (!s.ok) {
            err = s.err;
            return false;
        }
        s.skip_ws();
        if (s.peek() != ':') {
            err = "expected ':'";
            return false;
        }
        ++s.pos;
        s.skip_ws();

        Entry entry;
        const char c = s.peek();
        if (c == '{') {
            // 嵌套对象：先量出它的范围，再递归解析成子对象（配置读取要用）
            Scanner nested{s.text.substr(s.pos)};
            skip_value(nested);
            if (!nested.ok) {
                err = nested.err;
                return false;
            }
            auto child = std::make_shared<Object>();
            std::string child_err;
            if (!child->parse(s.text.substr(s.pos, nested.pos), child_err)) {
                err = child_err;
                return false;
            }
            entry.kind = Kind::object;
            entry.object = std::move(child);
            s.pos += nested.pos;
        } else if (c == '[') {
            skip_value(s);
            if (!s.ok) {
                err = s.err;
                return false;
            }
            entry.kind = Kind::null;  // 数组不参与取值
        } else if (c == '"') {
            entry.kind = Kind::string;
            entry.text = parse_string(s);
            if (!s.ok) {
                err = s.err;
                return false;
            }
        } else {
            const size_t start = s.pos;
            while (!s.eof() && s.peek() != ',' && s.peek() != '}') ++s.pos;
            const std::string raw = trim(std::string(text.substr(start, s.pos - start)));
            if (raw == "true" || raw == "false") {
                entry.kind = Kind::boolean;
                entry.boolean = raw == "true";
            } else if (raw == "null" || raw.empty()) {
                entry.kind = Kind::null;
            } else {
                entry.kind = Kind::number;
                entry.number = std::strtod(raw.c_str(), nullptr);
            }
        }
        if (values_.count(key) > 0) duplicates_.push_back(key);
        values_[std::move(key)] = std::move(entry);
    }
}

bool Object::has(std::string_view key) const {
    return values_.find(std::string(key)) != values_.end();
}

std::string Object::str(std::string_view key, std::string_view fallback) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end()) return std::string(fallback);
    if (it->second.kind == Kind::string) return it->second.text;
    if (it->second.kind == Kind::number) {
        char buf[32];
        std::snprintf(buf, sizeof(buf), "%g", it->second.number);
        return buf;
    }
    return std::string(fallback);
}

double Object::num(std::string_view key, double fallback) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end()) return fallback;
    if (it->second.kind == Kind::number) return it->second.number;
    if (it->second.kind == Kind::string) return std::strtod(it->second.text.c_str(), nullptr);
    return fallback;
}

int Object::integer(std::string_view key, int fallback) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end()) return fallback;
    return static_cast<int>(num(key, static_cast<double>(fallback)));
}

bool Object::flag(std::string_view key, bool fallback) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end()) return fallback;
    switch (it->second.kind) {
        case Kind::boolean: return it->second.boolean;
        case Kind::number: return it->second.number != 0.0;
        case Kind::string: {
            const std::string& v = it->second.text;
            if (v.empty()) return fallback;
            return v == "1" || v == "true" || v == "down" || v == "on" || v == "yes";
        }
        default: return fallback;
    }
}

const Object* Object::object(std::string_view key) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end() || it->second.kind != Kind::object) return nullptr;
    return it->second.object.get();
}

} // namespace phos::json

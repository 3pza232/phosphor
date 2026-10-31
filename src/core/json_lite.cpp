#include "core/json_lite.hpp"

#include "core/text.hpp"

#include <cctype>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <limits>

namespace phos::json {

namespace {

struct Scanner {
    explicit Scanner(std::string_view input) : text(input) {}

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

int hex_digit(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/// 读四位十六进制（不含前面的 \u）
bool parse_hex4(Scanner& s, unsigned& value) {
    if (s.text.size() - s.pos < 4) return false;
    unsigned result = 0;
    for (int i = 0; i < 4; ++i) {
        const int digit = hex_digit(s.text[s.pos++]);
        if (digit < 0) return false;
        result = (result << 4) | static_cast<unsigned>(digit);
    }
    value = result;
    return true;
}

/// 只做 UTF-8 的**结构**解码：非法首字节、被截断的序列、超长编码、超出 U+10FFFF 都返回
/// false，交给调用方按一个字节前进。代理码位在这里算结构合法（CESU-8 之类的孤立代理
/// 要单独处理），由 escape 统一改写成 U+FFFD。
bool decode_utf8(std::string_view text, size_t pos, char32_t& cp, size_t& length) {
    const unsigned char lead = static_cast<unsigned char>(text[pos]);
    if (lead < 0x80) {
        cp = lead;
        length = 1;
        return true;
    }
    if ((lead & 0xE0) == 0xC0) {
        length = 2;
        cp = lead & 0x1F;
    } else if ((lead & 0xF0) == 0xE0) {
        length = 3;
        cp = lead & 0x0F;
    } else if ((lead & 0xF8) == 0xF0) {
        length = 4;
        cp = lead & 0x07;
    } else {
        return false;
    }
    if (pos + length > text.size()) return false;
    for (size_t i = 1; i < length; ++i) {
        const unsigned char cont = static_cast<unsigned char>(text[pos + i]);
        if ((cont & 0xC0) != 0x80) return false;
        cp = (cp << 6) | (cont & 0x3F);
    }
    if ((length == 2 && cp < 0x80) || (length == 3 && cp < 0x800) ||
        (length == 4 && (cp < 0x10000 || cp > 0x10FFFF)))
        return false;
    return true;
}

/// \uXXXX（大写十六进制，JSON 大小写不敏感）
void append_unicode_escape(std::string& out, char32_t cp) {
    static const char kHex[] = "0123456789ABCDEF";
    out += "\\u";
    out += kHex[(cp >> 12) & 0xF];
    out += kHex[(cp >> 8) & 0xF];
    out += kHex[(cp >> 4) & 0xF];
    out += kHex[cp & 0xF];
}

/// 解析字符串（scanner 停在起始引号上）。\uXXXX 按代理对合并成 UTF-8 码点：
/// 单独的高/低代理不是合法 JSON 文本，判错而不是偷偷丢弃。
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
        const char esc = s.text[s.pos++];
        switch (esc) {
            case 'n': out += '\n'; break;
            case 't': out += '\t'; break;
            case 'r': out += '\r'; break;
            case 'b': out += '\b'; break;
            case 'f': out += '\f'; break;
            case '/': out += '/'; break;
            case '"': out += '"'; break;
            case '\\': out += '\\'; break;
            case 'u': {
                unsigned first = 0;
                if (!parse_hex4(s, first)) {
                    s.fail("bad \\u escape");
                    return out;
                }
                char32_t cp = first;
                if (first >= 0xD800 && first <= 0xDBFF) {
                    // 高代理必须紧跟低代理：\uD83D\uDE00 → U+1F600
                    if (s.text.size() - s.pos < 2 || s.text[s.pos] != '\\' ||
                        s.text[s.pos + 1] != 'u') {
                        s.fail("lone surrogate in \\u escape");
                        return out;
                    }
                    s.pos += 2;
                    unsigned second = 0;
                    if (!parse_hex4(s, second) || second < 0xDC00 || second > 0xDFFF) {
                        s.fail("invalid surrogate pair");
                        return out;
                    }
                    cp = 0x10000 + ((first - 0xD800) << 10) + (second - 0xDC00);
                } else if (first >= 0xDC00 && first <= 0xDFFF) {
                    s.fail("lone surrogate in \\u escape");
                    return out;
                }
                text::append_utf8(out, cp);
                break;
            }
            default: s.fail("bad escape"); return out;
        }
    }
    s.fail("unterminated string");
    return out;
}

/// JSON 数字文法：-?(0|[1-9][0-9]*)(\.[0-9]+)?([eE][+-]?[0-9]+)?
/// 先按文法过一遍再交给 strtod：NaN/Infinity/+1/01/0x10 都是 strtod 会宽容接受、
/// JSON 却非法的写法；溢出成无穷（1e999）同样判错——本实现只保留 double 能表示的值。
bool parse_number(std::string_view token, double& value) {
    const size_t size = token.size();
    size_t i = 0;
    if (i < size && token[i] == '-') ++i;
    if (i >= size) return false;
    if (token[i] == '0') {
        ++i;
    } else if (token[i] >= '1' && token[i] <= '9') {
        while (i < size && std::isdigit(static_cast<unsigned char>(token[i]))) ++i;
    } else {
        return false;
    }
    if (i < size && token[i] == '.') {
        ++i;
        if (i >= size || !std::isdigit(static_cast<unsigned char>(token[i]))) return false;
        while (i < size && std::isdigit(static_cast<unsigned char>(token[i]))) ++i;
    }
    if (i < size && (token[i] == 'e' || token[i] == 'E')) {
        ++i;
        if (i < size && (token[i] == '+' || token[i] == '-')) ++i;
        if (i >= size || !std::isdigit(static_cast<unsigned char>(token[i]))) return false;
        while (i < size && std::isdigit(static_cast<unsigned char>(token[i]))) ++i;
    }
    if (i != size) return false;

    const std::string text(token);
    const double parsed = std::strtod(text.c_str(), nullptr);
    if (!std::isfinite(parsed)) return false;
    value = parsed;
    return true;
}

/// 数字的短文本（%g）：显示与对象取值用
std::string short_number(double value) {
    char buffer[32];
    std::snprintf(buffer, sizeof(buffer), "%g", value);
    return buffer;
}

/// 数字的精确文本（17 位有效数字）：落盘后可无损回读
std::string exact_number(double value) {
    char buffer[40];
    std::snprintf(buffer, sizeof(buffer), "%.17g", value);
    return buffer;
}

bool parse_value(Scanner& s, Value& out, int depth);
bool parse_object(Scanner& s, Value& out, int depth);
bool parse_array(Scanner& s, Value& out, int depth);

/// 数字扫描：字符集先扫一段，再交给严格文法校验，最后要求后面是分隔符——
/// 否则 "1abc" 会被截成合法前缀 1，留下 "abc" 让上层报一个难懂的错误
bool parse_number_at(Scanner& s, Value& out) {
    const size_t start = s.pos;
    while (!s.eof()) {
        const char c = s.peek();
        if (std::isdigit(static_cast<unsigned char>(c)) || c == '-' || c == '+' || c == '.' ||
            c == 'e' || c == 'E')
            ++s.pos;
        else
            break;
    }
    const std::string raw(s.text.substr(start, s.pos - start));
    double parsed = 0.0;
    if (!parse_number(raw, parsed)) {
        s.fail(raw.empty() ? "expected value" : "bad number '" + raw.substr(0, 32) + "'");
        return false;
    }
    if (!s.eof()) {
        const char next = s.peek();
        if (!std::isspace(static_cast<unsigned char>(next)) && next != ',' && next != '}' &&
            next != ']') {
            s.fail("bad number '" + raw.substr(0, 32) + "'");
            return false;
        }
    }
    out = Value::of_number(parsed);
    return true;
}

bool parse_value(Scanner& s, Value& out, int depth) {
    s.skip_ws();
    if (s.eof()) {
        s.fail("unexpected end");
        return false;
    }
    switch (s.peek()) {
        case '{': return parse_object(s, out, depth);
        case '[': return parse_array(s, out, depth);
        case '"':
            out = Value::of_text(parse_string(s));
            return s.ok;
        case 't':
            if (s.text.substr(s.pos, 4) != "true") {
                s.fail("bad literal");
                return false;
            }
            s.pos += 4;
            out = Value::of_boolean(true);
            return true;
        case 'f':
            if (s.text.substr(s.pos, 5) != "false") {
                s.fail("bad literal");
                return false;
            }
            s.pos += 5;
            out = Value::of_boolean(false);
            return true;
        case 'n':
            if (s.text.substr(s.pos, 4) != "null") {
                s.fail("bad literal");
                return false;
            }
            s.pos += 4;
            out = Value{};
            return true;
        default: return parse_number_at(s, out);
    }
}

bool parse_object(Scanner& s, Value& out, int depth) {
    if (depth >= Value::kMaxDepth) {
        s.fail("json nested too deep");
        return false;
    }
    ++s.pos;  // '{'
    out = Value::of_object();
    while (true) {
        s.skip_ws();
        if (s.eof()) {
            s.fail("unexpected end of object");
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
        if (!s.ok) return false;
        s.skip_ws();
        if (s.peek() != ':') {
            s.fail("expected ':'");
            return false;
        }
        ++s.pos;
        Value child;
        if (!parse_value(s, child, depth + 1)) return false;
        if (out.members.count(key) > 0) out.duplicate_keys.push_back(key);
        out.members[std::move(key)] = std::move(child);
    }
}

bool parse_array(Scanner& s, Value& out, int depth) {
    if (depth >= Value::kMaxDepth) {
        s.fail("json nested too deep");
        return false;
    }
    ++s.pos;  // '['
    out = Value::of_array();
    while (true) {
        s.skip_ws();
        if (s.eof()) {
            s.fail("unterminated array");
            return false;
        }
        if (s.peek() == ']') {
            ++s.pos;
            return true;
        }
        if (s.peek() == ',') {
            ++s.pos;
            continue;
        }
        Value child;
        if (!parse_value(s, child, depth + 1)) return false;
        out.items.push_back(std::move(child));
    }
}

} // namespace

std::string escape(std::string_view text) {
    std::string out;
    out.reserve(text.size() + 8);
    size_t pos = 0;
    while (pos < text.size()) {
        char32_t cp = 0;
        size_t length = 0;
        if (!decode_utf8(text, pos, cp, length)) {
            out += "\\uFFFD";  // 非法 UTF-8：宁可替换也不能把坏字节写进 JSON
            ++pos;
            continue;
        }
        if (cp >= 0xD800 && cp <= 0xDFFF) {
            out += "\\uFFFD";  // 孤立代理（CESU-8 等）：JSON 文本不得含代理码位
        } else if (cp == '"') {
            out += "\\\"";
        } else if (cp == '\\') {
            out += "\\\\";
        } else if (cp == '\b') {
            out += "\\b";
        } else if (cp == '\f') {
            out += "\\f";
        } else if (cp == '\n') {
            out += "\\n";
        } else if (cp == '\r') {
            out += "\\r";
        } else if (cp == '\t') {
            out += "\\t";
        } else if (cp < 0x20 || (cp >= 0x7F && cp <= 0x9F)) {
            append_unicode_escape(out, cp);  // 其余 C0 控制字符与 DEL/C1
        } else {
            out.append(text.data() + pos, length);
        }
        pos += length;
    }
    return out;
}

std::string quote(std::string_view text) { return "\"" + escape(text) + "\""; }

namespace {

void dump_value(const Value& value, std::string& out) {
    switch (value.kind) {
        case Value::Kind::null: out += "null"; return;
        case Value::Kind::boolean: out += value.boolean ? "true" : "false"; return;
        case Value::Kind::number: out += exact_number(value.number); return;
        case Value::Kind::text: out += quote(value.text); return;
        case Value::Kind::array:
            out += '[';
            for (size_t i = 0; i < value.items.size(); ++i) {
                if (i > 0) out += ',';
                dump_value(value.items[i], out);
            }
            out += ']';
            return;
        case Value::Kind::object: {
            out += '{';
            bool first = true;
            for (const auto& [key, child] : value.members) {
                if (!first) out += ',';
                first = false;
                out += quote(key);
                out += ':';
                dump_value(child, out);
            }
            out += '}';
            return;
        }
    }
}

} // namespace

bool Value::parse(std::string_view json_text, std::string& err) {
    Scanner s{json_text};
    *this = Value{};
    if (!parse_value(s, *this, 0)) {
        err = s.err.empty() ? "bad json" : s.err;
        return false;
    }
    s.skip_ws();
    if (!s.eof()) {
        err = "trailing characters";
        return false;
    }
    return true;
}

std::string Value::dump() const {
    std::string out;
    dump_value(*this, out);
    return out;
}

bool Object::parse(std::string_view text, std::string& err) {
    Value root;
    if (!root.parse(text, err)) return false;
    if (root.kind != Value::Kind::object) {
        err = "expected '{'";
        return false;
    }
    assign(root, *this);
    return true;
}

void Object::assign(const Value& value, Object& target) {
    target.values_.clear();
    target.duplicates_ = value.duplicate_keys;
    for (const auto& [key, child] : value.members) {
        Entry entry;
        switch (child.kind) {
            case Value::Kind::text:
                entry.kind = Kind::string;
                entry.text = child.text;
                break;
            case Value::Kind::number:
                entry.kind = Kind::number;
                entry.number = child.number;
                break;
            case Value::Kind::boolean:
                entry.kind = Kind::boolean;
                entry.boolean = child.boolean;
                break;
            case Value::Kind::null: entry.kind = Kind::null; break;
            case Value::Kind::object:
                entry.kind = Kind::object;
                entry.object = std::make_shared<Object>();
                assign(child, *entry.object);
                break;
            case Value::Kind::array:
                entry.kind = Kind::array;
                for (const Value& item : child.items) {
                    switch (item.kind) {
                        case Value::Kind::text: entry.array.push_back(item.text); break;
                        case Value::Kind::number:
                            entry.array.push_back(short_number(item.number));
                            break;
                        case Value::Kind::boolean:
                            entry.array.push_back(item.boolean ? "true" : "false");
                            break;
                        case Value::Kind::null: entry.array.push_back("null"); break;
                        default: break;  // 嵌套对象/数组不参与取值
                    }
                }
                break;
        }
        target.values_.emplace(key, std::move(entry));
    }
}

bool Object::has(std::string_view key) const {
    return values_.find(std::string(key)) != values_.end();
}

bool Object::is_string(std::string_view key) const {
    auto it = values_.find(std::string(key));
    return it != values_.end() && it->second.kind == Kind::string;
}

bool Object::is_number(std::string_view key) const {
    auto it = values_.find(std::string(key));
    return it != values_.end() && it->second.kind == Kind::number;
}

bool Object::is_boolean(std::string_view key) const {
    auto it = values_.find(std::string(key));
    return it != values_.end() && it->second.kind == Kind::boolean;
}

std::string Object::str(std::string_view key, std::string_view fallback) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end()) return std::string(fallback);
    if (it->second.kind == Kind::string) return it->second.text;
    if (it->second.kind == Kind::number) return short_number(it->second.number);
    return std::string(fallback);
}

double Object::num(std::string_view key, double fallback) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end()) return fallback;
    if (it->second.kind == Kind::number) return it->second.number;
    if (it->second.kind == Kind::string) {
        // 字符串形式的数值（协议里的兼容写法）；"inf"/"nan" 文本不得传播成非有限数
        const double parsed = std::strtod(it->second.text.c_str(), nullptr);
        return std::isfinite(parsed) ? parsed : fallback;
    }
    return fallback;
}

double Object::number(std::string_view key, double fallback) const { return num(key, fallback); }

int Object::integer(std::string_view key, int fallback) const {
    const double value = num(key, static_cast<double>(fallback));
    if (!std::isfinite(value)) return fallback;
    // 先钳再窄化：double → int 越界是 UB，不能直接 static_cast
    if (value >= static_cast<double>(std::numeric_limits<int>::max()))
        return std::numeric_limits<int>::max();
    if (value <= static_cast<double>(std::numeric_limits<int>::min()))
        return std::numeric_limits<int>::min();
    return static_cast<int>(value);
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

std::vector<std::string> Object::keys() const {
    std::vector<std::string> out;
    out.reserve(values_.size());
    for (const auto& [key, unused] : values_) {
        (void)unused;
        out.push_back(key);
    }
    return out;
}

std::vector<std::string> Object::string_array(std::string_view key) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end() || it->second.kind != Kind::array) return {};
    return it->second.array;
}

} // namespace phos::json

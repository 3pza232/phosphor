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

/// 解析数组：只收集字符串元素（数字/布尔按原样文本收），嵌套对象/数组整体跳过。
/// 配置里的 mods_disabled 是字符串数组，其它数组语义未定义——收了也没人读
bool parse_array(Scanner& s, std::vector<std::string>& out) {
    ++s.pos;  // '['
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
        const char c = s.peek();
        if (c == '"') {
            out.push_back(parse_string(s));
            if (!s.ok) return false;
        } else if (c == '{' || c == '[') {
            skip_value(s);  // 嵌套的复合值不参与取值
            if (!s.ok) return false;
        } else {
            const size_t start = s.pos;
            while (!s.eof() && s.peek() != ',' && s.peek() != ']') ++s.pos;
            const std::string raw = trim(std::string(s.text.substr(start, s.pos - start)));
            double ignored = 0.0;
            if (raw.empty() ||
                (raw != "true" && raw != "false" && raw != "null" && !parse_number(raw, ignored))) {
                s.fail("bad value in array");  // 裸字面量同样按 JSON 文法校验
                return false;
            }
            out.push_back(raw);
        }
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

bool Object::parse(std::string_view text, std::string& err) { return parse_at(text, err, 0); }

bool Object::parse_at(std::string_view text, std::string& err, int depth) {
    if (depth >= kMaxDepth) {
        err = "json nested too deep";
        return false;
    }
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
            if (!child->parse_at(s.text.substr(s.pos, nested.pos), child_err, depth + 1)) {
                err = child_err;
                return false;
            }
            entry.kind = Kind::object;
            entry.object = std::move(child);
            s.pos += nested.pos;
        } else if (c == '[') {
            entry.kind = Kind::array;
            if (!parse_array(s, entry.array)) {
                err = s.err;
                return false;
            }
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
            } else if (raw == "null") {
                entry.kind = Kind::null;
            } else {
                double parsed = 0.0;
                if (!parse_number(raw, parsed)) {
                    err = raw.empty() ? "expected value" : "bad number '" + raw.substr(0, 32) + "'";
                    return false;
                }
                entry.kind = Kind::number;
                entry.number = parsed;
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

std::vector<std::string> Object::string_array(std::string_view key) const {
    auto it = values_.find(std::string(key));
    if (it == values_.end() || it->second.kind != Kind::array) return {};
    return it->second.array;
}

} // namespace phos::json

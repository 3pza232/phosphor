#include "cart/save_store.hpp"

#include "core/json_lite.hpp"
#include "core/log.hpp"

#include <cmath>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string_view>

namespace phos {

namespace {

/// 容器格式：第一行是带版本/卡带 id/校验和的头部，正文是一行 JSON 对象。
/// 旧格式（`key=value` 每行一条、无头部）继续可读，并在首次打开时自动升级；
/// 升级前留一份 `.v1` 备份——玩家的旧存档不该因为升级而变得不可回退。
constexpr std::string_view kMagic = "PHOSPHOR-SAVE";
constexpr int kFormatVersion = 2;

bool key_within_limits(const std::string& key) {
    return !key.empty() && key.size() <= SaveStore::kMaxKeyLength &&
           key.find('=') == std::string::npos && key.find('\n') == std::string::npos;
}

/// 值树合法性：数字必须有限（NaN/inf 不是合法 JSON）、不允许 null
/// （null 与"键不存在"在 Lua 里无法区分，存下来只会读回一个缺项）
bool value_tree_valid(const SaveStore::Value& value) {
    switch (value.kind) {
        case SaveStore::Value::Kind::null: return false;
        case SaveStore::Value::Kind::number: return std::isfinite(value.number);
        case SaveStore::Value::Kind::array:
            for (const SaveStore::Value& item : value.items)
                if (!value_tree_valid(item)) return false;
            return true;
        case SaveStore::Value::Kind::object:
            for (const auto& [key, child] : value.members) {
                (void)key;
                if (!value_tree_valid(child)) return false;
            }
            return true;
        default: return true;
    }
}

/// 入库校验：结构化值按其 JSON 文本计入 4096 上限（磁带码也按这份文本导出）；
/// 顶层的文本值另要求不含换行（磁带码按 key=value 行拼接）
bool value_within_limits(const SaveStore::Value& value) {
    if (!value_tree_valid(value)) return false;
    switch (value.kind) {
        case SaveStore::Value::Kind::text:
            return value.text.size() <= SaveStore::kMaxValueLength &&
                   value.text.find('\n') == std::string::npos;
        case SaveStore::Value::Kind::number:
        case SaveStore::Value::Kind::boolean: return true;
        default: return value.dump().size() <= SaveStore::kMaxValueLength;
    }
}

int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

uint32_t crc32(std::string_view data) {
    uint32_t crc = 0xFFFFFFFFu;
    for (unsigned char byte : data) {
        crc ^= byte;
        for (int bit = 0; bit < 8; ++bit)
            crc = (crc >> 1) ^ (0xEDB88320u & (0u - (crc & 1u)));
    }
    return ~crc;
}

std::string hex32(uint32_t value) {
    static const char* kDigits = "0123456789abcdef";
    std::string out(8, '0');
    for (int i = 7; i >= 0; --i) {
        out[static_cast<size_t>(i)] = kDigits[value & 0xFu];
        value >>= 4;
    }
    return out;
}

/// 正文：一份 JSON 对象（键升序、值树原样转 JSON），CRC 与落盘都只认这一份文本
std::string json_payload(const std::map<std::string, SaveStore::Value>& data) {
    json::Value root = json::Value::of_object();
    for (const auto& [key, value] : data) root.members[key] = value;
    return root.dump();
}

/// 删掉半份写出的临时文件（失败路径的清理；删不掉也没有更好的补救）
void discard_tmp(const std::string& tmp) {
    std::error_code ec;
    if (std::filesystem::is_regular_file(tmp, ec)) std::filesystem::remove(tmp, ec);
}

/// 目录可写性探针：临时文件都建不出来，就永远改不成 .sav，此时老实降级只读
bool probe_writable(const std::string& tmp) {
    std::ofstream probe(tmp, std::ios::trunc);
    if (!probe) return false;
    probe.close();
    discard_tmp(tmp);
    return true;
}

/// 旧格式解析（`key=value` 每行一条）：用于迁移与磁带码导入；值按文本处理
bool parse_legacy(std::string_view text, std::map<std::string, SaveStore::Value>& out) {
    size_t begin = 0;
    while (begin <= text.size()) {
        const size_t end = text.find('\n', begin);
        std::string_view line = text.substr(
            begin, end == std::string_view::npos ? std::string_view::npos : end - begin);
        if (!line.empty() && line.back() == '\r') line.remove_suffix(1);
        const size_t eq = line.find('=');
        if (eq != std::string_view::npos) {
            const std::string key(line.substr(0, eq));
            const std::string value(line.substr(eq + 1));
            // 存档文件亦不可信：越界项跳过，而不是让整份存档作废
            if (key_within_limits(key) && value.size() <= SaveStore::kMaxValueLength &&
                value.find('\n') == std::string::npos &&
                !(out.size() >= SaveStore::kMaxEntries && out.find(key) == out.end()))
                out[key] = SaveStore::Value::of_text(value);
        }
        if (end == std::string_view::npos) break;
        begin = end + 1;
    }
    return true;
}

struct Header {
    std::string cart_id;
    uint32_t crc = 0;
    std::string payload;
};

bool parse_v2(std::string_view text, Header& header) {
    const size_t newline = text.find('\n');
    if (newline == std::string_view::npos) return false;
    std::istringstream line{std::string(text.substr(0, newline))};
    std::string magic;
    int version = 0;
    std::string crc_hex;
    line >> magic >> version >> header.cart_id >> crc_hex;
    if (magic != kMagic || version != kFormatVersion) return false;
    if (crc_hex.size() != 8) return false;
    uint32_t crc = 0;
    for (char c : crc_hex) {
        const int nibble = hex_nibble(c);
        if (nibble < 0) return false;
        crc = (crc << 4) | static_cast<uint32_t>(nibble);
    }
    header.crc = crc;
    header.payload = std::string(text.substr(newline + 1));
    return true;
}

} // namespace

std::string save_text(const SaveStore::Value& value) {
    if (value.kind == SaveStore::Value::Kind::text) return value.text;
    return value.dump();
}

bool SaveStore::open(const std::string& save_dir, const std::string& cart_id, int slot) {
    namespace fs = std::filesystem;
    data_.clear();
    if (slot < 0) slot = 0;
    if (slot > kMaxSlot) slot = kMaxSlot;
    cart_id_ = cart_id;
    const std::string suffix = slot > 0 ? ".s" + std::to_string(slot) : std::string();
    path_ = (fs::path(save_dir) / (cart_id + suffix + ".sav")).string();
    writable_ = false;

    std::error_code ec;
    fs::create_directories(save_dir, ec);
    if (!ec) writable_ = probe_writable(path_ + ".tmp");

    std::error_code exists_ec;
    if (!fs::exists(path_, exists_ec)) return writable_;  // 新存档：空数据

    std::ifstream in(path_, std::ios::binary);
    if (!in) {
        // 旧档存在却读不出（权限/介质错误）：只读运行，绝不用空数据覆盖未知内容
        writable_ = false;
        return false;
    }
    std::string text((std::istreambuf_iterator<char>(in)), std::istreambuf_iterator<char>());
    in.close();

    Header header;
    if (parse_v2(text, header)) {
        if (header.cart_id != cart_id) {
            log::warn("save: " + path_ + " belongs to cart '" + header.cart_id + "', ignoring");
            writable_ = false;
            return false;
        }
        if (crc32(header.payload) != header.crc) {
            log::warn("save: checksum mismatch in " + path_);
            writable_ = false;
            return false;
        }
        json::Value payload;
        std::string err;
        if (!payload.parse(header.payload, err)) {
            log::warn("save: bad payload in " + path_ + ": " + err);
            writable_ = false;
            return false;
        }
        if (payload.kind != json::Value::Kind::object) {
            log::warn("save: payload in " + path_ + " is not an object");
            writable_ = false;
            return false;
        }
        for (const auto& [key, value] : payload.members) {
            if (!key_within_limits(key)) continue;
            if (data_.size() >= kMaxEntries) break;
            if (!value_within_limits(value)) continue;  // 非法/超限值跳过，不让整份存档作废
            data_[key] = value;
        }
        return true;
    }

    // 旧格式：读入后立刻升级；保留 .v1 备份，升级失败也不动原文件
    if (!parse_legacy(text, data_)) return false;
    if (writable_) {
        const std::string backup = path_ + ".v1";
        std::error_code backup_ec;
        if (!fs::exists(backup, backup_ec)) {
            std::error_code copy_ec;
            fs::copy_file(path_, backup, fs::copy_options::none, copy_ec);
            if (copy_ec) log::warn("save: cannot back up legacy file: " + copy_ec.message());
        }
        if (!flush(data_)) log::warn("save: cannot upgrade " + path_ + " to format 2");
    }
    return true;
}

std::optional<SaveStore::Value> SaveStore::get_value(const std::string& key) const {
    auto it = data_.find(key);
    if (it == data_.end()) return std::nullopt;
    return it->second;
}

std::optional<std::string> SaveStore::get(const std::string& key) const {
    auto value = get_value(key);
    if (!value) return std::nullopt;
    return save_text(*value);
}

bool SaveStore::set(const std::string& key, const Value& value) {
    if (!writable_ || !key_within_limits(key) || !value_within_limits(value)) return false;

    auto it = data_.find(key);
    if (it == data_.end()) {
        if (data_.size() >= kMaxEntries) return false;
        data_.emplace(key, value);
        if (flush(data_)) return true;
        data_.erase(key);  // 写盘失败：回滚，内存保持与磁盘一致
        return false;
    }
    const Value previous = it->second;
    it->second = value;
    if (flush(data_)) return true;
    it->second = previous;
    return false;
}

bool SaveStore::erase(const std::string& key) {
    if (!writable_) return false;
    auto it = data_.find(key);
    if (it == data_.end()) return true;  // 不在表里：磁盘上也没有它

    auto node = data_.extract(it);
    if (flush(data_)) return true;
    data_.insert(std::move(node));  // 写盘失败：把节点放回去
    return false;
}

bool SaveStore::flush(const std::map<std::string, Value>& data) const {
    const std::string tmp = path_ + ".tmp";
    std::ofstream out(tmp, std::ios::trunc | std::ios::binary);
    if (!out) return false;

    // 头部里的卡带 id 取自文件名：同一份文件被拷到别的 id 下会被 open() 拒绝，
    // 避免"把 A 的档当 B 的档读"（跨卡带串档比丢档更难查）
    const std::string payload = json_payload(data);
    out << kMagic << ' ' << kFormatVersion << ' ' << cart_id_ << ' ' << hex32(crc32(payload))
        << '\n'
        << payload;
    out.flush();
    if (!out) {
        discard_tmp(tmp);
        return false;
    }
    out.close();
    if (!out) {
        discard_tmp(tmp);
        return false;
    }

    std::error_code ec;
    std::filesystem::rename(tmp, path_, ec);
    if (ec) {
        discard_tmp(tmp);
        return false;
    }
    return true;
}

std::string SaveStore::export_code() const {
    // 磁带码：旧版 `key=value\n` 载荷的十六进制——跨版本/跨机器都能读。
    // 结构化值按 JSON 文本写进码里（导入后成为文本值：码只保证文本语义）
    static const char* kHex = "0123456789ABCDEF";
    std::string payload;
    for (const auto& [k, v] : data_) payload += k + "=" + save_text(v) + "\n";

    std::string code;
    code.reserve(payload.size() * 2);
    for (unsigned char c : payload) {
        code += kHex[c >> 4];
        code += kHex[c & 0x0F];
    }
    return code;
}

bool SaveStore::import_code(const std::string& code) {
    if (!writable_) return false;

    // 玩家/agent 复制来的码可能夹带空白与折行：先剔除再解码
    std::string hex;
    hex.reserve(code.size());
    for (char c : code)
        if (c != ' ' && c != '\n' && c != '\r' && c != '\t') hex += c;
    if (hex.empty() || hex.size() % 2 != 0) return false;

    std::string payload;
    payload.reserve(hex.size() / 2);
    for (size_t i = 0; i < hex.size(); i += 2) {
        const int high = hex_nibble(hex[i]);
        const int low = hex_nibble(hex[i + 1]);
        if (high < 0 || low < 0) return false;
        payload += static_cast<char>((high << 4) | low);
    }

    // 先全量校验再落地：任何一处非法都保持原存档不变
    std::map<std::string, Value> parsed;
    if (!parse_legacy(payload, parsed)) return false;

    std::map<std::string, Value> previous = data_;
    data_ = std::move(parsed);
    if (flush(data_)) return true;
    data_ = std::move(previous);
    return false;
}

} // namespace phos

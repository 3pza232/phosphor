#include "cart/save_store.hpp"

#include <filesystem>
#include <fstream>

namespace phos {

namespace {

/// 入库校验：磁带码是 key=value 换行拼接的十六进制，因此键值不得含换行，键不得含 '='
bool entry_within_limits(const std::string& key, const std::string& value) {
    if (key.empty() || key.size() > SaveStore::kMaxKeyLength) return false;
    if (value.size() > SaveStore::kMaxValueLength) return false;
    return key.find('=') == std::string::npos && key.find('\n') == std::string::npos &&
           value.find('\n') == std::string::npos;
}

int hex_nibble(char c) {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
}

/// 删掉半份写出的临时文件（失败路径的清理；删不掉也没有更好的补救）。
/// 只删普通文件：临时文件位置被别的东西（例如目录）占住时不动它
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

} // namespace

bool SaveStore::open(const std::string& save_dir, const std::string& cart_id) {
    namespace fs = std::filesystem;
    data_.clear();
    path_ = (fs::path(save_dir) / (cart_id + ".sav")).string();
    writable_ = false;

    std::error_code ec;
    fs::create_directories(save_dir, ec);
    if (!ec) writable_ = probe_writable(path_ + ".tmp");

    std::error_code exists_ec;
    if (!fs::exists(path_, exists_ec)) return writable_;  // 新存档：空数据

    std::ifstream in(path_);
    if (!in) {
        // 旧档存在却读不出（权限/介质错误）：只读运行，绝不用空数据覆盖未知内容
        writable_ = false;
        return false;
    }
    std::string line;
    while (std::getline(in, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        const size_t eq = line.find('=');
        if (eq == std::string::npos) continue;
        const std::string key = line.substr(0, eq);
        const std::string value = line.substr(eq + 1);
        if (!entry_within_limits(key, value)) continue;  // 存档文件亦不可信
        if (data_.size() >= kMaxEntries && data_.find(key) == data_.end()) continue;
        data_[key] = value;
    }
    return true;
}

std::optional<std::string> SaveStore::get(const std::string& key) const {
    auto it = data_.find(key);
    if (it == data_.end()) return std::nullopt;
    return it->second;
}

bool SaveStore::set(const std::string& key, const std::string& value) {
    if (!writable_ || !entry_within_limits(key, value)) return false;

    auto it = data_.find(key);
    if (it == data_.end()) {
        if (data_.size() >= kMaxEntries) return false;
        data_.emplace(key, value);
        if (flush(data_)) return true;
        data_.erase(key);  // 写盘失败：回滚，内存保持与磁盘一致
        return false;
    }
    const std::string previous = it->second;
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

bool SaveStore::flush(const std::map<std::string, std::string>& data) const {
    const std::string tmp = path_ + ".tmp";
    std::ofstream out(tmp, std::ios::trunc);
    if (!out) return false;
    for (const auto& [key, value] : data) out << key << '=' << value << '\n';
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
    // 磁带码：key=value\n 拼接后的十六进制（保证纯文本可复制）
    static const char* kHex = "0123456789ABCDEF";
    std::string payload;
    for (const auto& [k, v] : data_) payload += k + "=" + v + "\n";

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
    std::map<std::string, std::string> parsed;
    size_t begin = 0;
    while (begin <= payload.size()) {
        const size_t end = payload.find('\n', begin);
        const std::string line =
            payload.substr(begin, end == std::string::npos ? std::string::npos : end - begin);
        if (!line.empty()) {
            const size_t eq = line.find('=');
            if (eq == std::string::npos) return false;
            const std::string key = line.substr(0, eq);
            const std::string value = line.substr(eq + 1);
            if (!entry_within_limits(key, value)) return false;
            if (parsed.size() >= kMaxEntries && parsed.find(key) == parsed.end()) return false;
            parsed[key] = value;
        }
        if (end == std::string::npos) break;
        begin = end + 1;
    }

    // 先写盘、成功了才换内存：失败时原内存与旧档都还在
    if (!flush(parsed)) return false;
    data_ = std::move(parsed);
    return true;
}

} // namespace phos

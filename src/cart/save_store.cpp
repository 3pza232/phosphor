#include "cart/save_store.hpp"

#include <cstdio>
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

} // namespace

bool SaveStore::open(const std::string& save_dir, const std::string& cart_id) {
    namespace fs = std::filesystem;
    std::error_code ec;
    fs::create_directories(save_dir, ec);

    path_ = (fs::path(save_dir) / (cart_id + ".sav")).string();
    // 目录建不出来（只读介质、权限不足）就让卡带以"只读存档"运行：
    // 读仍可用，写会被拒绝并如实回报失败，而不是假装存下了
    writable_ = !ec;

    std::ifstream in(path_);
    if (!in) return writable_;  // 新存档：空数据

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
    if (data_.size() >= kMaxEntries && data_.find(key) == data_.end()) return false;
    data_[key] = value;
    return flush();
}

bool SaveStore::erase(const std::string& key) {
    if (!writable_) return false;
    data_.erase(key);
    return flush();
}

bool SaveStore::flush() const {
    std::ofstream out(path_, std::ios::trunc);
    if (!out) return false;
    for (const auto& [k, v] : data_)
        out << k << '=' << v << '\n';
    return static_cast<bool>(out);
}

std::string SaveStore::export_code() const {
    // 磁带码：key=value\n 拼接后的十六进制（保证纯文本可复制）
    static const char* kHex = "0123456789ABCDEF";
    std::string payload;
    for (const auto& [k, v] : data_)
        payload += k + "=" + v + "\n";

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

    data_ = std::move(parsed);
    return flush();
}

} // namespace phos

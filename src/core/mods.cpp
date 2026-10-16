#include "core/mods.hpp"

#include <algorithm>

namespace phos {

namespace {

/// 覆盖表与禁用集合：由上层（App）在启动期一次性喂入，之后只读。
/// 覆盖表是纯数据（键→落盘路径），本层不扫描目录、不碰 Lua
struct Registry {
    std::vector<std::string> disabled;             // 被禁用的 mod id
    std::map<std::string, std::string> overrides;  // "<目标id>/<路径>" → 落盘路径
};

Registry& registry() {
    static Registry r;
    return r;
}

bool is_disabled(const Registry& r, const std::string& id) {
    return std::find(r.disabled.begin(), r.disabled.end(), id) != r.disabled.end();
}

} // namespace

std::string mod_override(const std::string& target_id, const std::string& rel_path) {
    if (target_id.empty() || rel_path.empty()) return {};
    const std::map<std::string, std::string>& overrides = registry().overrides;
    const auto it = overrides.find(target_id + "/" + rel_path);
    return it == overrides.end() ? std::string() : it->second;
}

void set_overrides(std::map<std::string, std::string> table) {
    registry().overrides = std::move(table);
}

void set_disabled(const std::vector<std::string>& ids) {
    registry().disabled = ids;
}

bool mod_enabled(const std::string& id) {
    return !is_disabled(registry(), id);
}

} // namespace phos

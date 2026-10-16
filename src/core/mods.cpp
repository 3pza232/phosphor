#include "core/mods.hpp"

#include "core/log.hpp"

#include <algorithm>
#include <filesystem>
#include <map>

namespace phos {

namespace {

namespace fs = std::filesystem;

/// 扫描结果：首次访问时构建一次，之后复用（Mod 是启动期加载的静态内容）。
/// 禁用集合可经 set_disabled 中途改写，故保留 built 标志做失效重建
struct Registry {
    bool built = false;
    std::vector<std::string> names;
    std::vector<std::string> disabled;             // 被禁用的 mod id（= 目标 id）
    std::map<std::string, std::string> overrides;  // "<目标id>/<路径>" → 落盘路径
};

Registry& registry() {
    static Registry r;
    return r;
}

bool is_disabled(const Registry& r, const std::string& id) {
    return std::find(r.disabled.begin(), r.disabled.end(), id) != r.disabled.end();
}

void build(Registry& r) {
    r.built = true;
    r.names.clear();
    r.overrides.clear();
    std::error_code ec;
    if (!fs::is_directory("mods", ec)) return;

    // 扁平规则：`mods/` 下的相对路径**本身就是覆盖键** `<目标id>/<目标内路径>`，
    // 不再有 `overrides/` 与"随意命名的 mod 外层"。例：
    //   mods/snake/panel.lua      → 覆盖 snake 的 panel.lua
    //   mods/default/font.lua     → 覆盖 default 字体方案
    //   mods/graphite/skin.lua    → 覆盖 graphite 主题
    // 一个键在一个文件系统里只有一份 → 不再有"多 mod 叠层"，也就没有"谁盖谁"的歧义。
    std::vector<std::string> tops;
    for (fs::recursive_directory_iterator it("mods", ec), end; it != end && !ec; it.increment(ec)) {
        if (!it->is_regular_file(ec)) continue;
        const fs::path rel = fs::relative(it->path(), "mods", ec);
        if (rel.empty()) continue;
        // 键必须形如 "<目标id>/<路径>"：根目录下的裸文件（只有一段）定位不到目标，忽略
        const std::string key = rel.generic_string();
        if (key.find('/') == std::string::npos) continue;
        std::string top = rel.begin()->string();  // 顶层第一段 = 目标 id = mod id
        if (std::find(tops.begin(), tops.end(), top) == tops.end()) tops.push_back(top);
        // 被禁用的 mod 仍然列出（UI 要能管理），但它的覆盖不进入查表
        if (is_disabled(r, top)) continue;
        r.overrides[key] = it->path().generic_string();
    }

    std::sort(tops.begin(), tops.end());
    r.names = std::move(tops);
    if (!r.names.empty()) {
        std::string list;
        for (const std::string& n : r.names) {
            if (!list.empty()) list += ", ";
            list += n;
            if (is_disabled(r, n)) list += " (disabled)";
        }
        log::info("mods loaded: " + list);
    }
}

} // namespace

std::string mod_override(const std::string& target_id, const std::string& rel_path) {
    if (target_id.empty() || rel_path.empty()) return {};
    Registry& r = registry();
    if (!r.built) build(r);
    const auto it = r.overrides.find(target_id + "/" + rel_path);
    return it == r.overrides.end() ? std::string() : it->second;
}

const std::vector<std::string>& mod_names() {
    Registry& r = registry();
    if (!r.built) build(r);
    return r.names;
}

void set_disabled(const std::vector<std::string>& ids) {
    Registry& r = registry();
    r.disabled = ids;
    r.built = false;  // 覆盖表依赖禁用集合：下次访问时重建
}

bool mod_enabled(const std::string& id) {
    Registry& r = registry();
    if (!r.built) build(r);
    return !is_disabled(r, id);
}

} // namespace phos

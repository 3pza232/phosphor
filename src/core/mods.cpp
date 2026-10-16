#include "core/mods.hpp"

#include "core/log.hpp"

#include <algorithm>
#include <filesystem>
#include <map>

namespace phos {

namespace {

namespace fs = std::filesystem;

/// 扫描结果：首次访问时构建一次，之后复用（Mod 是启动期加载的静态内容）
struct Registry {
    bool built = false;
    std::vector<std::string> names;
    std::map<std::string, std::string> overrides;  // "<目标id>/<路径>" → 落盘路径
};

Registry& registry() {
    static Registry r;
    return r;
}

void build(Registry& r) {
    r.built = true;
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
        std::string top = rel.begin()->string();  // 顶层第一段 = 目标 id；日志按它归类
        if (std::find(tops.begin(), tops.end(), top) == tops.end()) tops.push_back(top);
        r.overrides[key] = it->path().generic_string();
    }

    std::sort(tops.begin(), tops.end());
    r.names = std::move(tops);
    if (!r.names.empty()) {
        std::string list;
        for (const std::string& n : r.names) list += (list.empty() ? "" : ", ") + n;
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

} // namespace phos

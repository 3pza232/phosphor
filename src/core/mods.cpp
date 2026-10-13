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
    std::map<std::string, std::string> overrides;  // "<目标id>/<路径>" → 落盘路径（后到者胜）
};

Registry& registry() {
    static Registry r;
    return r;
}

void build(Registry& r) {
    r.built = true;
    std::error_code ec;
    if (!fs::is_directory("mods", ec)) return;

    for (fs::directory_iterator it("mods", ec), end; it != end && !ec; it.increment(ec)) {
        if (it->is_directory(ec)) r.names.push_back(it->path().filename().string());
    }
    std::sort(r.names.begin(), r.names.end());  // 目录名排序 = 应用顺序（后者覆盖前者）

    for (const std::string& name : r.names) {
        const fs::path over = fs::path("mods") / name / "overrides";
        if (!fs::is_directory(over, ec)) continue;
        for (fs::recursive_directory_iterator it(over, ec), end; it != end && !ec; it.increment(ec)) {
            if (!it->is_regular_file(ec)) continue;
            // 键 = 相对 overrides/ 的路径（即 "<目标id>/<目标内路径>"）
            const std::string key = fs::relative(it->path(), over, ec).generic_string();
            if (!key.empty()) r.overrides[key] = it->path().generic_string();  // 后到者胜
        }
    }

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

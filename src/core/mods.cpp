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
    std::vector<std::string> names;                // 全部 mod id（= 文件夹名，按名排序）
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

void build(Registry& r) {
    r.built = true;
    r.names.clear();
    r.overrides.clear();
    std::error_code ec;
    if (!fs::is_directory("mods", ec)) return;

    // 每个 mod 是一个**有名字的文件夹**：文件夹名即 mod id，`mods/` 下只认文件夹。
    // 先收齐 id 并排序——列表顺序与应用顺序（撞键时谁覆盖谁）都由它定，跨机器一致
    for (fs::directory_iterator it("mods", ec), end; it != end && !ec; it.increment(ec)) {
        if (!it->is_directory(ec)) continue;
        r.names.push_back(it->path().filename().string());
    }
    std::sort(r.names.begin(), r.names.end());

    // 覆盖内容镜像目标结构放在 `<mod-id>/` 之下，覆盖键取 mod-id **之后**的相对路径：
    //   mods/font-resize/default/font.lua → 键 default/font.lua
    //   mods/snake-tweaks/snake/panel.lua → 键 snake/panel.lua
    // `mod.lua` 清单与任何"只有一段"的裸文件都定位不到目标（键须形如 "<目标id>/<路径>"），
    // 由下面那条 "无斜杠即忽略" 一并挡掉。禁用 mod 仍列出（UI 要能管理），覆盖不入表。
    for (const std::string& id : r.names) {
        if (is_disabled(r, id)) continue;
        const fs::path root = fs::path("mods") / id;
        for (fs::recursive_directory_iterator it(root, ec), end; it != end && !ec; it.increment(ec)) {
            if (!it->is_regular_file(ec)) continue;
            const fs::path rel = fs::relative(it->path(), root, ec);
            if (rel.empty()) continue;
            const std::string key = rel.generic_string();
            if (key.find('/') == std::string::npos) continue;
            // 命名化后两个 mod 可能撞同一个键：按 id 字典序后处理的覆盖先前的，并留痕。
            // 旧布局"一个键只有一份"的保证不再成立，碰撞必须可见而不是静默丢弃
            if (r.overrides.count(key) != 0)
                log::warn("mod override collision on '" + key + "' (mod '" + id + "' wins)");
            r.overrides[key] = it->path().generic_string();
        }
    }

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

#pragma once

#include <string>
#include <vector>

namespace phos {

/// 覆盖层 Mod 的**唯一查找处**（规范见 docs/content-packs.md）。
///
/// Mod = `mods/<目标id>/`，默认**自动生效**（扫描到即应用）。开关（启用/禁用）是
/// 后来加的一维：被禁用的 Mod 其覆盖**不再进入查表**（按 `mods/<目标id>/` 的
/// `<目标id>` 判定），但仍在 `mod_names()` 里列出——UI 才能把它再打开。
///
/// 一个 mod 可以覆盖多个目标，覆盖项放在 `mods/<目标id>/` 下按 `<目标内路径>` 存放：
///
///   mods/<目标id>/<目标内路径>
///
/// `<目标id>` 是内容包的文件夹名、字体方案名或卡带 id；`<目标内路径>` 与包内一致
/// （如 `font.lua` / `skin.lua` / `panel.lua` / `assets/map.txt`）。卡带的 `manifest.lua`
/// 不可覆盖（身份须稳定）。
///
/// 这里只做**路径解析**（不碰 Lua，故放 core/ 让 pack/ 与 cart/ 都能用）；mod 的元数据
/// （`mod.lua`：名字 / 作者 / 说明）由更上层按需解析。
std::string mod_override(const std::string& target_id, const std::string& rel_path);

/// 已加载的 mod 目录名（按目录名排序 = 应用顺序）。**含被禁用的**——
/// "有哪些 mod"与"哪些生效"是两件事，UI 需要前者才能管理后者
const std::vector<std::string>& mod_names();

/// 设置被禁用的 mod id 集合并触发重建。必须在内容扫描（`packs_.scan` / `set_carts`）
/// **之前**调用：扫描结果会被覆盖层影响，晚了就来不及
void set_disabled(const std::vector<std::string>& ids);

/// 该 mod 是否生效（未在禁用集合里）
bool mod_enabled(const std::string& id);

} // namespace phos

#pragma once

#include <string>
#include <vector>

namespace phos {

/// 覆盖层 Mod 的**唯一查找处**（规范见 docs/content-packs.md §六）。
///
/// Mod = `mods/` 下的一个**有名字的文件夹**，文件夹名就是它的 id。文件夹内镜像要覆盖的
/// 目标结构，可选带一份 `mod.lua` 清单（显示名/说明，**不参与**覆盖路径）：
///
///   mods/<mod-id>/mod.lua               可选清单：return { name = {..}, desc = {..} }
///   mods/<mod-id>/<目标id>/<目标内路径>   覆盖内容
///
/// 覆盖键取 `<mod-id>` **之后**的相对路径 `<目标id>/<目标内路径>`（例：
/// `mods/font-resize/default/font.lua` → 键 `default/font.lua`）。放进去默认**自动生效**；
/// 开关（启用/禁用）按 **mod-id** 判定：被禁 mod 的覆盖不再进入查表，但仍列在
/// `mod_names()` 里——UI 才能把它再打开。
///
/// `<目标id>` 是内容包的文件夹名、字体方案名或卡带 id；`<目标内路径>` 与包内一致
/// （如 `font.lua` / `skin.lua` / `panel.lua` / `assets/map.txt`）。卡带的 `manifest.lua`
/// 不可覆盖（身份须稳定）。
///
/// 这里只做**路径解析**（不碰 Lua，故放 core/ 让 pack/ 与 cart/ 都能用）；mod 的元数据
/// （`mod.lua`：名字 / 说明）由 pack 层按需解析（见 pack/pack.hpp 的 `scan_mods`）。
std::string mod_override(const std::string& target_id, const std::string& rel_path);

/// 已加载的 mod id（= 文件夹名，按名排序 = 应用顺序）。**含被禁用的**——
/// "有哪些 mod"与"哪些生效"是两件事，UI 需要前者才能管理后者
const std::vector<std::string>& mod_names();

/// 设置被禁用的 mod id 集合并触发重建。必须在内容扫描（`packs_.scan` / `set_carts`）
/// **之前**调用：扫描结果会被覆盖层影响，晚了就来不及
void set_disabled(const std::vector<std::string>& ids);

/// 该 mod 是否生效（未在禁用集合里）
bool mod_enabled(const std::string& id);

} // namespace phos

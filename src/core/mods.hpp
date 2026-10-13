#pragma once

#include <string>
#include <vector>

namespace phos {

/// 覆盖层 Mod 的**唯一查找处**（规范见 docs/content-packs.md）。
///
/// Mod = `mods/<任意名>/`，**自动生效**（扫描到即应用，没有开关、也没有"方案"之分）。
/// 一个 mod 可以覆盖多个目标，覆盖项放在 `overrides/` 下、按目标的 id 分目录：
///
///   mods/<名>/overrides/<目标id>/<目标内路径>
///
/// `<目标id>` 是内容包的文件夹名、字体方案名或卡带 id；`<目标内路径>` 与包内一致
/// （如 `font.lua` / `skin.lua` / `panel.lua` / `assets/map.txt`）。多个 mod 同时改同一个
/// 文件时，按 **mod 目录名排序**，后者覆盖前者。卡带的 `manifest.lua` 不可覆盖（身份须稳定）。
///
/// 这里只做**路径解析**（不碰 Lua，故放 core/ 让 pack/ 与 cart/ 都能用）；mod 的元数据
/// （`mod.lua`：名字 / 作者 / 说明）由更上层按需解析。
std::string mod_override(const std::string& target_id, const std::string& rel_path);

/// 已加载的 mod 目录名（按目录名排序 = 应用顺序）
const std::vector<std::string>& mod_names();

} // namespace phos

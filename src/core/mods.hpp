#pragma once

#include <map>
#include <string>
#include <vector>

namespace phos {

/// 覆盖层 Mod 的**唯一查找处**（规范见 docs/content-packs.md §六）。
///
/// Mod 是 `mods/` 下的一个文件夹，文件夹名即 mod-id。文件夹里放该 mod 独有的内容
/// （扁平，文件名自由）+ 一份必需清单 `mod.lua`，由清单**显式声明**它的内容覆盖到哪里：
///
///   mods/<mod-id>/mod.lua          return { name=…, desc=…, overrides = {
///                                    ["<目标id>/<包内路径>"] = "本 mod 内的文件", … } }
///   mods/<mod-id>/<任意文件名>      被 overrides 指向的内容（可放子目录）
///
/// 覆盖键仍是 `<目标id>/<包内路径>`（目标 id = 内容包文件夹名 / 字体方案名 / 卡带 id），
/// 于是 `mod_override(target_id, rel_path)` 的查询接口与内容包/卡带那边的调用都**不变**。
///
/// 覆盖表**不在本层解析**：`mod.lua` 是 Lua，读它、按启用集过滤、按 mod-id 字典序叠加
/// 都归 pack 层（`pack::scan_mods`，复用其最小沙箱）。本层只管"喂进来的表怎么查"，
/// 因此不依赖 Lua，可同时被 pack/ 与 cart/ 链接。
std::string mod_override(const std::string& target_id, const std::string& rel_path);

/// 用外部解析好的覆盖表整体替换当前表（键 = `<目标id>/<包内路径>`，值 = 覆盖文件的
/// 落盘路径）。表已由 `pack::scan_mods` 按启用集过滤、按 mod-id 字典序叠加（后覆盖前）。
/// 必须在内容扫描（`packs_.scan` / `set_carts` / 字体方案扫描）**之前**调用：扫描结果
/// 会被覆盖表影响，晚了就来不及
void set_overrides(std::map<std::string, std::string> table);

/// 设置被禁用的 mod id 集合。语义照旧：被禁 mod 的覆盖**不生效**——过滤在
/// `pack::scan_mods` 里据 `mod_enabled` 完成（core 不扫描、不碰 Lua），这里只记录集合
void set_disabled(const std::vector<std::string>& ids);

/// 该 mod 是否生效（未在禁用集合里）
bool mod_enabled(const std::string& id);

} // namespace phos

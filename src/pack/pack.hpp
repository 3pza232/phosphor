#pragma once

#include "core/audio.hpp"
#include "core/defaults.hpp"
#include "core/palette.hpp"
#include "core/skin.hpp"

#include <map>
#include <string>
#include <vector>

namespace phos {

/// 扫描 theme/palette/ 下全部显像管色板包。损坏包跳过
/// （调用方保证列表非空，空列表时用 builtin_palette() 兜底）。
std::vector<Palette> scan_palettes(const std::string& dir);

/// 解析单个 palette 包目录（只需 palette.lua；显示名取文件夹名）。
/// warnings 非空时收集"可回退的声明问题"（类型不对等）：扫描路径不传，行为不变；
/// DevKit 的 --check-packs 用它把坏包原因列出来
bool load_palette(const std::string& dir, Palette& out, std::string& err,
                  std::vector<std::string>* warnings = nullptr);

/// 扫描 theme/skin/ 下全部游戏机主题包
std::vector<Skin> scan_skins(const std::string& dir);

/// 启动动画包（只需 main.lua，脚本与卡带同构）
struct BootPack {
    std::string id;
    std::string name;
    std::string dir;
};

/// 扫描 theme/boot/ 下全部启动动画包
std::vector<BootPack> scan_boots(const std::string& dir);
/// 解析单个启动动画包目录（只做结构检查：main.lua 必须存在；脚本能否执行由调用方用沙箱验证）
bool load_boot(const std::string& dir, BootPack& out, std::string& err);

/// 卡带架样式包（只需 shelf.lua：可选 update(dt)，必须有 draw(ctx)）
struct ShelfPack {
    std::string id;
    std::string name;  // 显示名回退 = 文件夹名（设置里没声明本地化名时用它）
    /// 顶层声明的本地化显示名：`name = "GRID"` 或 `name = { zh = "卡片墙", en = "GRID" }`。
    /// 读不到（坏包 / 没声明）时留空，由调用方回落到 `name`
    std::string name_zh;
    std::string name_en;
    /// 顶层声明的二维列数：`cols = 4`。主机据它把上下键映射为逐行移动（0 = 未声明）
    int cols = 0;
    std::string dir;
};

/// 扫描 theme/shelf/ 下全部卡带架样式包
std::vector<ShelfPack> scan_shelves(const std::string& dir);
/// 解析单个卡带架样式包目录（只读声明：shelf.lua 存在、顶层 name/cols 类型；draw(ctx)
/// 契约由 Cartridge::load_shelf 验证——扫描路径不传 warnings，行为不变）
bool load_shelf_pack(const std::string& dir, ShelfPack& out, std::string& err,
                     std::vector<std::string>* warnings = nullptr);

/// 一条覆盖层 Mod 的**清单**（`mods/<id>/mod.lua`，必需）。
/// 清单既提供 UI 显示名/说明，也**显式声明**本 mod 的内容覆盖到哪里（overrides）
struct ModManifest {
    std::string id;       // 文件夹名（= mod id）
    std::string name_zh;  // 显示名；缺省回落文件夹名，故非空
    std::string name_en;
    std::string desc_zh;  // 说明（可空）
    std::string desc_en;
    bool default_off = false;  // 清单声明 `default_off = true`：出厂默认关闭
    bool enabled = true;       // 有效启用态（据 default_off + 两个配置列表算出）
};

/// `mods/` 的扫描结果：可管理的 mod 清单 + 已建好的覆盖表
struct ModScan {
    /// 全部**有有效 mod.lua** 的 mod（含未启用的，UI 才能再开）；按 id 字典序
    std::vector<ModManifest> mods;
    /// 覆盖表：键 `<目标id>/<包内路径>` → 覆盖文件的落盘路径。
    /// 已按启用集过滤（未启用的不进表）、按 mod-id 字典序叠加（同键后者覆盖前者）
    std::map<std::string, std::string> overrides;
};

/// 扫描 `mods/` 下全部 mod：读 `mod.lua` 的 `name`/`desc`/`default_off`/`overrides`。
/// 「是否生效」按 `core::mod_enabled(id, default_off)` 判定（需先 `set_disabled`/`set_enabled`）。
/// 没有 `mod.lua`、读不出表、或**没有 `overrides` 表**的文件夹都不算 mod——`log::warn`
/// 后跳过（不再有"路径即键"的隐式规则）；`overrides` 为空表 = 只登记、不覆盖。
/// 覆盖键非法（缺 `<目标id>/<路径>` 形态）、值指向的文件不存在等条目跳过并告警。
/// 显示名一律以文件夹名兜底，故读不到 name 也照常列出
ModScan scan_mods();

/// 音效包：主机事件 → 合成参数（或包内音频文件）
struct SoundPack {
    std::string id;
    std::string name;
    std::string dir;
    std::map<std::string, ToneSpec> tones;    // 事件名 → 合成音
    std::map<std::string, std::string> files; // 事件名 → 包内音频路径（优先于合成音）
};

/// 扫描 theme/sound/ 下全部音效包
std::vector<SoundPack> scan_sounds(const std::string& dir);
/// 解析单个音效包目录（sounds.lua 必须存在且返回表；warnings 非空时收集可跳过的条目问题）
bool load_sound(const std::string& dir, SoundPack& out, std::string& err,
                std::vector<std::string>* warnings = nullptr);

/// 解析单个 skin 包目录（只需 skin.lua）。warnings 语义同 load_palette。
bool load_skin(const std::string& dir, Skin& out, std::string& err,
               std::vector<std::string>* warnings = nullptr);

/// 一套字体方案（`theme/font/<名称>/`）。文件夹名即方案名（与其它内容包同一约定）
struct FontScheme {
    std::string name;                // 方案名 = 文件夹名
    std::vector<std::string> files;  // 回退顺序（首个为主字体；默认顺序由 core/font_files 给出）
    int size = 0;                    // 方案声明的字号（像素）；0 = 未声明（用全局默认）
    int min_size = kMinFontPx;       // 可调范围下限（方案声明；缺省 12）
    int max_size = kMaxFontPx;       // 可调范围上限（方案声明；缺省 24；Mod 可抬高，硬上限 kMaxFontPxCeiling）
};

/// 扫描 `theme/font/` 下全部字体方案（含字体文件的子目录），`default` 排最前。
/// 方案里的 `font.lua`（可选）显式声明：
///   return { size = 16, min = 12, max = 24, order = { "font", "font-cn" } }
/// `size` 是默认字号，`min`/`max` 是设置界面可调范围（`max` 抬高即"更大字号"，Mod 可覆盖）。
/// `order` 按 stem 或文件名给出回退顺序，未列出的文件按默认规则附在其后。
/// 默认规则由 `core/font_files` 的 `font_files_in_scheme` 给出：只收 .ttf/.otf/.ttc，
/// stem 为 `font` 的主字体在前，其余按文件名排序。没有 `font.lua` 时整套用它；
/// 坏脚本留痕并按文件名规则继续
std::vector<FontScheme> scan_font_schemes(const std::string& dir);

/// 解析单个字体方案目录（字体文件枚举 + 可选 font.lua）。目录里没有任何字体文件时
/// 返回 false 并填 err；font.lua 坏掉只进 warnings（按文件名规则继续，与扫描一致）
bool load_font_scheme(const std::string& dir, FontScheme& out, std::string& err,
                      std::vector<std::string>* warnings = nullptr);

} // namespace phos

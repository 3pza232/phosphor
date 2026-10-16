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
bool load_palette(const std::string& dir, Palette& out, std::string& err);

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

/// 卡带架样式包（只需 shelf.lua：可选 update(dt)，必须有 draw(ctx)）
struct ShelfPack {
    std::string id;
    std::string name;
    std::string dir;
};

/// 扫描 theme/shelf/ 下全部卡带架样式包
std::vector<ShelfPack> scan_shelves(const std::string& dir);

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

/// 解析单个 skin 包目录（只需 skin.lua）。
bool load_skin(const std::string& dir, Skin& out, std::string& err);

/// 一套字体方案（`theme/font/<名称>/`）。文件夹名即方案名（与其它内容包同一约定）
struct FontScheme {
    std::string name;                // 方案名 = 文件夹名
    std::vector<std::string> files;  // 回退顺序（首个为主字体）
    int size = 0;                    // 方案声明的字号（像素）；0 = 未声明（用全局默认）
    int min_size = kMinFontPx;       // 可调范围下限（方案声明；缺省 12）
    int max_size = kMaxFontPx;       // 可调范围上限（方案声明；缺省 24；Mod 可抬高，硬上限 kMaxFontPxCeiling）
};

/// 扫描 `theme/font/` 下全部字体方案（含字体文件的子目录），`default` 排最前。
/// 方案里的 `font.lua`（可选）显式声明：
///   return { size = 16, min = 12, max = 24, order = { "font", "font-cn" } }
/// `size` 是默认字号，`min`/`max` 是设置界面可调范围（`max` 抬高即"更大字号"，Mod 可覆盖）。
/// `order` 按 stem 或文件名给出回退顺序，未列出的文件按默认规则（主字体在前、其余按名排序）
/// 附在其后。没有 `font.lua` 时整套回退到文件名规则。坏脚本留痕并按文件名规则继续
std::vector<FontScheme> scan_font_schemes(const std::string& dir);

} // namespace phos

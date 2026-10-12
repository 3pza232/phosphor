#pragma once

#include "core/audio.hpp"
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

} // namespace phos

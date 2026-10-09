#pragma once

#include "core/defaults.hpp"

#include <string>

namespace phos {

/// 机台配置（程序目录 config.json）。字段固定且扁平，手写极简 JSON 读写。
struct Config {
    std::string skin = "default";        // 游戏机主题（skin 包 id）
    std::string filter = "none";         // 显像管滤镜（"none" = 原色原样）
    std::string boot = "default";        // 启动动画包 id
    std::string sound = "default";       // 音效包 id
    std::string font = "default";        // 字体方案（theme/font/<名称>/）
    std::string language = "zh";         // 界面语言（"zh" / "en"，见 shell/messages.hpp）
    std::string shelf_style = "window";  // 卡带架样式：list / window
    int crt_level = kDefaultCrtLevel;      // 扫描线档位（见 core/crt.hpp）
    int music_volume = kDefaultMusicVolume;  // 音乐音量 0~100（音序器产出）
    int sfx_volume = kDefaultSfxVolume;      // 音效音量 0~100（beep/音符/采样）
};

/// 读取配置；文件不存在/损坏时返回默认值（安静回退）
Config load_config(const std::string& path);

/// 写入配置（设置变更时即时保存——"记忆性"）
void save_config(const std::string& path, const Config& cfg);

} // namespace phos

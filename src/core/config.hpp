#pragma once

#include "core/defaults.hpp"

#include <string>
#include <vector>

namespace phos {

/// 机台配置（程序目录 config.json）。字段固定且扁平，手写极简 JSON 读写。
struct Config {
    std::string skin = "default";        // 游戏机主题（连内容色板一起，见 skin.palette）
    std::string boot = "default";        // 启动动画包 id
    std::string sound = "default";       // 音效包 id
    std::string font = "default";        // 字体方案（theme/font/<名称>/）
    std::string language = "zh";         // 界面语言（"zh" / "en"，见 shell/messages.hpp）
    std::string shelf_style = "window";  // 卡带架样式：list / window / 某个 shelf 包 id
    /// 字号 = 单元格像素边长（整机字符与行距随之缩放）：0 = 跟随字体方案声明的字号
    /// （方案没声明则用 kDefaultFontPx）；正数 = 用户显式选择（钳到 [kMinFontPx, kMaxFontPx]）
    int font_size = 0;
    int crt_level = kDefaultCrtLevel;      // 扫描线档位（见 core/crt.hpp）
    int fps = kDefaultFps;                 // 画面刷新率上限（档位见 defaults.hpp 的 kFpsChoices）
    int music_volume = kDefaultMusicVolume;  // 音乐音量 0~100（音序器产出）
    int sfx_volume = kDefaultSfxVolume;      // 音效音量 0~100（beep/音符/采样）
    /// 被禁用的 Mod id（= `mods/<id>/` 的 `<id>`，见 core/mods.hpp）。空 = 默认开的都生效。
    /// 默认关闭的 Mod（`mod.lua` 里 `default_off = true`）不看这一份，看 `mods_enabled`
    std::vector<std::string> mods_disabled;
    /// 显式启用的"默认关闭"Mod id。空 = 所有默认关的都保持关着
    std::vector<std::string> mods_enabled;
};

/// 读取配置；文件不存在/损坏时返回默认值（安静回退）
Config load_config(const std::string& path);

/// 写入配置（设置变更时即时保存——"记忆性"）
void save_config(const std::string& path, const Config& cfg);

/// 卡带架的"最近打开"记录：一行一个卡带 id，最近打开的在最前。
/// 与 config.json 分开存：那份是**人写的设置**，这份是**机器写的使用痕迹**，
/// 混在一起会让人以为手改 config.json 就能改排序
std::vector<std::string> load_recent(const std::string& path);

/// 记一次打开：把 cart_id 提到最前（去重、截到上限）并立即落盘。
/// 写不进去只记日志——排序退化回目录顺序，不该拦住启动
void remember_recent(const std::string& path, const std::string& cart_id);

} // namespace phos

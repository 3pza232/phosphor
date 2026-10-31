#pragma once

#include "core/defaults.hpp"
#include "shell/messages.hpp"
#include "ui/element.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace phos {

/// 设置项的标识：顺序即为界面顺序（分区标题穿插其中，不参与选中）
enum class SettingId {
    theme,         // 游戏机主题（连内容色板一起）
    font,          // 字体方案
    font_size,     // 字号（= 单元格像素边长）
    scanlines,     // 扫描线档位
    fps,           // 画面刷新率（逻辑帧率恒定，见 defaults.hpp 的 kFpsChoices）
    sound_pack,    // 音效包
    music_volume,  // 音乐音量
    sfx_volume,    // 音效音量
    boot,          // 启动动画
    shelf_view,    // 卡带架样式
    language,      // 界面语言
    back,          // 返回
    count
};

/// 设置界面构建所需的只读状态
struct SettingsContext {
    std::vector<std::string> skins, fonts, boots, sounds;
    int skin_index = 0, font_index = 0, boot_index = 0, sound_index = 0;
    int crt_level = kDefaultCrtLevel;
    int fps = kDefaultFps;
    int music_volume = kDefaultMusicVolume, sfx_volume = kDefaultSfxVolume;
    /// 卡带架样式候选项与当前项：`[LIST, WINDOW, <shelf 包名…>]`，
    /// index 0 = list、1 = window、2+i = 第 i 个 shelf 包
    std::vector<std::string> shelves;
    int shelf_index = 1;
    int font_px = kDefaultFontPx;  // 当前生效字号（= 单元格边长）
    Lang lang = Lang::zh;  // 界面语言：设置界面自己的文案也要跟着切
};

/// 设置项在界面上的稳定 id（焦点/事件/agent 观测都以它为键）："settings/<key>"
const char* setting_key(SettingId id);
/// 由元素 id 反解设置项；不是设置行返回 SettingId::count
SettingId setting_from_key(std::string_view key);
/// 可选中项在界面顺序里的下标（0 基）；不是可选项返回 -1
int setting_item_index(SettingId id);

/// 把设置界面声明成一棵元素树（坐标由容器排布；预览框绝对定位在底部）。
/// area 是整块可用区域（决定预览框位置），root 由调用方创建。
void build_settings(ui::Node& root, const SettingsContext& ctx, const ui::Rect& area);

/// 可选中项数量（不含分区标题）
constexpr int settings_item_count() { return static_cast<int>(SettingId::count); }

} // namespace phos

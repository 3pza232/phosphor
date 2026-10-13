#pragma once

#include "core/defaults.hpp"
#include "core/screen.hpp"
#include "core/ui.hpp"
#include "shell/messages.hpp"

#include <string>
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

/// 设置界面渲染所需的只读状态
struct SettingsContext {
    std::vector<std::string> skins, fonts, boots, sounds;
    int skin_index = 0, font_index = 0, boot_index = 0, sound_index = 0;
    int crt_level = kDefaultCrtLevel;
    int fps = kDefaultFps;
    int music_volume = kDefaultMusicVolume, sfx_volume = kDefaultSfxVolume;
    bool window_style = true;
    int font_px = kDefaultFontPx;  // 当前生效字号（= 单元格边长）
    Lang lang = Lang::zh;  // 界面语言：设置界面自己的文案也要跟着切
    int lang_index = 0;    // 语言在可选列表里的下标（0 = 中文，1 = 英文）
};

/// 设置界面渲染（分区标题用暗色小标题，选项缩进显示）
void draw_settings(Screen& screen, const ui::Rect& content, const SettingsContext& ctx,
                   const ui::Style& style, int cursor);

/// 可选中项数量（不含分区标题）
constexpr int settings_item_count() { return static_cast<int>(SettingId::count); }



} // namespace phos

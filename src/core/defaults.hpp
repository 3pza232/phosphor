#pragma once

namespace phos {

/// 跨模块共享的可调常量。任何被两个以上模块使用的数值都应定义在这里，
/// 避免同一语义在多处重复（这是"不硬编码"的落点）。
inline constexpr int kContentW = 80;    // 卡带内容区宽（字符格）
inline constexpr int kContentH = 45;    // 卡带内容区高
inline constexpr int kPanelMaxW = 32;   // 侧栏面板最大宽度
inline constexpr int kCellPx = 16;      // 单元格像素边长
inline constexpr int kLogicFps = 60;    // 逻辑帧率

/// 卡带存档目录（默认；可用 --save-dir 改到别处，工具脚本据此隔离）
inline constexpr const char* kSaveDir = "saves";

inline constexpr float kBootDuration = 3.2f;  // 开机动画时长（秒）
inline constexpr int kVolumeStep = 10;        // 音量调节步长

// 出厂默认（配置初始值、界面显示、音频引擎兜底共用同一组数）
inline constexpr int kDefaultCrtLevel = 2;      // 扫描线档位（MEDIUM）
inline constexpr int kDefaultMusicVolume = 70;  // 音乐音量 0~100
inline constexpr int kDefaultSfxVolume = 85;    // 音效音量 0~100

} // namespace phos

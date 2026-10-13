#pragma once

#include <cstdint>

namespace phos {

/// 卡带可调参数的类型（`phos.debug.number / integer / toggle`）：控制台据此画浮点滑条 /
/// 整数滑条 / 复选框。放 core/ 是因为它要同时被 cart/（登记）与 agent/（渲染）用到，
/// 而两者互不依赖，只能共用一个低层类型
enum class DebugKind { number, integer, boolean };

/// 跨模块共享的可调常量。任何被两个以上模块使用的数值都应定义在这里，
/// 避免同一语义在多处重复（这是"不硬编码"的落点）。
inline constexpr int kContentW = 80;    // 卡带内容区宽（字符格）
inline constexpr int kContentH = 45;    // 卡带内容区高
inline constexpr int kPanelMaxW = 32;   // 侧栏面板最大宽度
inline constexpr int kMaxPadCols = 4096;  // phos.text.pad/pad_left 的列数上限：坏值不该撑爆内存
/// 单个内容文件（卡带素材 / 音效包采样）的读取上限：整读进内存的素材不该无上限
/// （见 roadmap 第 8 条）。卡带素材走 CartFiles::read，音效包采样在 App 侧先查大小
inline constexpr std::uintmax_t kMaxAssetBytes = 8u * 1024 * 1024;

/// 面板宽度的唯一合法化点：负数按收起（0）算，超上限按上限算。
/// 面板宽度是与主机共享的布局量（分隔线、面板局部坐标都跟着它走），
/// 所以钳制只写一份——两处各写一套，迟早对同一个输入给出两个结果
inline int clamp_panel_w(int w) { return w < 0 ? 0 : (w > kPanelMaxW ? kPanelMaxW : w); }
inline constexpr int kCellPx = 16;      // 默认单元格像素边长（= 默认字号）
inline constexpr int kLogicFps = 60;    // 逻辑帧率（游戏速度由它定，不随"帧率"设置变）

/// 字号 = **单元格像素边长**：它就是整台机器字符的大小，行距（格高）随之缩放——
/// 字号小则行距紧、字号大则行距松，不会出现"小字行距过宽 / 大字上下相碰"。范围与默认
/// 放这里，"配置校验""设置界面""字体方案默认"三处读同一份
inline constexpr int kMinFontPx = 12;    // 最小字号（再小几乎看不清）
inline constexpr int kMaxFontPx = 24;    // 最大字号（再大窗口就偏大）
inline constexpr int kDefaultFontPx = kCellPx;  // 出厂字号（= 默认格宽）

/// "帧率"设置的可选档位：每秒最多刷新多少次**画面**。逻辑帧率恒为 kLogicFps，
/// 所以这个档位只改刷新率与 CPU 占用，**不改游戏速度**：30 更省电、更有老机器的顿感，
/// 120/180 让 CRT 后处理与镜头平移更顺（高刷屏上才看得出来）。
/// 档位表放在这里，是为了让"配置校验"与"设置界面"读同一份，不再各写一套
inline constexpr int kFpsChoices[] = {30, 60, 120, 180};
inline constexpr int kFpsChoiceCount = 4;
inline constexpr int kDefaultFps = 60;  // 出厂默认：实机刷新率

/// 卡带存档目录（默认；可用 --save-dir 改到别处，工具脚本据此隔离）
inline constexpr const char* kSaveDir = "saves";

inline constexpr float kBootDuration = 3.2f;  // 开机动画时长（秒）
inline constexpr int kVolumeStep = 10;        // 音量调节步长

// 出厂默认（配置初始值、界面显示、音频引擎兜底共用同一组数）
inline constexpr int kDefaultCrtLevel = 2;      // 扫描线档位（MEDIUM）
inline constexpr int kDefaultMusicVolume = 70;  // 音乐音量 0~100
inline constexpr int kDefaultSfxVolume = 85;    // 音效音量 0~100

} // namespace phos

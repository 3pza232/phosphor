#pragma once

#include "cart/save_store.hpp"
#include "core/defaults.hpp"
#include "core/input.hpp"
#include "core/layered_screen.hpp"
#include "core/palette.hpp"
#include "core/screen.hpp"
#include "core/text.hpp"

#include <functional>
#include <random>

namespace sol { class state; }

namespace phos {

class Audio;
class CartFiles;
struct CartInfo;

/// 主机运行时上下文：API 层与 App 之间的共享状态。
/// 由 App 持有并随帧更新，API 函数捕获其引用。
struct HostContext {
    Screen* screen = nullptr;
    Input* input = nullptr;
    const Palette* palette = nullptr;   // 激活滤镜（phos.color 常量的来源）
    SaveStore* save = nullptr;          // 卡带存档（未声明 save 时为 nullptr）
    Audio* audio = nullptr;             // 音频子系统（可能为静音降级态）
    const CartFiles* cart_files = nullptr;  // 当前卡带包（读取包内音频等资源）
    const CartInfo* cart_info = nullptr;    // 当前卡带的身份（来自 manifest.lua；见 phos.cart）
    std::string save_dir = kSaveDir;    // 存档目录（--save-dir / 测试模式可改指向独立目录）
    double time = 0.0;                  // 卡带运行秒数
    long frame = 0;                     // 正在推进的逻辑帧号（与 state.query 的 frame 同源）
    int fps = kLogicFps;                // 实际帧率（窗口模式由主循环刷新；无头模式为逻辑帧率）
    /// 字形墨迹框查询（`phos.text.ink_box`）。窗口渲染器就绪时由 App 装配；
    /// 无头或字体未就绪时为空，调用方退回整格宽（见 core/text.hpp 的 GlyphBox）
    std::function<GlyphBox(char32_t)> glyph_metrics;
    std::string language = "zh";        // 界面语言（"zh"/"en"）：卡带据此选自己的文案
    std::mt19937 rng;                   // 确定性模式下由种子驱动

    // 内容区（"屏幕"）在网格中的位置与尺寸——卡带只见 80x45 局部坐标
    int content_x = 0, content_y = 0, content_w = kContentW, content_h = kContentH;

    // 侧栏面板：宽度 0 表示无面板（在其宿主坐标系内位于内容区右侧）
    int panel_w = 0;

    // 可选图层缓冲（`phos.layer`）。卡带不建层时它是空的，主循环里连一次合并都不发生；
    // 每次插卡由 App 重置，于是层随卡带生命周期
    LayeredScreen layers;

    int panel_origin_x() const { return content_x + content_w - panel_w; }
};

/// 向 Lua 沙箱注册 phos.* API（见 docs/api-reference.md）。
/// 这是全工程唯一允许接触 Lua 的模块。
void register_host_api(sol::state& lua, HostContext& host);

/// 将滤镜色板写入已注册的 phos.color 表（切换主题时热更新）
void apply_palette_to(sol::state& lua, const Palette& palette);

} // namespace phos

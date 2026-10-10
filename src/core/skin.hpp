#pragma once

#include "core/defaults.hpp"
#include "core/screen.hpp"
#include "core/ui.hpp"

#include <string>
#include <vector>

namespace phos {

/// 游戏机主题（skin 内容包）：机身外壳、氛围装饰与主机界面配色。
/// 卡带内容区（"屏幕"）由 screen_* 定义，外壳占据其余网格。
struct Skin {
    std::string id = "default";
    std::string name = "PHOSPHOR P-1";

    // 内容区（卡带与主机界面的作画区域）
    int screen_x = 2, screen_y = 3, screen_w = kContentW, screen_h = kContentH;

    // 外壳字符画（逐行，宽度自动补齐/截断到网格宽）
    std::vector<std::string> top;
    std::vector<std::string> bottom;
    std::string left = "||";    // 左侧装饰字符（按行轮换使用）
    std::string right = "||";

    // 主机界面配色（卡带不受其影响，卡带颜色来自滤镜/调色板）
    Color frame{60, 80, 60};
    Color accent{80, 255, 120};
    Color ui_fg{230, 255, 230};
    Color ui_bg{0, 0, 0};
    Color ui_dim{90, 110, 90};

    /// 指示灯：随运行时间呼吸
    struct Lamp {
        int x = 0, y = 0;
        Color color{255, 80, 80};
        float period = 2.0f;  // 呼吸周期（秒）
    };
    std::vector<Lamp> lamps;

    /// 整机网格宽（左外壳 + 内容区 + 右外壳）
    int grid_w() const { return screen_x * 2 + screen_w; }
    /// 整机网格高（顶部字符画 + 内容区 + 底部字符画）
    int grid_h() const { return static_cast<int>(top.size()) + screen_h +
                                 static_cast<int>(bottom.size()); }
};

/// 内容区矩形：皮肤几何是**唯一真源**。卡带看到的内容区、外壳的版面、
/// 转场特效的覆盖范围都由它定，所以只算一处——分别算两处，
/// 只要有一处没跟上皮肤，卡带的画布与外壳的版面就会错位
inline ui::Rect content_rect(const Skin& skin) {
    return ui::Rect{skin.screen_x, skin.screen_y, skin.screen_w, skin.screen_h};
}

/// 出厂默认机身（硬编码兜底，永远是回退链的最后一环）
Skin builtin_skin();

} // namespace phos

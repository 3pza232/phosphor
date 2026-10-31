#pragma once

#include "core/input.hpp"
#include "core/screen.hpp"

#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace phos {

struct Skin;
struct Palette;

namespace ui {

/// 界面配色：主机界面由 Skin 派生，卡带界面由 Palette 派生——
/// 全工程只有这两条派生路径，界面绘制不出现硬编码颜色。
struct Style {
    Color fg{230, 255, 230};
    Color dim{90, 110, 90};
    Color accent{80, 255, 120};
    Color frame{60, 80, 60};
    Color bg{0, 0, 0};
};

Style style_from_skin(const Skin& skin);
Style style_from_palette(const Palette& palette);

struct Rect {
    int x = 0, y = 0, w = 0, h = 0;
    int right() const { return x + w - 1; }
    int bottom() const { return y + h - 1; }
    /// 在 area 内居中的等尺寸矩形
    static Rect centered(Rect area, int w, int h);
};

// --- 基础绘制 ---
void fill(Screen& screen, Rect rect, char32_t ch, Color fg, Color bg);
void print(Screen& screen, int x, int y, std::string_view text, Color fg, Color bg);
void print_centered(Screen& screen, int y, std::string_view text, Color fg, Color bg,
                    int base, int span);
void divider(Screen& screen, int x, int y, int width, Color color, Color bg);

// --- 几何原语（越界静默裁剪；坐标为整屏网格坐标，调用方负责局部→网格换算） ---
/// 可选的裁剪矩形（网格坐标）：几何原语只画它与屏幕的交集。
/// 传 nullptr（缺省）= 只用屏幕边界。卡带 Region 用它把自己里面的图形裁在区域内。
/// 直线：Bresenham（陡/平/反向都正确），同一条线每格只写一次。
/// 线段先与（裁剪矩形 ∩ 屏幕）求交再光栅化，超大坐标不会变成无界循环。
void line(Screen& screen, int x1, int y1, int x2, int y2, char32_t ch, Color fg, Color bg,
          const Rect* clip = nullptr);
/// 空心矩形：1 格边线。w/h < 2 时按退化处理（单行 / 单列 / 单格）。
void outline(Screen& screen, int x, int y, int w, int h, char32_t ch, Color fg, Color bg,
             const Rect* clip = nullptr);
/// 空心圆：midpoint 算法，八向对称。r <= 0 时只画 (cx, cy) 一格。
/// 只光栅化裁剪区与屏幕内可能看见的那段弧（半径再大也是有界循环）。
void circle(Screen& screen, int cx, int cy, int r, char32_t ch, Color fg, Color bg,
            const Rect* clip = nullptr);

// --- 组件 ---
/// 带标题的边框（标题嵌在上边框，空标题则画普通边框）
void frame(Screen& screen, Rect rect, std::string_view title, const Style& style);
/// 百分比进度条
void bar(Screen& screen, int x, int y, int width, float ratio, const Style& style);
/// 垂直列表菜单（'>' 光标 + 高亮，超出高度时按 selected 滚动）
void menu(Screen& screen, Rect rect, const std::vector<std::string>& items, int selected,
          const Style& style);
/// 自动折行的正文
void text_block(Screen& screen, int x, int y, int width, std::string_view body, int max_lines,
                const Style& style);
/// 像素图标（字符画）。step = **降采样步长**：1 = 逐字符，2 = 每 2 列/行取一个
/// （成品是源图的一半，不是放大倍数；< 1 钳到 1）。brightness = 0..1 的亮度缩放
/// （非有限按 1，越界钳制）；它只改前景色，图标仍按字形占据格子。
void icon(Screen& screen, const std::vector<std::string>& rows,
          const std::map<char, Color>& colors, int center_x, int center_y, int step,
          float brightness, Color fallback);

// --- 交互 ---
enum class NavAction { none, confirm, cancel };

/// 列表导航：处理上/下（循环）与确认/取消，返回新的选中下标
int navigate(const Input& input, int count, int current, NavAction& action);

} // namespace ui
} // namespace phos

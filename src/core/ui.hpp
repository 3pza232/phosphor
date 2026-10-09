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
/// 像素图标（step=1 原尺寸，2 半尺寸；brightness 用于邻位预览调暗）
void icon(Screen& screen, const std::vector<std::string>& rows,
          const std::map<char, Color>& colors, int center_x, int center_y, int step,
          float brightness, Color fallback);

// --- 交互 ---
enum class NavAction { none, confirm, cancel };

/// 列表导航：处理上/下（循环）与确认/取消，返回新的选中下标
int navigate(const Input& input, int count, int current, NavAction& action);

} // namespace ui
} // namespace phos

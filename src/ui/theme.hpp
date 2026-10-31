#pragma once

#include "core/color.hpp"

namespace phos {

struct Skin;
struct Palette;

namespace ui {

/// 边框/光标/滚动条字形集。默认 ASCII，与既有主机界面逐字节一致；
/// 主题（或未来的 ui 内容包）可以换成制表符，控件代码不需要改。
struct Glyphs {
    char32_t h = U'-';
    char32_t v = U'|';
    char32_t tl = U'+';
    char32_t tr = U'+';
    char32_t bl = U'+';
    char32_t br = U'+';
    char32_t cursor = U'>';
    char32_t bullet = U'*';
    char32_t scroll_thumb = U'#';
    char32_t scroll_track = U'-';
    char32_t table_rule = U'\u2500';  ///< 表头下的分隔线（区别于普通 divider 的 h）
};

/// 控件度量：数字进 token，控件代码里不出现魔法数字。
struct Metrics {
    int pad_x = 1;     ///< 默认左右内边距
    int pad_y = 0;     ///< 默认上下内边距
    int gap = 1;       ///< 栈内子项间距
    int label_w = 16;  ///< "标签 + 取值"行的标签列宽
    int indent = 2;    ///< 选中标记占用的列宽
    int repeat_delay = 18;    ///< 方向键按住后首次重复前等待的帧数（默认 18 ≈ 300ms@60Hz）
    int repeat_interval = 3;  ///< 重复间隔帧数（默认 3 ≈ 50ms@60Hz）
};

/// 主题 token：颜色角色 + 字形集 + 度量。控件只读 token，不写死颜色与尺寸；
/// 每个控件仍可通过 Props 覆盖颜色/边框/内边距（局部样式，不是新主题）。
struct Theme {
    Color bg{0, 0, 0};            ///< 整屏底色
    Color surface{0, 0, 0};       ///< 不透明面板/窗口底色
    Color surface_alt{0, 0, 0};   ///< 次级面板（分区/标题条）
    Color text{230, 255, 230};    ///< 正文
    Color text_dim{90, 110, 90};  ///< 次要文字（标签、页脚）
    Color accent{80, 255, 120};   ///< 强调、选中
    Color border{60, 80, 60};     ///< 边框
    Color border_focus{80, 255, 120};
    Color selection_bg{0, 0, 0};  ///< 选中行底色（不透明场景用）
    Color selection_fg{80, 255, 120};
    Color warning{255, 200, 80};
    Color danger{255, 80, 80};
    Color disabled{90, 100, 90};

    Glyphs glyphs;
    Metrics metrics;
    int scale = 1;  ///< 基础字号倍率（卡带可用 2 做大标题，不影响布局 API）
};

/// 外壳主题：由皮肤包派生（机身界面配色）。
Theme theme_from_skin(const Skin& skin);
/// 卡带主题：由内容色板派生（与 phos.color 同源，换主题即换色）。
Theme theme_from_palette(const Palette& palette);

} // namespace ui
} // namespace phos

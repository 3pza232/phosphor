#pragma once

namespace phos {

/// 外壳界面的统一布局常量：界面坐标集中一处，绘制代码里不出现魔法数字。
///
/// 放在头文件而不是藏进 `Shell` 内部：屏幕模块（磁带码界面等）也要按同一套边距
/// 排版——各写一份，日子久了一定走样（标题贴着边框、页脚顶到正文这类毛病）。
struct ShellLayout {
    static constexpr int kMarginX = 2;     // 左右留白
    static constexpr int kTitleY = 1;      // 标题行（相对内容区顶部）
    static constexpr int kRuleY = 2;       // 标题下的分隔线
    static constexpr int kContentTop = 4;  // 正文起始行
    static constexpr int kFooterGap = 2;   // 底部为页脚预留的行数
    static constexpr int kPauseW = 30;     // 暂停菜单尺寸
    static constexpr int kPauseH = 9;
};

} // namespace phos

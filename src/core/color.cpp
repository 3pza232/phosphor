#include "core/color.hpp"

namespace phos {

// 标准色常量。声明在 color.hpp、定义在这里：任何需要 Color 的单元只要包含头文件
// 就能编译，只有真正引用这些常量时才链接本文件（早先它们定义在 screen.cpp，
// 于是"只想用个颜色"也要连着整个屏幕网格一起链接）
const Color Color::black{0, 0, 0};
const Color Color::white{230, 230, 230};
const Color Color::gray{140, 140, 140};
const Color Color::dark_gray{70, 70, 70};
const Color Color::red{255, 80, 80};
const Color Color::green{80, 255, 120};
const Color Color::blue{90, 140, 255};
const Color Color::yellow{255, 230, 90};
const Color Color::cyan{90, 230, 230};
const Color Color::magenta{230, 90, 230};
const Color Color::orange{255, 160, 60};
const Color Color::purple{160, 100, 255};

} // namespace phos

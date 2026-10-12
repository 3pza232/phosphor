#pragma once

#include "core/crt.hpp"
#include "core/screen.hpp"

#include <optional>
#include <string>
#include "core/layered_screen.hpp"

#include <vector>


namespace phos {

/// 离屏截图的渲染参数
struct ScreenImageOptions {
    int cell_w = 16;
    int cell_h = 16;
    CrtParams crt{};  // 后处理参数（色调 / 扫描线 / 孔径格栅 / 辉光 / 亮度补偿）
};

/// RGBA8 离屏图像
struct ScreenImage {
    int width = 0;
    int height = 0;
    std::vector<unsigned char> rgba;  // width * height * 4
};

/// 把字符网格光栅化为图像。**CPU 光栅化，不需要 GL 上下文**，因此无头模式同样可用。
/// 后处理与窗口渲染同一套公式（细扫描线 + 孔径格栅 + 辉光 + 亮度补偿 + 色调），
/// 但像素精度（格栅相位、渐层）与显卡实现允许存在细微差异。
///
/// font_files 为字体链（首个为主字体，其余为回退）：全角字符由链上第一个
/// 含该字形的字体提供，字形比半角宽一倍，自然跨两格。
///
/// 失败返回 nullopt 并填 error。
/// layers 非空时，按 z 升序把各图层叠画在 screen 之上（像素级合成，与窗口那条路同规则）：
/// 只有给过底色的格才铺底，字形只画笔画，笔画之外透出下层。origin 是内容区在屏幕里的
/// 字符格偏移。**不传 layers 就是纯底图**（不经过层合成这一步）。
/// overlay 非空时再压一层主机 chrome（侧栏分隔线，对应 GL 的 draw_overlay），
/// 使截图与窗口一致（有图层的卡带，分隔线不在 base 里）
std::optional<ScreenImage> render_screen_image(const Screen& screen,
                                               const std::vector<std::string>& font_files,
                                               const ScreenImageOptions& options,
                                               std::string& error,
                                               const LayeredScreen* layers = nullptr,
                                               int origin_x = 0, int origin_y = 0,
                                               const Screen* overlay = nullptr);

/// 写出 PNG（父目录按需创建）
bool write_png(const ScreenImage& image, const std::string& path, std::string& error);

} // namespace phos

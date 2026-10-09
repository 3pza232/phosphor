#pragma once

#include "core/crt.hpp"
#include "core/screen.hpp"

#include <optional>
#include <string>
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
std::optional<ScreenImage> render_screen_image(const Screen& screen,
                                               const std::vector<std::string>& font_files,
                                               const ScreenImageOptions& options,
                                               std::string& error);

/// 写出 PNG（父目录按需创建）
bool write_png(const ScreenImage& image, const std::string& path, std::string& error);

/// 读入 PNG 并统一为 RGBA8（用于基线比对）
std::optional<ScreenImage> load_png(const std::string& path, std::string& error);

} // namespace phos

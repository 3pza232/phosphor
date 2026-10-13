#include "render/screen_image.hpp"

#include "render/font.hpp"

#define STB_IMAGE_IMPLEMENTATION
#define STB_IMAGE_WRITE_IMPLEMENTATION
#include <stb_image.h>
#include <stb_image_write.h>

#include <algorithm>
#include <cmath>
#include <filesystem>
#include <fstream>
#include <iterator>

namespace phos {

namespace {

float smoothstep(float edge0, float edge1, float x) {
    const float t = std::clamp((x - edge0) / (edge1 - edge0), 0.0f, 1.0f);
    return t * t * (3.0f - 2.0f * t);
}

/// RGBA 画布视图
struct Canvas {
    unsigned char* data = nullptr;
    int width = 0;
    int height = 0;

    unsigned char* at(int x, int y) {
        return data + (static_cast<size_t>(y) * static_cast<size_t>(width) + x) * 4;
    }
};

/// 单元格底：整格填充背景色（与窗口渲染的每格背景四边形一致）
void fill_cell(Canvas& canvas, int x0, int y0, int cell_w, int cell_h, const Color& bg) {
    for (int y = y0; y < y0 + cell_h; ++y) {
        if (y < 0 || y >= canvas.height) continue;
        for (int x = x0; x < x0 + cell_w; ++x) {
            if (x < 0 || x >= canvas.width) continue;
            unsigned char* p = canvas.at(x, y);
            p[0] = bg.r;
            p[1] = bg.g;
            p[2] = bg.b;
            p[3] = 255;
        }
    }
}

/// 字形合成：core 为字形覆盖率，halo 取四邻域均值（对应窗口渲染的辉光抽样）
void blend_glyph(Canvas& canvas, const std::vector<unsigned char>& glyph, int gw, int gh,
                 int origin_x, int origin_y, const Color& fg, float glow) {
    auto sample = [&](int x, int y) -> float {
        if (x < 0 || x >= gw || y < 0 || y >= gh) return 0.0f;
        return glyph[static_cast<size_t>(y) * static_cast<size_t>(gw) + x] / 255.0f;
    };

    for (int gy = 0; gy < gh; ++gy) {
        const int y = origin_y + gy;
        if (y < 0 || y >= canvas.height) continue;
        for (int gx = 0; gx < gw; ++gx) {
            const int x = origin_x + gx;
            if (x < 0 || x >= canvas.width) continue;

            const float core = sample(gx, gy);
            const float halo =
                (sample(gx - 1, gy) + sample(gx + 1, gy) + sample(gx, gy - 1) + sample(gx, gy + 1)) *
                0.25f;
            const float alpha = std::max(core, halo * glow);
            if (alpha <= 0.0f) continue;

            unsigned char* p = canvas.at(x, y);
            for (int channel = 0; channel < 3; ++channel) {
                const float bg = p[channel] / 255.0f;
                const float fgv = channel == 0 ? fg.r : (channel == 1 ? fg.g : fg.b);
                const float mixed = bg + (fgv / 255.0f - bg) * alpha;
                p[channel] =
                    static_cast<unsigned char>(std::clamp(mixed, 0.0f, 1.0f) * 255.0f + 0.5f);
            }
        }
    }
}

/// 后处理：与窗口着色器同一套公式
/// （细扫描线 + 孔径格栅 + 亮度补偿 + 色调；坐标自下而上以对齐 GL 的 gl_FragCoord）
void post_process(Canvas& canvas, const CrtParams& crt) {
    const float tint[3] = {crt.tint.r / 255.0f, crt.tint.g / 255.0f, crt.tint.b / 255.0f};
    const float loss = crt.scanline * kScanlineLossPerUnit + crt.mask * kMaskLossPerUnit;
    const float comp = crt.compensate ? 1.0f + loss : 1.0f;

    for (int y = 0; y < canvas.height; ++y) {
        // 与 GL 对齐：gl_FragCoord 是像素**中心**（底行 y≈0.5、顶行 ≈H-0.5）。少了这半个
        // 像素，当周期取整数（kScanlinePeriodPx=3）时 phase 只会落在 {0,1/3,2/3}，永远够
        // 不到暗线区间（0.68..），扫描线在 CPU 这条路上会彻底失效
        const float fy = static_cast<float>(canvas.height) - 0.5f - static_cast<float>(y);
        const float phase = crt_scanline_phase(fy);
        const float scan =
            1.0f - crt.scanline * smoothstep(kScanlineDarkStart, kScanlineDarkEnd, phase);

        for (int x = 0; x < canvas.width; ++x) {
            const int sub = x % static_cast<int>(kMaskPeriodPx);  // 孔径格栅：RGB 子像素各自全亮，其余通道压暗
            unsigned char* p = canvas.at(x, y);
            for (int channel = 0; channel < 3; ++channel) {
                const float mask = (sub == channel) ? 1.0f : (1.0f - crt.mask);
                const float value = (p[channel] / 255.0f) * scan * mask * comp * tint[channel];
                p[channel] =
                    static_cast<unsigned char>(std::clamp(value, 0.0f, 1.0f) * 255.0f + 0.5f);
            }
        }
    }
}

} // namespace

std::optional<ScreenImage> render_screen_image(const Screen& screen,
                                               const std::vector<std::string>& font_files,
                                               const ScreenImageOptions& options,
                                               std::string& error,
                                               const LayeredScreen* layers,
                                               int origin_x, int origin_y,
                                               const Screen* overlay) {
    FontChain fonts;
    std::string load_error;
    for (const std::string& path : font_files) {
        // 与窗口渲染同一套回退语义：坏的字体跳过，其余继续
        if (!fonts.add(path, load_error)) load_error.clear();
    }
    if (fonts.empty()) {
        error = "no usable font file";
        return std::nullopt;
    }

    const int cell_w = std::max(1, options.cell_w);
    const int cell_h = std::max(1, options.cell_h);

    ScreenImage image;
    image.width = screen.width() * cell_w;
    image.height = screen.height() * cell_h;
    if (image.width <= 0 || image.height <= 0) {
        error = "screen is empty";
        return std::nullopt;
    }

    Canvas canvas;
    canvas.width = image.width;
    canvas.height = image.height;
    image.rgba.assign(static_cast<size_t>(image.width) * static_cast<size_t>(image.height) * 4, 0);
    canvas.data = image.rgba.data();

    // 一格的字形：先按**追加顺序**画笔迹，最后画 ch —— ch 是最前面那一笔。
    // 顺序必须与 GL 那条路（Renderer::emit_glyphs）一致：两条路画的是同一张图，
    // 截图与无头回归才有意义
    const auto draw_pens = [&](const Screen& grid, int cx, int cy, int x0, int y0, int scale) {
        const Cell& cell = grid.at(cx, cy);
        const int sc = scale < 1 ? 1 : scale;
        // 字形按 cell_h 光栅化；基线取主字体的 ascent（全角字形已按主字体基线对齐）。
        // 缩放块的头格把两者都放大到 sc 倍
        const float px = static_cast<float>(cell_h * sc);
        const float base = fonts.ascent(px);
        const auto one = [&](char32_t ch, const Color& fg) {
            if (ch == U' ') return;
            GlyphBitmap bitmap = fonts.rasterize(ch, px);
            if (bitmap.width <= 0 || bitmap.height <= 0) {
                if (ch == U'?') return;
                bitmap = fonts.rasterize(U'?', px);  // 无字形：占位
                if (bitmap.width <= 0 || bitmap.height <= 0) return;
            }
            // 全角字形把"字身框"在两格槽里居中：字体的推进宽度只有一格（16px），
            // 不居中的话汉字会挤在左边、右边空出一格。半角直接用字体的推进位置
            int glyph_x = x0 + bitmap.xoff;
            if (cell.cols == 2) glyph_x += (cell_w * 2 * sc - bitmap.advance) / 2;
            blend_glyph(canvas, bitmap.pixels, bitmap.width, bitmap.height, glyph_x,
                        y0 + static_cast<int>(base) + bitmap.yoff, fg, options.crt.glow);
        };
        for (const Screen::Ink& ink : grid.inks(cx, cy)) one(ink.ch, ink.fg);
        // 被缩放块覆盖的格自身没有字形（大字已由头格画完）——即使 blend 往它上面写过一笔，
        // 这里也只画笔迹，不画它的字形（与 GL 那条路一致）
        if (cell.scale != 0) one(cell.ch, cell.fg);
    };

    for (int cy = 0; cy < screen.height(); ++cy) {
        for (int cx = 0; cx < screen.width(); ++cx) {
            const Cell& cell = screen.at(cx, cy);
            // 续格 / 被缩放块覆盖的格：不单独铺底（宽字/大字由头格画完），但**这一格上的
            // 笔迹要画**——否则 blend 到这里的那一笔会凭空消失
            if (cell.cols == 0 || cell.scale == 0) {
                draw_pens(screen, cx, cy, cx * cell_w, cy * cell_h, 1);
                continue;
            }

            const int x0 = cx * cell_w;
            const int y0 = cy * cell_h;
            const int sc = cell.scale < 1 ? 1 : cell.scale;
            fill_cell(canvas, x0, y0, cell_w * cell.cols * sc, cell_h * sc, cell.bg);
            draw_pens(screen, cx, cy, x0, y0, sc);
        }
    }

    // 图层：按 z 升序逐层叠画。规则与 GL 那条路一致 —— 只有给过底色的格才铺底
    // （铺了就盖住下面），字形只画自己的笔画，笔画之外透出下层
    if (layers) {
        for (const Layer* layer : layers->ordered()) {
            if (!layer->visible) continue;
            const Screen& src = layer->cells;
            for (int cy = 0; cy < src.height(); ++cy) {
                for (int cx = 0; cx < src.width(); ++cx) {
                    const Cell& cell = src.at(cx, cy);
                    if (cell.cols == 0 || cell.scale == 0) continue;  // 续格 / 被缩放块覆盖
                    const int x0 = (origin_x + cx) * cell_w;
                    const int y0 = (origin_y + cy) * cell_h;
                    const int sc = cell.scale < 1 ? 1 : cell.scale;
                    if (cell.alpha != 0)
                        fill_cell(canvas, x0, y0, cell_w * cell.cols * sc, cell_h * sc, cell.bg);
                    draw_pens(src, cx, cy, x0, y0, sc);
                }
            }
        }
    }

    // 主机 chrome（侧栏分隔线）：与 GL 的 draw_overlay 对应，压在所有图层之上。
    // 有图层的卡带，分隔线不在 base 里，截图缺了它就跟窗口差一列
    if (overlay) {
        for (int cy = 0; cy < overlay->height(); ++cy) {
            for (int cx = 0; cx < overlay->width(); ++cx) {
                const Cell& cell = overlay->at(cx, cy);
                if (cell.cols == 0 || cell.scale == 0) continue;
                const int x0 = (origin_x + cx) * cell_w;
                const int y0 = (origin_y + cy) * cell_h;
                const int sc = cell.scale < 1 ? 1 : cell.scale;
                if (cell.alpha != 0)
                    fill_cell(canvas, x0, y0, cell_w * cell.cols * sc, cell_h * sc, cell.bg);
                draw_pens(*overlay, cx, cy, x0, y0, sc);
            }
        }
    }

    post_process(canvas, options.crt);
    return image;
}

bool write_png(const ScreenImage& image, const std::string& path, std::string& error) {
    if (image.width <= 0 || image.height <= 0 ||
        image.rgba.size() < static_cast<size_t>(image.width) * image.height * 4) {
        error = "image is empty";
        return false;
    }

    const std::filesystem::path output(path);
    if (auto parent = output.parent_path(); !parent.empty()) {
        std::error_code ec;
        std::filesystem::create_directories(parent, ec);
        if (ec) {
            error = "cannot create directory: " + parent.string();
            return false;
        }
    }

    if (!stbi_write_png(path.c_str(), image.width, image.height, 4, image.rgba.data(),
                        image.width * 4)) {
        error = "cannot write PNG: " + path;
        return false;
    }
    return true;
}

} // namespace phos

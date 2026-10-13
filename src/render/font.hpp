#pragma once

#include <cstdint>
#include <memory>
#include <string>
#include <vector>

namespace phos {

/// 一个字形位图（8 位 alpha），坐标已按主字体基线对齐：
/// 绘制时应贴到 (笔位置 + xoff, 基线 + yoff)。
struct GlyphBitmap {
    int width = 0;
    int height = 0;
    int xoff = 0;     // 位图左上角相对笔位置的水平偏移
    int yoff = 0;     // 位图左上角相对基线的垂直偏移（负数在基线之上）
    int advance = 0;  // 该字形的推进宽度；全角字形据此在两格槽里居中
    std::vector<uint8_t> pixels;  // width * height
};

/// 字体链：按优先级依次尝试多个字体文件，取第一个含该字形的字体。
///
/// 存在的理由：出厂字体只覆盖 ASCII，而中文需要另一个字体文件；
/// 链式回退让"ASCII 像素字体 + CJK 字体"共存，也让用户把字体丢进
/// `theme/font/<名称>/` 就能给机器换字。
///
/// 第三方头（stb_truetype）只出现在本模块内部，接口不暴露 stbtt 类型。
class FontChain {
public:
    FontChain();
    ~FontChain();
    FontChain(const FontChain&) = delete;
    FontChain& operator=(const FontChain&) = delete;

    /// 追加一个字体文件（按优先级顺序调用）。加载失败返回 false 并填 error，
    /// 调用方决定是跳过还是中止（回退链的语义是尽量跳过）。
    /// 支持 .ttf/.otf 与 .ttc（字体集合取第 0 号）。
    bool add(const std::string& path, std::string& error);

    bool empty() const { return faces_.empty(); }

    /// 哪个字体含有该字形；都没有返回 -1
    int face_for(char32_t cp) const;

    /// 光栅化：pixel_height 为字号（像素高），结果按主字体基线对齐。
    /// 无字体含该字形时返回空位图（width/height 为 0）。
    GlyphBitmap rasterize(char32_t cp, float pixel_height) const;

    /// 主字体的 ascent（按像素高缩放后），用于把字形贴到单元格基线上
    float ascent(float pixel_height) const;

    /// 主字体在一档字号下的 em 高度（ascent - descent，像素），
    /// 用来把图集尺寸换算到单元格尺寸
    float em_height(float pixel_height) const;

    /// 一个已打包字形的图集信息（UV 与度量，均为像素单位）
    struct PackedGlyph {
        float u0 = 0, v0 = 0, u1 = 0, v1 = 0;
        float xoff = 0, yoff = 0;
        float w = 0, h = 0;
    };

    /// 用主字体把一段 ASCII 区间一次性打进画布（静态区，像素与一次性打包一致）。
    /// canvas_pixels 尺寸为 canvas × canvas；out 与 [first, first+count) 一一对应。
    bool pack_ascii(int first, int count, float pixel_height, int canvas,
                    std::vector<uint8_t>& canvas_pixels,
                    std::vector<PackedGlyph>& out) const;

private:
    struct Face;
    std::vector<std::unique_ptr<Face>> faces_;  // faces_[0] 为主字体
};

/// 字体方案内的角色命名：stem 恰为 `font` 的文件是**主字体**（决定 ASCII 与整机字形风格），
/// 其余按名称排序作回退（约定用 `font-cn` 之类补齐它缺的码位）。
/// 扩展名 .ttf / .otf / .ttc 均可（TTC 取第 0 号）。
inline constexpr const char* kFontPrimaryStem = "font";

/// 一个字体方案目录里的文件顺序：主字体在最前，其余按名称排序。
/// 方案目录不存在或没有可用字体时返回空列表（调用方决定如何回退）。
/// 方案可用 `theme/font/<方案>/font.lua` 显式声明回退顺序，那是 `pack/pack.hpp` 的
/// `scan_font_schemes`：它用本函数得到默认顺序，再按声明重排
std::vector<std::string> collect_font_files(const std::string& scheme_dir);

} // namespace phos

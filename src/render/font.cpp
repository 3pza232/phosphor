#include "render/font.hpp"

// stb 的实现函数默认是 static：只能在包含 IMPLEMENTATION 的这个 TU 里用。
// 全工程对 stb_truetype 的调用都集中在 font.cpp，所以实现也放在这里。
#define STB_TRUETYPE_IMPLEMENTATION
#include <stb_truetype.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iterator>

namespace phos {

namespace fs = std::filesystem;

/// 一个已加载的字体面。**stbtt 类型只出现在这里**（第三方头不外泄）。
struct FontChain::Face {
    std::vector<unsigned char> data;
    stbtt_fontinfo info{};
    bool valid = false;
};

namespace {

/// 字形缩放。主字体（ASCII 像素字体）按行高缩放——整机像素基线由它定，不能动；
/// 回退字体（中文等大码集）按 **em 方框**缩放：这类字体的行高度量普遍大于一个 em
/// （给注音、附加符号留余地），按行高缩放会让满 em 汉字只占约 0.7 格，明显偏小
float face_scale(const stbtt_fontinfo& info, float pixel_height, bool primary) {
    return primary ? stbtt_ScaleForPixelHeight(&info, pixel_height)
                   : stbtt_ScaleForMappingEmToPixels(&info, pixel_height);
}

/// 该字体在给定字号下的 ascent（基线到格顶的距离）。
/// 回退字体取 OS/2 排版度量（sTypoAscender），它才是按 em 方框设计的；
/// 该表缺失或数值异常时退回行高度量。
float face_ascent(const stbtt_fontinfo& info, float pixel_height, bool primary) {
    int ascent = 0, descent = 0, line_gap = 0;
    if (!primary && stbtt_GetFontVMetricsOS2(&info, &ascent, &descent, &line_gap) &&
        ascent > 0 && ascent - descent > 0)
        return ascent * face_scale(info, pixel_height, false);
    stbtt_GetFontVMetrics(&info, &ascent, &descent, &line_gap);
    return ascent * face_scale(info, pixel_height, primary);
}

bool has_suffix(const std::string& path, const char* suffix) {
    const std::string s(suffix);
    return path.size() >= s.size() && path.compare(path.size() - s.size(), s.size(), s) == 0;
}

} // namespace

FontChain::FontChain() = default;
FontChain::~FontChain() = default;

bool FontChain::add(const std::string& path, std::string& error) {
    std::ifstream file(path, std::ios::binary);
    if (!file) {
        error = "cannot open font: " + path;
        return false;
    }

    auto face = std::make_unique<Face>();
    face->data.assign(std::istreambuf_iterator<char>(file), std::istreambuf_iterator<char>());
    if (face->data.empty()) {
        error = "empty font file: " + path;
        return false;
    }

    // .ttc 是字体集合：取第 0 号（stb 的 offset 接口对普通 ttf 返回 0）
    const int offset = stbtt_GetFontOffsetForIndex(face->data.data(), 0);
    if (offset < 0 || !stbtt_InitFont(&face->info, face->data.data(), offset)) {
        error = "invalid font file: " + path;
        return false;
    }

    face->valid = true;
    faces_.push_back(std::move(face));
    return true;
}

int FontChain::face_for(char32_t cp) const {
    for (size_t i = 0; i < faces_.size(); ++i) {
        if (!faces_[i]->valid) continue;
        // 字形索引 0 是 .notdef：该字体没有这个字，交给下一环
        if (stbtt_FindGlyphIndex(&faces_[i]->info, static_cast<int>(cp)) != 0)
            return static_cast<int>(i);
    }
    return -1;
}

float FontChain::ascent(float pixel_height) const {
    if (faces_.empty() || !faces_[0]->valid) return 0.0f;
    return face_ascent(faces_[0]->info, pixel_height, true);
}

float FontChain::em_height(float pixel_height) const {
    if (faces_.empty() || !faces_[0]->valid) return 0.0f;
    int ascent = 0, descent = 0, line_gap = 0;
    stbtt_GetFontVMetrics(&faces_[0]->info, &ascent, &descent, &line_gap);
    return (ascent - descent) * face_scale(faces_[0]->info, pixel_height, true);
}

bool FontChain::pack_ascii(int first, int count, float pixel_height, int canvas,
                           std::vector<uint8_t>& canvas_pixels,
                           std::vector<PackedGlyph>& out) const {
    if (faces_.empty() || !faces_[0]->valid) return false;
    if (canvas <= 0 ||
        canvas_pixels.size() < static_cast<size_t>(canvas) * static_cast<size_t>(canvas))
        return false;

    stbtt_pack_context context;
    if (!stbtt_PackBegin(&context, canvas_pixels.data(), canvas, canvas, 0, 1, nullptr))
        return false;

    std::vector<stbtt_packedchar> packed(static_cast<size_t>(count));
    const bool ok = stbtt_PackFontRange(&context, faces_[0]->data.data(), 0, pixel_height, first,
                                        count, packed.data());
    stbtt_PackEnd(&context);
    if (!ok) return false;

    out.clear();
    out.reserve(static_cast<size_t>(count));
    const float scale = 1.0f / static_cast<float>(canvas);
    for (int i = 0; i < count; ++i) {
        const stbtt_packedchar& p = packed[static_cast<size_t>(i)];
        PackedGlyph glyph;
        glyph.u0 = static_cast<float>(p.x0) * scale;
        glyph.v0 = static_cast<float>(p.y0) * scale;
        glyph.u1 = static_cast<float>(p.x1) * scale;
        glyph.v1 = static_cast<float>(p.y1) * scale;
        glyph.w = static_cast<float>(p.x1 - p.x0);
        glyph.h = static_cast<float>(p.y1 - p.y0);
        glyph.xoff = p.xoff;
        glyph.yoff = p.yoff;
        out.push_back(glyph);
    }
    return true;
}

GlyphBitmap FontChain::rasterize(char32_t cp, float pixel_height) const {
    GlyphBitmap bitmap;
    const int face_index = face_for(cp);
    if (face_index < 0) return bitmap;  // 链上没有这个字形

    const FontChain::Face& face = *faces_[static_cast<size_t>(face_index)];
    const bool primary = face_index == 0;
    const float scale = face_scale(face.info, pixel_height, primary);

    int advance = 0, bearing = 0;
    stbtt_GetCodepointHMetrics(&face.info, static_cast<int>(cp), &advance, &bearing);

    int bx0 = 0, by0 = 0, bx1 = 0, by1 = 0;
    stbtt_GetCodepointBitmapBox(&face.info, static_cast<int>(cp), scale, scale, &bx0, &by0, &bx1,
                                &by1);
    bitmap.width = bx1 - bx0;
    bitmap.height = by1 - by0;
    bitmap.xoff = bx0;
    bitmap.advance = static_cast<int>(advance * scale + 0.5f);

    // 基线对齐：stb 给出的 yoff 是相对**该字体自己的**基线的，而整屏只有一条绘制基线，
    // 所以要把字形整体挪到主字体基线上：shift = 本字体 ascent − 主字体 ascent。
    // 符号取反会让汉字整体上移、顶部被格子裁掉（剩下的笔画看起来就是另一个字）。
    const float baseline_shift = face_ascent(face.info, pixel_height, primary) -
                                 ascent(pixel_height);
    bitmap.yoff = by0 + static_cast<int>(baseline_shift < 0.0f ? baseline_shift - 0.5f
                                                              : baseline_shift + 0.5f);
    if (bitmap.width <= 0 || bitmap.height <= 0) {
        bitmap.width = 0;
        bitmap.height = 0;
        return bitmap;
    }

    bitmap.pixels.assign(static_cast<size_t>(bitmap.width) * static_cast<size_t>(bitmap.height), 0);
    stbtt_MakeCodepointBitmap(&face.info, bitmap.pixels.data(), bitmap.width, bitmap.height,
                              bitmap.width, scale, scale, static_cast<int>(cp));
    return bitmap;
}

namespace {

/// 某个目录下的字体文件（.ttf/.otf/.ttc），按名称排序保证顺序稳定
std::vector<std::string> font_files_in(const std::string& dir) {
    std::vector<std::string> files;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) return files;
    for (fs::directory_iterator it(dir, ec), end; it != end && !ec; it.increment(ec)) {
        if (!it->is_regular_file(ec)) continue;
        const std::string path = it->path().generic_string();
        if (has_suffix(path, ".ttf") || has_suffix(path, ".otf") || has_suffix(path, ".ttc"))
            files.push_back(path);
    }
    std::sort(files.begin(), files.end());
    return files;
}

/// 该文件是否是这个方案的主字体：stem 恰为 `font`（font-cn 之类是回退）
bool is_primary_font(const std::string& path) {
    return fs::path(path).stem().string() == kFontPrimaryStem;
}

} // namespace

std::vector<std::string> collect_font_files(const std::string& scheme_dir) {
    const std::vector<std::string> found = font_files_in(scheme_dir);  // 已按名称排序
    std::vector<std::string> files;
    files.reserve(found.size());
    // 主字体必须排最前：它的 ASCII 字形与像素基线是整机的基准，回退只管补齐它缺的码位
    for (const std::string& path : found)
        if (is_primary_font(path)) files.push_back(path);
    for (const std::string& path : found)
        if (!is_primary_font(path)) files.push_back(path);
    return files;
}

} // namespace phos

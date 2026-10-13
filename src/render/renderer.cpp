#include "render/renderer.hpp"

#include "core/log.hpp"
#include "core/text.hpp"
#include "render/font.hpp"

#include <glad/glad.h>

#include <algorithm>
#include <cmath>
#include <cstdio>

namespace phos {

namespace {

constexpr int kFirstChar = 32;
constexpr int kCharCount = 95;
constexpr float kFontPixels = 32.0f;  // 图集光栅化高度（绘制时缩放到单元格）
// 图集边长：ASCII 静态区占顶部一条，其余留给按需装入的 CJK 字形
constexpr int kAtlasSize = 1024;
// 找不到字体时给用户的提示（实际路径由 App 传入）
constexpr const char* kFontPathHint = "theme/font/default/font.ttf";

const char* kVertSrc = R"(
#version 330 core
layout(location = 0) in vec2 a_pos;    // 像素坐标
layout(location = 1) in vec2 a_uv;
layout(location = 2) in vec3 a_fg;
layout(location = 3) in vec3 a_bg;

uniform vec2 u_resolution;

out vec2 v_uv;
out vec3 v_fg;
out vec3 v_bg;

void main() {
    vec2 ndc = (a_pos / u_resolution) * 2.0 - 1.0;
    gl_Position = vec4(ndc.x, -ndc.y, 0.0, 1.0);
    v_uv = a_uv;
    v_fg = a_fg;
    v_bg = a_bg;
}
)";

// CRT 后处理：细扫描线（按像素周期，优于按字符行整片压暗）+ 孔径格栅 +
// 弱字符辉光（四邻域近似 bloom，弱到不糊字形）+ 反向亮度补偿（档位变化不改变整体亮度）
const char* kFragSrc = R"(
#version 330 core
in vec2 v_uv;
in vec3 v_fg;
in vec3 v_bg;

uniform sampler2D u_font;
uniform vec2 u_texel;    // 字体图集纹素尺寸（辉光采样步长）
uniform float u_period;  // 扫描线周期（像素）
uniform float u_maskperiod;  // 孔径格栅周期（像素，= RGB 子像素列数）
uniform float u_scan;    // 扫描线深度 0..1
uniform float u_mask;    // 孔径格栅强度 0..1
uniform float u_glow;    // 字符辉光 0..1
uniform float u_comp;    // 亮度补偿系数（>= 1.0）
uniform vec2 u_darkline; // 暗线相位区间（由 kScanlineDarkStart/End 传入）
uniform vec3 u_tint;     // 显像管整体色调
uniform float u_layer;   // 1 = 这一趟画的是图层（笔画为实、笔画之外透明）

out vec4 frag_color;

void main() {
    float core = texture(u_font, v_uv).r;
    float halo = (texture(u_font, v_uv + vec2(u_texel.x, 0.0)).r +
                  texture(u_font, v_uv - vec2(u_texel.x, 0.0)).r +
                  texture(u_font, v_uv + vec2(0.0, u_texel.y)).r +
                  texture(u_font, v_uv - vec2(0.0, u_texel.y)).r) * 0.25;
    float alpha = max(core, halo * u_glow);
    vec3 color = mix(v_bg, v_fg, alpha);

    // 细扫描线：每周期末尾一小段为暗线，其余保持全亮
    float phase = fract(gl_FragCoord.y / u_period);
    float dark_line = smoothstep(u_darkline.x, u_darkline.y, phase);
    float scanline = 1.0 - u_scan * dark_line;

    // 孔径格栅：RGB 子像素垂直条纹
    float sub = mod(gl_FragCoord.x, u_maskperiod);
    vec3 mask = vec3(1.0 - u_mask);
    if (sub < 1.0) mask.r = 1.0;
    else if (sub < 2.0) mask.g = 1.0;
    else mask.b = 1.0;

    vec3 lit = color * scanline * mask * u_comp * u_tint;
    // 图层趟：只输出**字形笔画**，alpha 用覆盖率 —— 笔画之外是透明的，
    // 下层（地形、角色……）的像素原样透出来。这才是"两层叠在同一格"，
    // 而不是"上层把下层顶掉"
    if (u_layer > 0.5) {
        frag_color = vec4(v_fg * scanline * mask * u_comp * u_tint, alpha);
        return;
    }
    frag_color = vec4(lit, 1.0);
}
)";

} // namespace

// FontChain 的完整类型只在本 TU 可见（头部只需前置声明），构造与析构因此留在这里
Renderer::Renderer() = default;

Renderer::~Renderer() { destroy(); }

void Renderer::destroy() {
    if (vbo_) glDeleteBuffers(1, &vbo_);
    if (vao_) glDeleteVertexArrays(1, &vao_);
    if (font_tex_) glDeleteTextures(1, &font_tex_);
    vbo_ = vao_ = font_tex_ = 0;
    fonts_.reset();
    extra_glyphs_.clear();
    pen_x_ = pen_y_ = pen_row_h_ = 0;
    atlas_full_ = false;
}

const Renderer::Glyph* Renderer::glyph_for(char32_t cp) {
    // 空格（32）就在 ASCII 区间里，由上一行覆盖；不必单独判一次
    if (cp >= kFirstChar && cp < kFirstChar + kCharCount) return &glyphs_[cp - kFirstChar];
    if (!fonts_) return nullptr;

    const auto cached = extra_glyphs_.find(cp);
    if (cached != extra_glyphs_.end()) return &cached->second;
    if (atlas_full_) return nullptr;

    const GlyphBitmap bitmap = fonts_->rasterize(cp, kFontPixels);
    if (bitmap.width <= 0 || bitmap.height <= 0) return nullptr;  // 字体链里没有这个字形

    // 一行放满就往下开一行；整体装不下即标记满，只告警一次
    if (pen_x_ + bitmap.width > kAtlasSize) {
        pen_x_ = 0;
        pen_y_ += pen_row_h_ + 1;
        pen_row_h_ = 0;
    }
    if (pen_y_ + bitmap.height > kAtlasSize) {
        atlas_full_ = true;
        log::warn("字体图集已满：后续字形只能显示为占位符（减少同屏 CJK 字数或缩小字号）");
        return nullptr;
    }

    glBindTexture(GL_TEXTURE_2D, font_tex_);
    // 源数据是紧密排列的 8 位单通道，行宽不一定是 4 的倍数：
    // GL 默认按 4 字节对齐读行，会在字形内部逐行错位（画出来像别的字），
    // 并且会多读每行尾部。这里按 1 字节对齐。
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);
    glTexSubImage2D(GL_TEXTURE_2D, 0, pen_x_, pen_y_, bitmap.width, bitmap.height, GL_RED,
                    GL_UNSIGNED_BYTE, bitmap.pixels.data());

    Glyph glyph;
    const float inv = 1.0f / static_cast<float>(kAtlasSize);
    glyph.u0 = static_cast<float>(pen_x_) * inv;
    glyph.v0 = static_cast<float>(pen_y_) * inv;
    glyph.u1 = static_cast<float>(pen_x_ + bitmap.width) * inv;
    glyph.v1 = static_cast<float>(pen_y_ + bitmap.height) * inv;
    glyph.w = static_cast<float>(bitmap.width);
    glyph.h = static_cast<float>(bitmap.height);
    glyph.xoff = static_cast<float>(bitmap.xoff);
    // 全角字形在两格槽里居中：xoff 是 kFontPixels 尺度，槽宽换算到同一尺度再取半
    if (text::char_width(cp) == 2) {
        const float slot = static_cast<float>(cell_w_ * 2) / pack_scale_;
        glyph.xoff += (slot - static_cast<float>(bitmap.advance)) / 2.0f;
    }
    glyph.yoff = static_cast<float>(bitmap.yoff);

    pen_x_ += bitmap.width + 1;
    pen_row_h_ = std::max(pen_row_h_, bitmap.height);
    return &extra_glyphs_.emplace(cp, glyph).first->second;
}

bool Renderer::init(const std::vector<std::string>& font_files, int cell_w, int cell_h,
                    std::string& err) {
    cell_w_ = cell_w;
    cell_h_ = cell_h;
    if (!shader_.build(kVertSrc, kFragSrc, err)) return false;
    auto fonts = load_font_chain(font_files);
    if (!fonts) {
        err = "没有可用的字体文件（检查 " + std::string(kFontPathHint) + "）";
        return false;
    }
    if (!build_font_atlas(std::move(fonts), err)) return false;

    glGenVertexArrays(1, &vao_);
    glGenBuffers(1, &vbo_);
    if (vao_ == 0 || vbo_ == 0) {
        err = "GL 顶点缓冲创建失败";
        return false;
    }
    glBindVertexArray(vao_);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);

    // 每格 6 顶点，每顶点 10 float：pos2 uv2 fg3 bg3
    constexpr int stride = 10 * sizeof(float);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, nullptr);
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(2 * sizeof(float)));
    glEnableVertexAttribArray(2);
    glVertexAttribPointer(2, 3, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(4 * sizeof(float)));
    glEnableVertexAttribArray(3);
    glVertexAttribPointer(3, 3, GL_FLOAT, GL_FALSE, stride, reinterpret_cast<void*>(7 * sizeof(float)));
    glBindVertexArray(0);

    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    return true;
}

std::unique_ptr<FontChain> Renderer::load_font_chain(const std::vector<std::string>& font_files) {
    auto fonts = std::make_unique<FontChain>();
    std::string load_error;
    for (const std::string& path : font_files) {
        // 回退链的语义：坏的字体跳过并告警，不因此让整机没字可用
        if (!fonts->add(path, load_error)) log::warn("字体已跳过: " + load_error);
        load_error.clear();
    }
    if (fonts->empty()) return nullptr;
    return fonts;
}

bool Renderer::reload_fonts(const std::vector<std::string>& font_files, std::string& err) {
    // 先装载：字体全不可用时立刻返回，已生效的字体一个成员都不动
    auto fonts = load_font_chain(font_files);
    if (!fonts) {
        err = "没有可用的字体文件";
        return false;
    }

    const unsigned previous_tex = font_tex_;
    font_tex_ = 0;
    if (!build_font_atlas(std::move(fonts), err)) {
        // 打包失败在固定字号/固定图集下不可达；真发生也宁可沿用旧图集，不要黑屏
        font_tex_ = previous_tex;
        return false;
    }
    if (previous_tex != 0) glDeleteTextures(1, &previous_tex);

    // 动态区里已装好的字形属于旧图集，必须整片丢弃重装
    extra_glyphs_.clear();
    atlas_full_ = false;
    return true;
}

bool Renderer::build_font_atlas(std::unique_ptr<FontChain> fonts, std::string& err) {
    std::vector<unsigned char> bitmap(static_cast<size_t>(kAtlasSize) * kAtlasSize, 0);
    std::vector<FontChain::PackedGlyph> packed;
    // 先在**局部**上打包：失败就原样返回，别把 fonts_ 换成一条没装成的链
    // （否则 reload 的回滚只还原纹理，而字形/度量会与旧链对不上）
    if (!fonts->pack_ascii(kFirstChar, kCharCount, kFontPixels, kAtlasSize, bitmap, packed)) {
        err = "字体图集打包失败（图集尺寸不足？）";
        return false;
    }
    fonts_ = std::move(fonts);  // 打包成功才接管

    for (size_t i = 0; i < packed.size() && i < kCharCount; ++i) {
        const FontChain::PackedGlyph& p = packed[i];
        Glyph& g = glyphs_[i];
        g.u0 = p.u0;
        g.v0 = p.v0;
        g.u1 = p.u1;
        g.v1 = p.v1;
        g.w = p.w;
        g.h = p.h;
        g.xoff = p.xoff;
        g.yoff = p.yoff;
    }

    // 动态区从静态区下方接着装：静态区（ASCII）的位置永不改变，它是整机像素基线
    int ascii_bottom = 0;
    for (const FontChain::PackedGlyph& p : packed)
        ascii_bottom = std::max(ascii_bottom, static_cast<int>(p.v1 * kAtlasSize + 0.5f));
    pen_x_ = 0;
    pen_y_ = ascii_bottom + 1;
    pen_row_h_ = 0;

    // 度量：字形等比缩放进目标单元格（比例由 pack_scale_ 保证）
    font_ascent_ = fonts_->ascent(kFontPixels);
    const float em = fonts_->em_height(kFontPixels);
    pack_scale_ = em > 0.0f ? static_cast<float>(cell_h_) / em : 1.0f;

    glGenTextures(1, &font_tex_);
    if (font_tex_ == 0) {
        err = "glGenTextures 失败（纹理名耗尽？）";
        return false;
    }
    glBindTexture(GL_TEXTURE_2D, font_tex_);
    glPixelStorei(GL_UNPACK_ALIGNMENT, 1);  // 图集是单通道 8 位，行宽按字节算
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RED, kAtlasSize, kAtlasSize, 0,
                 GL_RED, GL_UNSIGNED_BYTE, bitmap.data());
    // 位图字体（ProggyClean 等）用最近邻采样才锐利；线性过滤会把像素字糊掉
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    return true;
}

void Renderer::emit_backgrounds(const Screen& screen, int ox, int oy, bool given_bg_only) {
    const float cw = static_cast<float>(cell_w_);
    const float chh = static_cast<float>(cell_h_);
    // 底色四边形：UV 指向图集空白处（采样恒为 0），fg 也传底色 —— 混出来就是纯底色
    auto push_vert = [&](float px, float py, const Color& bg) {
        float f = 1.0f / 255.0f;
        vertices_.insert(vertices_.end(), {
            px, py, 0.0f, 0.0f,
            bg.r * f, bg.g * f, bg.b * f,
            bg.r * f, bg.g * f, bg.b * f});
    };

    for (int y = 0; y < screen.height(); ++y) {
        for (int x = 0; x < screen.width(); ++x) {
            const Cell& cell = screen.at(x, y);
            if (cell.cols == 0) continue;  // 续格：整格由左邻的宽字形覆盖
            // 图层：没给过底色的格**什么都不铺**，下层从这一格透出来
            if (given_bg_only && cell.alpha == 0) continue;

            const float bx0 = (ox + x) * cw, by0 = (oy + y) * chh;
            const float bx1 = bx0 + (cell.cols == 2 ? cw * 2 : cw), by1 = by0 + chh;
            push_vert(bx0, by0, cell.bg);
            push_vert(bx1, by0, cell.bg);
            push_vert(bx1, by1, cell.bg);
            push_vert(bx0, by0, cell.bg);
            push_vert(bx1, by1, cell.bg);
            push_vert(bx0, by1, cell.bg);
        }
    }
}

void Renderer::emit_glyphs(const Screen& screen, int ox, int oy, bool layer, GlyphPick pick) {
    const float cw = static_cast<float>(cell_w_);
    const float chh = static_cast<float>(cell_h_);
    auto push_vert = [&](float px, float py, float u, float v, const Color& fg, const Color& bg) {
        float f = 1.0f / 255.0f;
        vertices_.insert(vertices_.end(), {
            px, py, u, v,
            fg.r * f, fg.g * f, fg.b * f,
            bg.r * f, bg.g * f, bg.b * f});
    };

    // 推**一笔**：几何与底色归位都在这里，一笔一份四边形。
    // 与"一格一份"的区别只在调用次数 —— 叠了笔的格会调它两次以上
    const auto push_pen = [&](int x, int y, char32_t ch, const Color& fg, const Color& bg) {
        // 字体链里没有该字形时退到占位符：宁可显示 '?'，也不留一格空白
        const Glyph* glyph = glyph_for(ch);
        if (!glyph) glyph = glyph_for(U'?');
        if (!glyph) return;

        const Glyph& g = *glyph;
        const float s = pack_scale_;
        const float gx = (ox + x) * cw + g.xoff * s;
        const float gy = (oy + y) * chh + (font_ascent_ + g.yoff) * s;
        const float gw = g.w * s;
        const float gh = g.h * s;

        // 字形四边形。宽字符的位图天然跨两格，续格自身不绘制
        push_vert(gx, gy, g.u0, g.v0, fg, bg);
        push_vert(gx + gw, gy, g.u1, g.v0, fg, bg);
        push_vert(gx + gw, gy + gh, g.u1, g.v1, fg, bg);
        push_vert(gx, gy, g.u0, g.v0, fg, bg);
        push_vert(gx + gw, gy + gh, g.u1, g.v1, fg, bg);
        push_vert(gx, gy + gh, g.u0, g.v1, fg, bg);
    };

    for (int y = 0; y < screen.height(); ++y) {
        for (int x = 0; x < screen.width(); ++x) {
            const Cell& cell = screen.at(x, y);
            if (cell.cols == 0) continue;   // 续格：宽字形由头格一次画完
            // 趟的分配看这一格**有没有笔迹**：没有的走不透明趟，有的走覆盖率趟。
            // 逐格分趟而不是整屏分趟 —— 一趟只能有一种写法，整屏分趟会把底也带上
            const bool has_pens = !screen.inks(x, y).empty();
            if (pick == GlyphPick::pens && !has_pens) continue;
            if (pick == GlyphPick::plain && has_pens) continue;
            // 注意：图层里"有字形但没底色"是**正常**的（雨滴就是这样），不能跳过
            //
            // 顺序：先按**追加顺序**推这一格的笔迹，最后才推 ch —— ch 是最前面那一笔。
            // 同一格里于是"先深后浅"（底线、风痕、正在画的这一笔各归各位），
            // 而不是后来者把前者顶掉
            for (const Screen::Ink& ink : screen.inks(x, y)) {
                if (ink.ch != U' ') push_pen(x, y, ink.ch, ink.fg, cell.bg);
            }
            if (cell.ch != U' ') push_pen(x, y, cell.ch, cell.fg, cell.bg);  // 空格没有字形
        }
    }
}

void Renderer::submit(float win_w, float win_h, bool layer, bool clear_first) {
    // 视口用**帧缓冲**尺寸（高 DPI 下大于逻辑尺寸）：NDC 仍按逻辑尺寸算（u_resolution），
    // 于是逻辑画面被拉伸铺满整个 framebuffer，而不是只占左下角一块
    const int vw = fb_w_ > 0 ? fb_w_ : static_cast<int>(win_w);
    const int vh = fb_h_ > 0 ? fb_h_ : static_cast<int>(win_h);
    glViewport(0, 0, vw, vh);
    // 清屏**整帧只能有一次**（画底那一趟）。逐层叠画时每层也要铺底，但那是画在
    // 已经画好的画面上：谁再清一次，底就被抹掉，画面只剩各层的字形
    if (clear_first) {
        glClearColor(0.0f, 0.0f, 0.0f, 1.0f);
        glClear(GL_COLOR_BUFFER_BIT);
    }
    // 图层趟按覆盖率混合：底趟全是 alpha = 1，开关对它没有影响
    if (layer) {
        glEnable(GL_BLEND);
        glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    } else {
        glDisable(GL_BLEND);
    }

    shader_.use();
    shader_.set_vec2("u_resolution", win_w, win_h);
    shader_.set_int("u_font", 0);
    shader_.set_vec2("u_texel", 1.0f / kAtlasSize, 1.0f / kAtlasSize);

    auto set_float = [this](const char* name, float value) {
        glUniform1f(glGetUniformLocation(shader_.id(), name), value);
    };
    set_float("u_period", kScanlinePeriodPx);
    set_float("u_maskperiod", kMaskPeriodPx);
    set_float("u_scan", crt_.scanline);
    set_float("u_mask", crt_.mask);
    set_float("u_glow", crt_.glow);
    // 补偿扫描线与格栅造成的平均亮度损失（按暗线占比与格栅通道占比估算），
    // 使"档位越高结构越明显，但整体亮度基本不变"
    const float loss = crt_.scanline * kScanlineLossPerUnit + crt_.mask * kMaskLossPerUnit;
    set_float("u_comp", crt_.compensate ? 1.0f + loss : 1.0f);
    set_float("u_layer", layer ? 1.0f : 0.0f);
    shader_.set_vec2("u_darkline", kScanlineDarkStart, kScanlineDarkEnd);
    glUniform3f(glGetUniformLocation(shader_.id(), "u_tint"),
                crt_.tint.r / 255.0f, crt_.tint.g / 255.0f, crt_.tint.b / 255.0f);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, font_tex_);

    glBindVertexArray(vao_);
    glBindBuffer(GL_ARRAY_BUFFER, vbo_);
    glBufferData(GL_ARRAY_BUFFER,
                 static_cast<GLsizeiptr>(vertices_.size() * sizeof(float)),
                 vertices_.data(), GL_DYNAMIC_DRAW);
    glDrawArrays(GL_TRIANGLES, 0, static_cast<GLsizei>(vertices_.size() / 10));
    glBindVertexArray(0);
}

void Renderer::draw(const Screen& screen) {
    win_w_px_ = static_cast<float>(cell_w_) * screen.width();
    win_h_px_ = static_cast<float>(cell_h_) * screen.height();

    vertices_.clear();
    // 单趟峰值：字形趟每格最多 (kMaxInks+1) 块四边形（叠笔 + 主字形），每块 6 顶点 ×10 float。
    // 一次 reserve 覆盖本帧后面所有趟（clear 不缩容），避免逐趟 realloc
    vertices_.reserve(static_cast<size_t>(screen.width()) * screen.height() *
                      (Screen::kMaxInks + 1) * 6 * 10);
    emit_backgrounds(screen, 0, 0, false);
    // ① 底：**不透明**，整帧唯一一次清屏
    submit(win_w_px_, win_h_px_, false, true);

    // ② 字分两趟。没笔迹的格不透明（不动既有画面），有笔迹的格按字形覆盖率叠到
    //    已经画好的底上 —— 同格里几笔于是各自留下自己的笔画，而不是后来者把前者顶掉。
    //    两趟各自一次 submit：一趟只能有一种"透不透"
    vertices_.clear();
    emit_glyphs(screen, 0, 0, false, GlyphPick::plain);
    if (!vertices_.empty()) submit(win_w_px_, win_h_px_, false, false);

    vertices_.clear();
    emit_glyphs(screen, 0, 0, true, GlyphPick::pens);
    if (!vertices_.empty()) submit(win_w_px_, win_h_px_, true, false);
}

void Renderer::draw_overlay(const Screen& overlay, int origin_x, int origin_y) {
    // ① 只铺 overlay **真的给了底色**的格（alpha != 0）：其余格透出下层
    vertices_.clear();
    emit_backgrounds(overlay, origin_x, origin_y, true);
    if (!vertices_.empty()) submit(win_w_px_, win_h_px_, false, false);
    // ② 画 glyph（笔画为实、笔画之外透明）
    vertices_.clear();
    emit_glyphs(overlay, origin_x, origin_y, true);
    if (!vertices_.empty()) submit(win_w_px_, win_h_px_, true, false);
}

void Renderer::draw_layers(const LayeredScreen& layers, int origin_x, int origin_y) {
    for (const Layer* layer : layers.ordered()) {
        if (!layer->visible) continue;

        // ① 铺这层的底：只有它**真的给了底色**的格才铺（铺了就盖住下面）
        vertices_.clear();
        emit_backgrounds(layer->cells, origin_x, origin_y, true);
        if (!vertices_.empty()) submit(win_w_px_, win_h_px_, false, false);

        // ② 画这层的字：笔画为实、笔画之外透明，于是与下层**叠**在一起，
        //    而不是把下层的字形顶掉（雨滴落在山体上就是这样叠出来的）
        vertices_.clear();
        emit_glyphs(layer->cells, origin_x, origin_y, true);
        if (!vertices_.empty()) submit(win_w_px_, win_h_px_, true, false);
    }
}

bool Renderer::read_frame(std::vector<unsigned char>& rgba, int& width, int& height) {
    // 读回尺寸与视口一致：有帧缓冲尺寸就用它（高 DPI 下读的是整帧，而非左下角一块）
    const int w = fb_w_ > 0 ? fb_w_ : static_cast<int>(win_w_px_);
    const int h = fb_h_ > 0 ? fb_h_ : static_cast<int>(win_h_px_);
    if (w <= 0 || h <= 0) return false;  // 还没画过任何一帧

    rgba.assign(static_cast<size_t>(w) * static_cast<size_t>(h) * 4, 0);
    glPixelStorei(GL_PACK_ALIGNMENT, 1);
    glBindFramebuffer(GL_FRAMEBUFFER, 0);
    glReadBuffer(GL_BACK);  // 双缓冲下读回的才是刚画好的那一帧（默认 framebuffer 的后缓冲）
    glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, rgba.data());
    width = w;
    height = h;
    return true;
}

GlyphBox Renderer::ink_box(char32_t cp) {
    const Glyph* glyph = glyph_for(cp);
    if (!glyph) return GlyphBox{0, cell_w_, true};
    const float xoff = glyph->xoff * pack_scale_;
    return GlyphBox{static_cast<int>(xoff < 0.0f ? xoff - 0.5f : xoff + 0.5f),
                    static_cast<int>(glyph->w * pack_scale_ + 0.5f), false};
}

} // namespace phos

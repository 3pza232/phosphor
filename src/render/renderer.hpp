#pragma once

#include "core/crt.hpp"
#include "core/screen.hpp"
#include "render/shader.hpp"

#include <memory>
#include <string>
#include <unordered_map>
#include <vector>

namespace phos {

class FontChain;

/// 网格渲染器：Screen → 字体图集 → OpenGL。
/// 后处理参数：扫描线与色调由 palette 内容包覆盖，辉光/孔径格栅由 CRT 档位给出。
/// 这里只按参数计算，不决定风格数值。
class Renderer {
public:
    Renderer();
    ~Renderer();
    Renderer(const Renderer&) = delete;
    Renderer& operator=(const Renderer&) = delete;

    /// 初始化 GL 资源与字体图集。font_files 为字体链（首个为主字体，其余为回退），
    /// cell_w/cell_h 为目标单元格像素尺寸（字形等比缩放填入，保持比例）。
    /// 调用前须已有当前 GL 上下文且 glad 已加载。
    bool init(const std::vector<std::string>& font_files, int cell_w, int cell_h, std::string& err);

    /// 换字体（切换字体方案）：重装字体链、重建字形图集，并丢弃动态区已缓存的字形。
    /// 字体文件全部不可用时返回 false 且**不动已生效的字体**（换字失败不该黑屏）。
    bool reload_fonts(const std::vector<std::string>& font_files, std::string& err);

    /// 绘制整个字符网格
    void draw(const Screen& screen);

    /// CRT 后处理参数（扫描线 / 孔径格栅 / 辉光 / 色调），由 App 综合档位与滤镜给出
    void set_crt(const CrtParams& params) { crt_ = params; }

    int cell_w() const { return cell_w_; }
    int cell_h() const { return cell_h_; }

private:
    /// 图集里的一个字形
    struct Glyph {
        float u0, v0, u1, v1;   // 图集 UV
        float xoff, yoff;       // 相对单元格基线偏移（像素，kFontPixels 尺度）
        float w, h;             // 字形尺寸（像素）
    };

    /// 装载字体链（跳过坏字体并告警）；一个可用字体都没有时返回空
    static std::unique_ptr<FontChain> load_font_chain(const std::vector<std::string>& font_files);
    /// 用已装载的字体链重建图集与度量（换字体与初始化共用）
    bool build_font_atlas(std::unique_ptr<FontChain> fonts, std::string& err);
    /// 取字形：ASCII 走静态区，其余按需光栅化并装入动态区。
    /// 返回 nullptr 表示字体链里没有这个字形（调用方改用占位符）。
    const Glyph* glyph_for(char32_t cp);
    void destroy();

    Shader shader_;
    unsigned vao_ = 0, vbo_ = 0;
    unsigned font_tex_ = 0;

    int cell_w_ = 16, cell_h_ = 16;
    float font_ascent_ = 0.0f;
    CrtParams crt_{};

    // ASCII 32..126 的字形信息（静态区：一次打包，跨帧复用）
    Glyph glyphs_[95]{};
    float pack_scale_ = 1.0f;

    // 字体链与动态区：CJK 等大码集不可能全量打包，用到哪个装哪个
    std::unique_ptr<FontChain> fonts_;
    std::unordered_map<char32_t, Glyph> extra_glyphs_;
    int pen_x_ = 0, pen_y_ = 0, pen_row_h_ = 0;  // 动态区的行式装箱指针
    bool atlas_full_ = false;                    // 装满了就不再尝试（只警告一次）

    std::vector<float> vertices_;  // 每帧重建的顶点数据
};

} // namespace phos

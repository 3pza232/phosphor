#pragma once

#include "core/text.hpp"

#include "core/crt.hpp"
#include "core/layered_screen.hpp"
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

    /// 在**已经画好的底**之上，按 z 升序把各图层逐层叠画一遍（像素级合成）。
    /// 与"把层合并进一块网格再画"的区别：一格里能同时看到两层的笔画 ——
    /// 层的字形只占自己的笔画，笔画之外是**透明**的，下面的地形/角色原样透出来
    /// （文本视图仍是一格一个字形，见 LayeredScreen::merge_over）。
    void draw_layers(const LayeredScreen& layers, int origin_x, int origin_y);

    /// 在**所有图层之上**再叠一块网格：主机 chrome（侧栏底色/分隔线等）。
    /// 与 draw_layers 同一套像素级合成（透明处透出下层），只是不参与卡带的图层栈
    void draw_overlay(const Screen& overlay, int origin_x, int origin_y);

    /// 目标帧缓冲尺寸（**物理像素**）：App 每帧从窗口查得后写入。高 DPI / 分数缩放下它
    /// 大于逻辑网格尺寸——视口与读回用它，逻辑画面才会铺满整个 framebuffer（否则只占左下角）
    void set_framebuffer_size(int w, int h) {
        fb_w_ = w;
        fb_h_ = h;
    }

    /// 一个字形在格内的墨迹框（像素，相对格左缘）。按需装入字形，与绘制同一份度量；
    /// 字体链里没有该字形时退回整格宽并置 approx
    GlyphBox ink_box(char32_t cp);

    /// 读回**当前帧缓冲**的像素（RGBA8，行序自下而上，遵循 OpenGL 约定）。
    /// 这是 GL 渲染路唯一的像素出口：`screenshot` 走 CPU 光栅化，覆盖不到着色器
    /// 分支与逐层叠画。只在窗口路径有意义，且必须在 draw() / draw_layers() 之后、
    /// swap 之前调用——swap 之后后缓冲内容不再有定义。成功填 width/height 并返回 true。
    bool read_frame(std::vector<unsigned char>& rgba, int& width, int& height);

    /// CRT 后处理参数（扫描线 / 孔径格栅 / 辉光 / 色调），由 App 综合档位与色板给出
    void set_crt(const CrtParams& params) { crt_ = params; }

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

    /// 把一块网格的**底色**推成整格四边形（每格一块）。
    /// given_bg_only = true 时只推**给过底色**的格（alpha != 0）—— 图层没铺底的格
    /// 必须让下层透出来。它与 emit_glyphs / submit 的 layer 是**两件事**，
    /// 名字因此不共用：那边说的是"按笔画覆盖率输出"，这边说的是"哪些格有底"
    void emit_backgrounds(const Screen& screen, int origin_x, int origin_y, bool given_bg_only);
    /// 一趟推哪些格的字形。**基屏的底与字必须分开趟**：着色器一趟只能有一种
    /// "透不透"，把带笔迹的格与底趟混在一趟里，底色的四边形也会被按覆盖率输出
    /// （覆盖率恒为 0 → 底色整块消失，画面全黑只剩字形笔画）
    enum class GlyphPick {
        all,    ///< 全部格（图层趟用：层里的格一律按覆盖率发）
        plain,  ///< 只推**没有笔迹**的格（走不透明趟）
        pens,   ///< 只推**有笔迹**的格（按覆盖率叠到已画好的底上）
    };

    /// 把一块网格的**字形**推成四边形（空格与续格不推）。
    /// layer = true 时这些四边形在着色器里按笔画覆盖率输出 alpha，成为"叠"而不是"盖"
    void emit_glyphs(const Screen& screen, int origin_x, int origin_y, bool layer,
                     GlyphPick pick = GlyphPick::all);
    /// 上传已攒好的顶点并下发一次绘制。
    /// win_w/win_h 是窗口像素尺寸（图层缓冲比它小，NCD 换算得用它）；
    /// layer 决定走"笔画透明"的着色分支；clear_first **整帧只能有一次** ——
    /// 逐层叠画时每个铺底趟都要画在已经画好的画面上，谁再清一次就把底抹掉了
    void submit(float win_w_px, float win_h_px, bool layer, bool clear_first);

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
    // 窗口像素尺寸：draw() 时记下，逐层叠画要拿它做 NDC 换算（层缓冲比窗口小）
    float win_w_px_ = 0.0f, win_h_px_ = 0.0f;
    // 帧缓冲尺寸（物理像素）：非零就用它做 glViewport / glReadPixels，否则回退到逻辑尺寸
    int fb_w_ = 0, fb_h_ = 0;
};

} // namespace phos

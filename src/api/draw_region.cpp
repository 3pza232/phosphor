#include "api/draw_region.hpp"

#include "api/ui_api.hpp"
#include "core/text.hpp"

#include <algorithm>
#include <utility>

namespace phos {

namespace {

/// 区域锚定的表层左边界与宽度：内容区（默认）或侧栏面板
int surface_x(const HostContext& host, const std::string& surface) {
    return surface == "panel" ? host.panel_origin_x() : host.content_x;
}

int surface_w(const HostContext& host, const std::string& surface) {
    return surface == "panel" ? host.panel_w : host.content_w;
}

} // namespace

DrawRegion::DrawRegion(HostContext& host, std::string surface, int x, int y, int w, int h)
    : host_(host), surface_(std::move(surface)), x_(x), y_(y), w_(w), h_(h) {
    // 与表层可用范围求交：越界部分直接不要，而不是让每次绘制各自做边缘判断。
    // 求交只做一次，字段给出的就是"实际能画的区域"。
    const int limit_w = surface_w(host_, surface_);
    const int limit_h = host_.content_h;
    const int left = std::max(x_, 0);
    const int top = std::max(y_, 0);
    const int right = std::min(x_ + w_, limit_w);
    const int bottom = std::min(y_ + h_, limit_h);
    x_ = left;
    y_ = top;
    w_ = std::max(0, right - left);
    h_ = std::max(0, bottom - top);
}

// 局部 → 绝对：表层起点 + **区域自身的偏移** + 区域内坐标。
// 少了中间那项，整块区域会落到表层左上角，而不是区域自己的位置
int DrawRegion::abs_x(int x) const { return surface_x(host_, surface_) + x_ + x; }
int DrawRegion::abs_y(int y) const { return host_.content_y + y_ + y; }

ui::Style DrawRegion::style() const { return cart_style(host_); }

void DrawRegion::clear(Color fg, Color bg) { fill(0, 0, w_, h_, U' ', fg, bg); }

void DrawRegion::put(int x, int y, char32_t ch, Color fg, Color bg) {
    const int cols = text::char_width(ch);
    // 宽字符在最后一列放不下：宁可少画一个字，也不让它溢出到区域外
    if (cols == 0 || x < 0 || y < 0 || x + cols > w_ || y >= h_) return;
    screen().put(abs_x(x), abs_y(y), ch, fg, bg);
}

void DrawRegion::print(int x, int y, std::string_view text, Color fg, Color bg) {
    if (y < 0 || y >= h_) return;
    int col = x;
    for (char32_t cp : text::decode(text)) {
        const int cols = text::char_width(cp);
        if (cols == 0) continue;
        if (col + cols > w_) break;  // 右边界放不下就停，宁少画不错位
        if (col >= 0) screen().put(abs_x(col), abs_y(y), cp, fg, bg);
        col += cols;
    }
}

void DrawRegion::fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg) {
    for (int row = y; row < y + h; ++row)
        for (int col = x; col < x + w; ++col) put(col, row, ch, fg, bg);
}

void DrawRegion::blit(int x, int y, const std::vector<std::string>& rows, Color fg, Color bg) {
    for (size_t i = 0; i < rows.size(); ++i) print(x, y + static_cast<int>(i), rows[i], fg, bg);
}

void DrawRegion::put_fg(int x, int y, char32_t ch, Color fg) {
    const int cols = text::char_width(ch);
    if (cols == 0 || x < 0 || y < 0 || x + cols > w_ || y >= h_) return;
    screen().put_fg(abs_x(x), abs_y(y), ch, fg);
}

void DrawRegion::print_fg(int x, int y, std::string_view text, Color fg) {
    if (y < 0 || y >= h_) return;
    int col = x;
    for (char32_t cp : text::decode(text)) {
        const int cols = text::char_width(cp);
        if (cols == 0) continue;
        if (col + cols > w_) break;
        if (col >= 0) screen().put_fg(abs_x(col), abs_y(y), cp, fg);
        col += cols;
    }
}

void DrawRegion::fill_fg(int x, int y, int w, int h, char32_t ch, Color fg) {
    for (int row = y; row < y + h; ++row)
        for (int col = x; col < x + w; ++col) put_fg(col, row, ch, fg);
}

void DrawRegion::blit_fg(int x, int y, const std::vector<std::string>& rows, Color fg) {
    for (size_t i = 0; i < rows.size(); ++i)
        print_fg(x, y + static_cast<int>(i), rows[i], fg);
}

void DrawRegion::frame(std::string_view title) {
    ui::frame(screen(), ui::Rect{abs_x(0), abs_y(0), w_, h_}, title, style());
}

void DrawRegion::divider(int y) {
    if (y < 0 || y >= h_) return;
    ui::Style s = style();
    ui::divider(screen(), abs_x(0), abs_y(y), w_, s.dim, s.bg);
}

void DrawRegion::bar(int x, int y, int w, float ratio) {
    if (y < 0 || y >= h_) return;
    ui::bar(screen(), abs_x(x), abs_y(y), std::min(w, w_ - x), ratio, style());
}

void DrawRegion::menu(int x, int y, int w, const std::vector<std::string>& items, int selected,
                      int h) {
    if (items.empty()) return;
    const int height = h > 0 ? h : static_cast<int>(items.size());
    if (y + height <= 0 || y >= h_) return;
    ui::menu(screen(), ui::Rect{abs_x(x), abs_y(y), std::min(w, w_ - x), height}, items, selected,
             style());
}

void DrawRegion::body(int x, int y, int w, std::string_view text, int max_lines) {
    if (y < 0 || y >= h_) return;
    ui::text_block(screen(), abs_x(x), abs_y(y), std::min(w, w_ - x), text,
                   max_lines > 0 ? max_lines : 1, style());
}

void DrawRegion::sprite(int x, int y, const std::vector<std::string>& rows,
                        const std::map<char, Color>& colors, int step) {
    if (rows.empty()) return;
    int art_w = 0;
    for (const auto& row : rows)
        art_w = std::max(art_w, static_cast<int>(row.size()));
    const int art_h = static_cast<int>(rows.size());
    // ui::icon 以中心定位；这里按左上角语义换算，越界部分由 icon/screen 自己夹住
    ui::icon(screen(), rows, colors, abs_x(x) + art_w / 2, abs_y(y) + art_h / 2,
             step < 1 ? 1 : step, 1.0f, style().accent);
}

} // namespace phos

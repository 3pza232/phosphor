#include "api/draw_region.hpp"

#include "api/ui_api.hpp"
#include "core/log.hpp"
#include "core/text.hpp"

#include <algorithm>
#include <utility>

namespace phos {

namespace {

/// 区域锚定到的面的左边界与宽度：内容区（默认）或侧栏面板
int anchor_x(const HostContext& host, const std::string& anchor) {
    return anchor == "panel" ? host.panel_origin_x() : host.content_x;
}

int anchor_w(const HostContext& host, const std::string& anchor) {
    return anchor == "panel" ? host.panel_w : host.content_w;
}

} // namespace

DrawRegion::DrawRegion(HostContext& host, std::string anchor, std::string layer, int x, int y,
                       int w, int h)
    : host_(host), anchor_(std::move(anchor)), layer_(std::move(layer)), x_(x), y_(y), w_(w), h_(h) {
    // 与锚定面的可用范围求交：越界部分直接不要，而不是让每次绘制各自做边缘判断。
    // 求交只做一次，字段给出的就是"实际能画的区域"。
    const int limit_w = anchor_w(host_, anchor_);
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

Screen& DrawRegion::screen() const {
    if (Layer* layer = resolved_layer()) return layer->cells;
    return *host_.screen;
}

Layer* DrawRegion::resolved_layer() const {
    if (layer_.empty()) return nullptr;
    if (Layer* layer = host_.layers.find(layer_)) return layer;
    // 层没了（注销过、或名字写错）：回落到内容区。画在别处比什么都不画更难查，
    // 所以留痕——只留一次
    if (!warned_missing_layer_) {
        warned_missing_layer_ = true;
        log::warn("phos.ui.region: layer \"" + layer_ + "\" 不存在，回落到内容区");
    }
    return nullptr;
}

// 局部 → 绝对：锚定面起点 + **区域自身的偏移** + 区域内坐标。
// 少了中间那项，整块区域会落到面的左上角，而不是区域自己的位置。
// 层缓冲自带原点（内容区局部），所以那一路上"锚定面起点"是 0
int DrawRegion::abs_x(int x) const {
    const int base = resolved_layer() ? 0 : anchor_x(host_, anchor_);
    return base + x_ + x;
}
int DrawRegion::abs_y(int y) const {
    const int base = resolved_layer() ? 0 : host_.content_y;
    return base + y_ + y;
}

int DrawRegion::room_w() const {
    // w_ 是构造时与当时面宽的交集：面板之后被 phos.panel.resize 改窄，它就会偏大
    const int room = anchor_w(host_, anchor_) - x_;
    return w_ < room ? w_ : room;
}

int DrawRegion::clip_w(int x, int w) const {
    const int avail = room_w() - x;
    if (avail <= 0) return 0;
    return w < avail ? w : avail;
}

Surface DrawRegion::surface_of() const {
    return Surface(screen(), abs_x(0), abs_y(0), room_w(), h_);
}

ui::Style DrawRegion::style() const { return cart_style(host_); }

void DrawRegion::clear(Color fg, Color bg) { surface_of().clear(fg, bg); }

void DrawRegion::put(int x, int y, char32_t ch, Color fg, Color bg) {
    surface_of().put(x, y, ch, fg, bg);
}

void DrawRegion::print(int x, int y, std::string_view text, Color fg, Color bg) {
    surface_of().print(x, y, text, fg, bg);
}

void DrawRegion::fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg) {
    surface_of().fill(x, y, w, h, ch, fg, bg);
}

void DrawRegion::blit(int x, int y, const std::vector<std::string>& rows, Color fg, Color bg) {
    surface_of().blit(x, y, rows, fg, bg);
}

bool DrawRegion::blend(int x, int y, char32_t ch, Color fg) {
    return surface_of().blend(x, y, ch, fg);
}

void DrawRegion::back(int x, int y, Color bg) { surface_of().back(x, y, bg); }

void DrawRegion::back_rect(int x, int y, int w, int h, Color bg) {
    surface_of().back_rect(x, y, w, h, bg);
}

void DrawRegion::plot(int x2, int y2, Color fg) { surface_of().plot(x2, y2, fg); }

void DrawRegion::frame(std::string_view title) {
    ui::frame(screen(), ui::Rect{abs_x(0), abs_y(0), room_w(), h_}, title, style());
}

void DrawRegion::divider(int y) {
    if (y < 0 || y >= h_) return;
    ui::Style s = style();
    ui::divider(screen(), abs_x(0), abs_y(y), room_w(), s.dim, s.bg);
}

void DrawRegion::bar(int x, int y, int w, float ratio) {
    if (y < 0 || y >= h_) return;
    ui::bar(screen(), abs_x(x), abs_y(y), clip_w(x, w), ratio, style());
}

void DrawRegion::menu(int x, int y, int w, const std::vector<std::string>& items, int selected,
                      int h) {
    if (items.empty()) return;
    const int height = h > 0 ? h : static_cast<int>(items.size());
    if (y + height <= 0 || y >= h_) return;
    ui::menu(screen(), ui::Rect{abs_x(x), abs_y(y), clip_w(x, w), height}, items, selected,
             style());
}

void DrawRegion::body(int x, int y, int w, std::string_view text, int max_lines) {
    if (y < 0 || y >= h_) return;
    ui::text_block(screen(), abs_x(x), abs_y(y), clip_w(x, w), text,
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

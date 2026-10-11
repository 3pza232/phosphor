#pragma once

#include "api/host_api.hpp"
#include "core/screen.hpp"
#include "core/surface.hpp"
#include "core/ui.hpp"

#include <map>
#include <string>
#include <string_view>
#include <vector>

namespace phos {

/// 卡带侧"绘制区域"（Lua: `phos.ui.region`）。
///
/// 一个**带裁剪的矩形**：所有坐标相对区域左上角，超出边界的一律不画。
/// 两种用法同源——这正是"浮动窗口"与"非浮动分区窗口"的统一做法：
///   - **非浮动分区**：侧栏某块放小地图、游戏区某块放状态条
///   - **浮动窗口**：卡带自己的设置/暂停/背包面板（画在底图之后即可）
///
/// 本机每帧清屏、卡带每帧重画，所以**层级就是调用顺序**：先画底图、再画窗口。
/// 不需要"备份背景再还原"那类机制——窗口关闭时不再画它，底图自然就在。
///
/// 写入本身交给 `Surface`：区域与内容区、侧栏面板的差别只是"原点在哪、裁到哪为止"，
/// 越界裁剪、透明底、宽字符占格的规则三处必须一致，所以只写一份。
///
/// `anchor` 决定锚定在哪个面："screen"（内容区，默认）或 "panel"（侧栏面板）；
/// 它在 Lua 侧的名字是 `surface`。
/// 构造时会与表层的可用范围**求交**（越界部分直接不要），所以 x/y/w/h 给出的
/// 就是实际可画范围，卡带据此排版即可。
///
/// `layer` 非空时，区域改锚定到该**图层**（坐标原点在内容区左上角，与 screen 同域）：
/// 写入落在那块层缓冲上，合成时再叠到世界之上。
class DrawRegion {
public:
    DrawRegion(HostContext& host, std::string anchor, std::string layer, int x, int y, int w, int h);

    int x() const { return x_; }
    int y() const { return y_; }
    int w() const { return w_; }
    int h() const { return h_; }
    /// 区域锚定的面：内容区（"screen"）/ 侧栏（"panel"）/ 层名
    const std::string& anchor() const { return layer_.empty() ? anchor_ : layer_; }

    // 坐标均为区域局部坐标；颜色由 Lua 绑定层转换后传入
    void clear(Color fg, Color bg);
    void put(int x, int y, char32_t ch, Color fg, Color bg);
    void print(int x, int y, std::string_view text, Color fg, Color bg);
    void fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg);
    /// 一次写多行（每行一条字符串）：地图/画面搬运用，避免逐格与逐行调用
    void blit(int x, int y, const std::vector<std::string>& rows, Color fg, Color bg);
    void frame(std::string_view title);
    void divider(int y);
    void bar(int x, int y, int w, float ratio);
    void menu(int x, int y, int w, const std::vector<std::string>& items, int selected, int h);
    void body(int x, int y, int w, std::string_view text, int max_lines);
    void sprite(int x, int y, const std::vector<std::string>& rows,
                const std::map<char, Color>& colors, int step);

private:
    /// 本区域写入的目标网格：锚定层时是那块层缓冲，否则是整屏
    Screen& screen() const;
    /// 锚定到的层；未锚定层、或层已被注销时返回 nullptr（含一次留痕）
    Layer* resolved_layer() const;
    /// 本区域对应的一块面。每次现取：面板宽度可在运行时改，缓存就会用旧几何
    Surface surface_of() const;
    /// 区域在**当前**面宽下还能用的宽度：w_ 是构造时与当时面宽的交集，面板变窄后会偏大
    int room_w() const;
    /// 区域内一条横线的实际可用宽度（x 为区域内坐标，放不下就是 0）
    int clip_w(int x, int w) const;
    ui::Style style() const;
    /// 局部坐标 → 绝对网格坐标（锚点决定横向基准）
    int abs_x(int x) const;
    int abs_y(int y) const;

    HostContext& host_;
    std::string anchor_;
    std::string layer_;                      // 空 = 不锚定层
    mutable bool warned_missing_layer_ = false;  // 层不存在只留一次痕（每帧都留会刷满日志）
    int x_ = 0, y_ = 0, w_ = 0, h_ = 0;
};

} // namespace phos

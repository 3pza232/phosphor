#pragma once

#include "core/color.hpp"
#include "core/screen.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace phos {

/// 屏幕上一块**可写矩形**：卡带内容区、侧栏面板、卡带的绘制区域都是它的实例。
///
/// 三者真正的差别只有"原点在哪、写到哪为止"；写入规则（越界怎么裁、宽字符占几格、
/// 省略底色是什么意思）必须一致，所以只在这里写一份。
///
/// 坐标是**面内局部坐标**，原点在面的左上角。越界一律不写：卡带既不必为边缘做
/// 防御性编程，也写不到面板另一侧与机身装饰上。
///
/// `bg` 带 `Color::keep` 时保留该格原有底色，即 Lua 侧"没给背景色"的语义；
/// 要不要 keep 由各绑定层决定（见 docs/api-reference.md 里那两组规则）。
class Surface {
public:
    Surface(Screen& screen, int origin_x, int origin_y, int w, int h);

    /// 写一个字符。宽字符在最后一列放不下时整格不写（宁少画一个字，不留半个）
    void put(int x, int y, char32_t ch, Color fg, Color bg);
    /// 写一行文本。超出右缘的部分按**显示宽度**截断，左缘之外的部分不写
    void print(int x, int y, std::string_view text, Color fg, Color bg);
    /// 填一块矩形。宽字符按两格一组铺，末列只剩一格时留空
    void fill(int x, int y, int w, int h, char32_t ch, Color fg, Color bg);
    /// 一次写多行（每行一条字符串），逐行按 print 的规则
    void blit(int x, int y, const std::vector<std::string>& rows, Color fg, Color bg);
    /// 追加一笔（**叠加**：不清掉这一格已有的字形与笔迹）。
    /// 同格里两笔各自按字形覆盖率混合，"两个东西落在同一格"因此是叠加而不是顶替。
    /// 只收半角字形（宽字要占两格，那是 put 的活）；返回 false = 越界或这一格已满
    bool blend(int x, int y, char32_t ch, Color fg);
    /// 只写底色：字形与已叠的笔迹都不动。"背景比字形宽一格"就是在本格之外再 back 一次
    void back(int x, int y, Color bg);
    /// 整块只写底色（与 fill 的分工：fill 连字形一起写）
    void back_rect(int x, int y, int w, int h, Color bg);
    /// 在**子位**上落一笔：x / y 是子格坐标（一格 = 2x2 子位）。
    /// 同一格的多次 plot 合并成一个象限字形，位序见 Screen::quadrant_glyph
    void plot(int x2, int y2, Color fg);
    /// 整面填成空格
    void clear(Color fg, Color bg) { fill(0, 0, w_, h_, U' ', fg, bg); }

    /// 读本面某格；越界返回空白格
    const Cell& at(int x, int y) const;
    /// 读本面某格的**字符**：续格报它的头格，控制字符报 0（与文本导出同一份判断）
    char32_t glyph_at(int x, int y) const;

private:
    bool inside(int x, int y) const { return x >= 0 && y >= 0 && x < w_ && y < h_; }

    Screen& screen_;
    int ox_ = 0, oy_ = 0, w_ = 0, h_ = 0;
};

} // namespace phos

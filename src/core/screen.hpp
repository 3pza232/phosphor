#pragma once

#include "core/color.hpp"

#include <cstdint>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

namespace phos {

/// 屏幕一格。ch 为 Unicode 码点。
///
/// 全角字符（CJK 等）占两格：左格是"头"（`cols = 2`），右格是"续格"
/// （`cols = 0`，自身没有字形，绘制时跳过）。这样"格"仍然是等宽单位，
/// 渲染与对齐只需认 `cols`，不必满屏推断宽度。
struct Cell {
    char32_t ch = U' ';
    Color fg = Color::white;
    Color bg = Color::black;
    /// 列宽：1 = 半角；2 = 全角头格；0 = 续格（右半，由左邻格决定外观）
    uint8_t cols = 1;
    /// 底色是否存在：0 = 透明（层合成时跳过底色），非 0 = 存在。
    /// 只有**图层缓冲**会用到 0——底层网格的每一次写入都是不透明的（见 Layer / LayeredScreen）
    uint8_t alpha = 255;

    /// 抹掉这一格的字形，**保留底色与存在性**。宽字被截断、层用空格抹掉下层字形时用；
    /// 是全工程"清一格字形"的唯一写法（先前 Screen 与 LayeredScreen 各写了一份）
    void clear_glyph() {
        ch = U' ';
        cols = 1;
    }
};

/// 字符网格：游戏画面的逻辑抽象，与渲染完全解耦。
/// 渲染器只是网格的消费者之一（headless 下文本导出是唯一消费者）。
class Screen {
public:
    Screen() = default;
    Screen(int w, int h);

    /// 同一格里最多叠几笔（含 `ch` 那一笔）。
    ///
    /// 它是"一格叠几笔"的预算，**不是图层系统**：图层解决"谁压在谁上面"，
    /// 笔迹解决"同一格里怎么共存"。满了以后（两种情况都留一次日志，不静默）：
    ///   * `blend`（追加一笔）= **拒绝新的一笔**：已画上的内容只增不减；
    ///   * 层合成要压入新的一笔（`prepend_ink`）= 丢弃**最深**的一笔，
    ///     否则新内容根本画不出来（新的一笔是表层，不能丢）。
    static constexpr int kMaxInks = 3;

    /// 叠在同一格上的一笔（`ch` 之外的字形）
    struct Ink {
        char32_t ch = U' ';
        Color fg = Color::white;
    };

    int width() const { return w_; }
    int height() const { return h_; }

    /// 重建网格尺寸（切换游戏机主题时按皮肤几何调整）
    void resize(int w, int h);

    // 越界写入静默裁剪——卡带/调用方不必做边缘防御
    /// 写一个字符（全角字符额外占用右邻格作为续格）。
    /// `bg.keep` = 保留该格原有底色，**在这里落地**：print / fill 与各层包装最终都走 put，
    /// "透明底"因此只有一个解析点。
    void put(int x, int y, char32_t ch, Color fg = Color::white, Color bg = Color::black);
    /// 写一行文本（UTF-8 解码后按显示宽度推进；控制字符跳过）
    void print(int x, int y, std::string_view text, Color fg = Color::white, Color bg = Color::black);
    /// 填充矩形
    void fill(int x, int y, int w, int h, char32_t ch,
              Color fg = Color::white, Color bg = Color::black);

    /// 读某格；越界返回空白格（不抛异常，便于渲染循环直接遍历）
    const Cell& at(int x, int y) const;

    /// 追加一笔**叠画**：不清掉这一格已有的内容，只在它上面再画一笔。
    /// 与 `put` 的分工是刻意的：`put` 是"这一格改成这个字"（替换，清空笔迹），
    /// `blend` 是"再画一笔"（叠加）。**新的一笔在最前面**，原先那一笔退进笔迹表 ——
    /// 渲染按"先深后浅"逐笔混合，同格两笔因此各自留下自己的笔画。
    /// 返回 false = 这一格已满（kMaxInks）、字形不是半角、或坐标越界
    bool blend(int x, int y, char32_t ch, Color fg);

    /// 这一格的**额外笔迹**（按追加顺序，`ch` 不在其中——它是最前面那一笔）。
    /// 绝大多数格是空的：不叠笔的卡带因此不产生任何额外存储与开销
    const std::vector<Ink>& inks(int x, int y) const;

    /// 只改底色的存在性与颜色，**不动字形、也不动笔迹**。
    /// "背景比字形宽一格"就是在这个格上再 back 一次：底色铺过去，字还在原处
    void back(int x, int y, Color bg);

    /// 子位掩码 → 象限字形。位序是**引擎契约**：1 左上、2 右上、4 左下、8 右下
    /// （0 = 空、15 = 整格）。卡带不必自带这张表 —— 地形、降水、子格绘制共用一份
    static char32_t quadrant_glyph(uint8_t bits);

    /// 子格坐标 → 格坐标 + 子位。**这一步换算是引擎契约**：格 g 覆盖子格 2g 与 2g+1，
    /// 位序 1 左上 / 2 右上 / 4 左下 / 8 右下。卡带的相机、降水、光柱都该用这一份 ——
    /// 各处自己写 `floor(u/2)` 的话，同一屏会长出两套网格，差半格就是"看着陷进墙里"
    struct SubCell {
        int x = 0;        ///< 格坐标
        int y = 0;        ///< 格坐标
        uint8_t bit = 0;  ///< 该子格在这一格里的位
    };
    static SubCell cell_of(int x2, int y2);

    /// 在某个**子位**上落一笔：坐标是**本网格的子格坐标**（一格 = 2x2 子格）。
    /// 同一格的多次 plot 按位**合并**成一个象限字形，而不是互相盖掉 ——
    /// 半格精度是引擎能力，卡带不必自己拼字符。位序只在本文件推导一处。
    /// 它只改字形槽：底色与已叠的笔迹（blend 追加的那些）都不动
    void plot(int x2, int y2, Color fg);

    /// 让这一格的**子位累积**作废（字形被别人改写时用：累积记的是"这一格的哪几个
    /// 子位已经有笔"，字形换了，这份记账就不再成立）
    void forget_plot_bits(int x, int y);

    /// 整格搬运：把一格已成形的状态（含 cols 与 alpha、以及它的笔迹）原样放到 (x, y)。
    /// 与 `put` 的分工是明确的——`put` 面向"写一个字符"（解析 keep、维护宽字符邻格），
    /// 这个面向"搬运一格"（层合成）。卡带侧写画面请继续用 put / print / fill
    void set(int x, int y, const Cell& cell);

    /// 追加一笔到这一格（供层合成用：把下层原有的字形压到新字形之后）
    void prepend_ink(int x, int y, char32_t ch, Color fg);

    /// 整屏清成**透明格**（空格 + alpha=0）：图层缓冲"这一帧从空开始"的写法。
    /// 底层网格不用它——底层的清屏永远不透明（见 fill / clear）
    void clear_transparent();

    /// 空白格：所有"越界读"共用同一个值，调用方不必各自造一个空对象
    static const Cell& empty();

    /// 导出为纯文本（agent 接口第一期：画面即可读文本）。
    /// 全角字符原样按 UTF-8 导出，续格不产出字符：终端里它的显示宽度仍是两格，
    /// 而"中文"这样的词在文本里保持相邻（便于阅读与断言匹配）。
    std::string to_text() const;

    /// 某格"有内容"的字符：续格报头格字符、空格算内容、控制字符与越界返回 0。
    /// 文本导出与 `phos.screen.get` 共用这一份判断——各写一套就会让 agent
    /// 读到的画面与 dump 出来的文本对不上。
    char32_t glyph_at(int x, int y) const;

private:
    /// 线性下标：全工程"格 (x, y) → cells_ 下标"的唯一换算，笔迹表与子位表也共用它。
    /// 各处自己写 `y * w_ + x` 时漏一个 `w_` 就会静默写错格，收成一处就没有这种可能
    int index_of(int x, int y) const { return y * w_ + x; }

    /// 笔迹的存放处：只有"叠过笔"的格才在表里（键为 index_of）。
    /// 不放进 Cell 是刻意的：Cell 满屏一格一份，塞一个定长数组进去，会让每张卡带、
    /// 每一帧都为"可能用不到的多笔"付内存与拷贝代价
    std::unordered_map<int, std::vector<Ink>> inks_;
    std::vector<Ink>* inks_at(int x, int y);

    /// 按**子位掩码**落笔（plot 的里子：位序在这里定，也只在这里定）
    void plot_bit(int x, int y, uint8_t bit, Color fg);

    /// 子位累积：`plot` 要知道这一格"已经占了哪几个子位"，两次半笔才能合成一个象限字形。
    /// 与笔迹表同一套稀疏策略：只有 plot 过的格才在表里
    std::unordered_map<int, uint8_t> plot_bits_;

    /// 叠画上限的日志只报一次：满了是密处的常态，逐条写会把日志冲成噪声
    bool warned_ink_cap_ = false;

    // 默认构造后是"0x0 空网格"：读尺寸的调用方拿到的是确定的 0，而不是未初始化的值
    int w_ = 0, h_ = 0;
    std::vector<Cell> cells_;
};

} // namespace phos

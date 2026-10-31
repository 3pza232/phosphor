#pragma once

#include "core/color.hpp"
#include "core/screen_store.hpp"

#include <cstdint>
#include <string>
#include <string_view>

namespace phos {

/// 字符网格：游戏画面的逻辑抽象，与渲染完全解耦。
/// 渲染器只是网格的消费者之一（headless 下文本导出是唯一消费者）。
///
/// 写入/替换方法（put/print/fill/blend/back/plot/set/prepend_ink/…）的实现已下沉到
/// core/screen_draw.cpp（Writer 依赖 core/screen_store.hpp）；存储本身是 ScreenStore，
/// 本类只保留公开 API、一行转发与读取/几何查询。
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
    static constexpr int kMaxInks = ScreenStore::kMaxInks;

    /// 单格缩放上限：`scale` 就是这个范围里的整数（1 = 常规，2/3 = 更大字号）
    static constexpr int kMaxCellScale = ScreenStore::kMaxCellScale;

    /// 叠在同一格上的一笔（ch 之外的字形）；物理定义在 ScreenStore 的存储单元里
    using Ink = phos::Ink;

    int width() const { return store_.width(); }
    int height() const { return store_.height(); }

    /// 重建网格尺寸（切换游戏机主题时按皮肤几何调整）
    void resize(int w, int h);

    // 越界写入静默裁剪——卡带/调用方不必做边缘防御
    /// 写一个字符（全角字符额外占用右邻格作为续格）。`scale >= 2` 时写成**缩放块**
    /// （占 `cols*scale` 列 × `scale` 行，块内其余格标记为被覆盖），于是同屏可有不同字号。
    /// 默认底色 `kKeepBg` = **保留该格原有底色**（透明），"透明底"因此只有一个解析点。
    /// 要铺一块实底（机身、面板）就显式传背景色
    void put(int x, int y, char32_t ch, Color fg = Color::white, Color bg = kKeepBg,
             uint8_t scale = 1);
    /// 写一行文本（UTF-8 解码后按显示宽度推进；控制字符跳过）。底色默认保留
    void print(int x, int y, std::string_view text, Color fg = Color::white, Color bg = kKeepBg,
               uint8_t scale = 1);
    /// 填充矩形。底色默认保留；要实底就显式传背景色
    void fill(int x, int y, int w, int h, char32_t ch,
              Color fg = Color::white, Color bg = kKeepBg);

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
    using SubCell = ScreenStore::SubCell;
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
    /// 实现已下沉到 core/screen_text.hpp（Screen 只保留这一行转发）；
    /// 续格/缩放/控制字符的导出规则见那里的契约注释。
    std::string to_text() const;

    /// 某格"有内容"的字符：续格报头格字符、空格算内容、控制字符与越界返回 0。
    /// 文本导出与 `phos.screen.get` 共用这一份判断——各写一套就会让 agent
    /// 读到的画面与 dump 出来的文本对不上。
    char32_t glyph_at(int x, int y) const;

    /// (x,y) 是否落在某个**缩放块**里（含头格自身）。层合成后的"大字归一"靠它判定
    /// 一个被覆盖格是不是还有头格罩着
    bool covered_by_scaled_block(int x, int y) const;

private:
    /// 存储（格 / 笔迹 / 子位表）的唯一持有者；写入语义是它的 friend Writer
    ScreenStore store_;
};

} // namespace phos

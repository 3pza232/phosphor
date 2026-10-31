#pragma once

#include "core/color.hpp"

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace phos {

namespace screen_draw {
struct Writer;
}

/// 屏幕一格。ch 为 Unicode 码点。
///
/// 全角字符（CJK 等）占两格：左格是"头"（cols = 2），右格是"续格"
/// （cols = 0，自身没有字形，绘制时跳过）。这样"格"仍然是等宽单位，
/// 渲染与对齐只需认 cols，不必满屏推断宽度。
///
/// 缩放（scale）与 cols **正交**：cols 管横向续格（宽字），scale 管"更大的字"
/// 成块覆盖（scale=S>=2 的头格占 cols*S 列 × S 行，块内其余格 scale = 0 被覆盖）。
/// 于是同一屏可以并存不同大小的字：scale = 1 是常规正文，scale >= 2 是大标题
struct Cell {
    char32_t ch = U' ';
    Color fg = Color::white;
    Color bg = Color::black;
    /// 列宽：1 = 半角；2 = 全角头格；0 = 续格（右半，由左邻格决定外观）
    uint8_t cols = 1;
    /// 缩放：1 = 普通；S>=2 = 缩放块头格；0 = 被缩放块覆盖（自身无字形，绘制时跳过）
    uint8_t scale = 1;
    /// 底色是否存在：0 = 透明（层合成时跳过底色），非 0 = 存在。
    /// 底层网格的默认 alpha 是 255（不透明）；层缓冲的清屏把它置 0。
    /// 注意：put 的默认底色是 kKeepBg（保留原底色），所以"不动背景"是默认行为
    uint8_t alpha = 255;

    /// 抹掉这一格的字形，**保留底色与存在性**。宽字被截断、层用空格抹掉下层字形时用；
    /// 是全工程"清一格字形"的唯一写法——新调用点必须走它，不要内联改 ch/cols
    void clear_glyph() {
        ch = U' ';
        cols = 1;
        scale = 1;
    }
};

/// 叠在同一格上的一笔（ch 之外的字形）
struct Ink {
    char32_t ch = U' ';
    Color fg = Color::white;
};

/// Screen 的存储：字符网格 + 稀疏笔迹表 + 稀疏子位表。
///
/// 这是 core 内部单元（Screen 持有它）；公开方法只提供 Screen 已经公开的只读视图
/// （at/inks/covered_by_scaled_block）与 resize，**不暴露可变的 Cell& 或表迭代器**。
/// 写入语义在 screen_draw::Writer（唯一 friend），由 Screen 的方法一行转发。
class ScreenStore {
  public:
    ScreenStore() = default;
    ScreenStore(int w, int h);

    int width() const { return w_; }
    int height() const { return h_; }

    /// 重建网格尺寸（切换游戏机主题时按皮肤几何调整）
    void resize(int w, int h);

    /// 读某格；越界返回空白格（不渲染循环各自造空对象）
    const Cell& at(int x, int y) const;

    /// 这一格的额外笔迹（ch 不在其中）；越界/无笔迹返回空表
    const std::vector<Ink>& inks(int x, int y) const;

    /// (x,y) 是否落在某个缩放块里（含头格自身）
    bool covered_by_scaled_block(int x, int y) const;

    /// 空白格：所有"越界读"共用同一个值
    static const Cell& empty();

    /// 同一格里最多叠几笔（含 ch 那一笔）；写入语义（screen_draw）的预算
    static constexpr int kMaxInks = 3;
    /// 单格缩放上限（1 = 常规，2/3 = 更大字号）
    static constexpr int kMaxCellScale = 3;

    /// 子格坐标 → 格坐标 + 子位（位序 1 左上 / 2 右上 / 4 左下 / 8 右下）
    struct SubCell {
        int x = 0;
        int y = 0;
        uint8_t bit = 0;
    };
    static SubCell cell_of(int x2, int y2);
    /// 子位掩码 → 象限字形（0 = 空、15 = 整格）
    static char32_t quadrant_glyph(uint8_t bits);

  private:
    /// 写入语义的唯一 friend：screen_draw::Writer（实现在 screen_draw.cpp）
    friend struct screen_draw::Writer;

    /// 线性下标：格 (x,y) → cells_ 下标的唯一换算
    int index_of(int x, int y) const { return y * w_ + x; }

    /// 笔迹表：只有叠过笔的格才在表里（键为 index_of）
    std::vector<Ink>* inks_at(int x, int y);
    std::unordered_map<int, std::vector<Ink>> inks_;

    /// 覆盖 (x,y) 的缩放块头格坐标；不在任何缩放块里返回 false
    bool scaled_block_of(int x, int y, int& head_x, int& head_y) const;

    /// 子位累积：只有 plot 过的格才在表里
    std::unordered_map<int, uint8_t> plot_bits_;

    /// 叠画上限/无字形槽的日志只报一次（每个 Screen 一份，与拆前一致）
    bool warned_ink_cap_ = false;
    bool warned_blend_slot_ = false;

    int w_ = 0, h_ = 0;
    std::vector<Cell> cells_;
};

} // namespace phos

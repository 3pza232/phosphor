#pragma once

#include "core/screen.hpp"

#include <string_view>

namespace phos::screen_draw {

/// Screen 的写入/替换语义（put/print/fill/blend/back/plot/set/prepend_ink/…）。
///
/// 为什么在 Screen 之外：这些方法的实现全都在操作 Screen 的私有存储（cells_、
/// inks_、plot_bits_）与宽字/缩放块的邻格维护；把它们挪出去后，Screen 只保留
/// 存储、读取与几何查询，写入语义的演进（S7 后续）不再挤压 Screen 类。
///
/// 暴露面刻意收窄：
///   - 头文件里只有函数签名，没有布局/存储访问器；
///   - 实现里的 Writer 是 Screen 的唯一 friend（见 screen.hpp），只在 .cpp 中定义；
///   - 外部仍调 Screen::put(...) 等方法，默认值/错误行为不变。
struct Writer {
    static void put(Screen& screen, int x, int y, char32_t ch, Color fg, Color bg,
                    uint8_t scale = 1);
    static void print(Screen& screen, int x, int y, std::string_view text, Color fg, Color bg,
                      uint8_t scale);
    static void fill(Screen& screen, int x, int y, int w, int h, char32_t ch, Color fg, Color bg);
    static bool blend(Screen& screen, int x, int y, char32_t ch, Color fg);
    static void back(Screen& screen, int x, int y, Color bg);
    static void plot(Screen& screen, int x2, int y2, Color fg);
    static void forget_plot_bits(Screen& screen, int x, int y);
    static void prepend_ink(Screen& screen, int x, int y, char32_t ch, Color fg);
    static void set(Screen& screen, int x, int y, const Cell& cell);
    static void clear_transparent(Screen& screen);

  private:
    /// put 的写前清理：把 (x,y) 覆盖的旧缩放块整块清成空格（连带笔迹/子位）
    static void clear_scaled_block_at(Screen& screen, int x, int y, Color fg, Color bg,
                                      bool keeps_bg);
    /// plot 的里子：按子位掩码落半笔（位序只由 Screen::cell_of 决定）
    static void plot_bit(Screen& screen, int x, int y, uint8_t bit, Color fg);
};

} // namespace phos::screen_draw

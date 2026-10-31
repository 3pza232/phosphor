#pragma once

#include "core/screen_store.hpp"

#include <string_view>

namespace phos::screen_draw {

/// Screen 的写入/替换语义（put/print/fill/blend/back/plot/set/prepend_ink/…）。
///
/// 依赖面：只依赖 ScreenStore（格 / 笔迹 / 子位表的窄接口 + 唯一 friend），
/// 不再依赖 Screen 类；Screen 的方法只做一行转发。这样存储、写入、读取/导出三块
/// 可以各自演进（S7 后续：存储布局变化只动 screen_store）。
///
/// 暴露面刻意收窄：
///   - 头文件里只有函数签名，没有存储访问器；
///   - Writer 是 ScreenStore 的唯一 friend，只在 .cpp 中定义；
///   - 外部仍调 Screen::put(...) 等方法，默认值/错误行为不变。
struct Writer {
    static void put(ScreenStore& store, int x, int y, char32_t ch, Color fg, Color bg,
                    uint8_t scale = 1);
    static void print(ScreenStore& store, int x, int y, std::string_view text, Color fg, Color bg,
                      uint8_t scale);
    static void fill(ScreenStore& store, int x, int y, int w, int h, char32_t ch, Color fg,
                     Color bg);
    static bool blend(ScreenStore& store, int x, int y, char32_t ch, Color fg);
    static void back(ScreenStore& store, int x, int y, Color bg);
    static void plot(ScreenStore& store, int x2, int y2, Color fg);
    static void forget_plot_bits(ScreenStore& store, int x, int y);
    static void prepend_ink(ScreenStore& store, int x, int y, char32_t ch, Color fg);
    static void set(ScreenStore& store, int x, int y, const Cell& cell);
    static void clear_transparent(ScreenStore& store);

  private:
    /// put 的写前清理：把 (x,y) 覆盖的旧缩放块整块清成空格（连带笔迹/子位）
    static void clear_scaled_block_at(ScreenStore& store, int x, int y, Color fg, Color bg,
                                      bool keeps_bg);
    /// plot 的里子：按子位掩码落半笔（位序只由 ScreenStore::cell_of 决定）
    static void plot_bit(ScreenStore& store, int x, int y, uint8_t bit, Color fg);
};

} // namespace phos::screen_draw

#pragma once

#include "core/color.hpp"

#include <cstdint>
#include <string>
#include <string_view>
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
};

/// 字符网格：游戏画面的逻辑抽象，与渲染完全解耦。
/// 渲染器只是网格的消费者之一（headless 下文本导出是唯一消费者）。
class Screen {
public:
    Screen() = default;
    Screen(int w, int h);

    int width() const { return w_; }
    int height() const { return h_; }

    /// 重建网格尺寸（切换游戏机主题时按皮肤几何调整）
    void resize(int w, int h);

    // 越界写入静默裁剪——卡带/调用方不必做边缘防御
    /// 写一个字符（全角字符额外占用右邻格作为续格）
    void put(int x, int y, char32_t ch, Color fg = Color::white, Color bg = Color::black);
    /// 写一行文本（UTF-8 解码后按显示宽度推进；控制字符跳过）
    void print(int x, int y, std::string_view text, Color fg = Color::white, Color bg = Color::black);
    /// 填充矩形
    void fill(int x, int y, int w, int h, char32_t ch,
              Color fg = Color::white, Color bg = Color::black);
    /// 清屏（可选底色）
    void clear(Color fg = Color::white, Color bg = Color::black);

    /// 只改前景、**保留该格原有背景**（"不清底"）。
    /// 卡带没显式给 bg 时走这几条：否则每个字都自带黑底，
    /// 压在天空或地形上就是一块块黑斑（地形用象限字形，一格里有空有实，
    /// 黑底会让坡面边缘出现黑边）。显式给了 bg 的调用方（外壳、界面）不受影响。
    void put_fg(int x, int y, char32_t ch, Color fg) { put(x, y, ch, fg, at(x, y).bg); }
    void print_fg(int x, int y, std::string_view text, Color fg) {
        print(x, y, text, fg, at(x, y).bg);
    }
    void fill_fg(int x, int y, int w, int h, char32_t ch, Color fg) {
        fill(x, y, w, h, ch, fg, at(x, y).bg);
    }

    /// 读某格；越界返回静态空 Cell（不抛异常，便于渲染循环直接遍历）
    const Cell& at(int x, int y) const;

    /// 导出为纯文本（agent 接口第一期：画面即可读文本）。
    /// 全角字符原样按 UTF-8 导出，续格不产出字符：终端里它的显示宽度仍是两格，
    /// 而"中文"这样的词在文本里保持相邻（便于阅读与断言匹配）。
    std::string to_text() const;

    /// 某格"有内容"的字符：宽字符的续格报它的头格字符（问哪一格都答得出）；
    /// 空格是内容（原样返回 ' '），只有控制字符与越界格返回 0。
    /// 文本导出（`to_text`）与 `phos.screen.get` 都走这一份判断：两处若各写一套
    /// "续格算不算内容、控制字符怎么办"，改一处忘一处就会让 agent 读到的画面
    /// 与 dump 出来的文本对不上。
    char32_t glyph_at(int x, int y) const;

private:
    int w_, h_;
    std::vector<Cell> cells_;
    Cell out_of_bounds_{};
};

} // namespace phos

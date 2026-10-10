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
    // 默认构造后是"0x0 空网格"：读尺寸的调用方拿到的是确定的 0，而不是未初始化的值
    int w_ = 0, h_ = 0;
    std::vector<Cell> cells_;
};

} // namespace phos

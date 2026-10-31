#include "shell/boot_view.hpp"

#include "core/text.hpp"
#include "core/version.hpp"

#include <string>
#include <vector>

namespace phos::boot {

namespace {

// 自检屏的版面：起点与行距集中在这里（旧实现把它们散在绘制循环里）。
// 逐行打出与行尾光标闪烁是**动画特效**，不组件化——组件描述的是静态布局，
// 而这里的每一帧都依赖动画时钟。
constexpr int kStartX = 24;   // 首列（相对内容区左缘）
constexpr int kStartY = 12;   // 首行（相对内容区顶）
constexpr int kLineStep = 2;  // 相邻两行的行距
constexpr int kCaretBlinkRate = 5;  // 光标每秒闪几次

} // namespace

void draw(Screen& screen, const BootContext& ctx, const ui::Style& style) {
    ui::fill(screen, ctx.content, U' ', style.fg, style.bg);

    // 版本取自主机单一来源；文案按界面语言从文案表取（见 shell/messages.hpp）
    const std::vector<std::string> lines = {
        std::string(kProductName) + " v" + kVersion,
        "",
        tr(ctx.lang, Msg::boot_memory),
        tr(ctx.lang, Msg::boot_display),
        tr(ctx.lang, Msg::boot_shell),
        tr(ctx.lang, Msg::boot_tube),
        "",
        tr(ctx.lang, Msg::boot_waiting),
    };
    const int visible = static_cast<int>(ctx.elapsed / ctx.interval) + 1;
    const int x = ctx.content.x + kStartX;
    int y = ctx.content.y + kStartY;
    for (size_t i = 0; i < lines.size() && static_cast<int>(i) < visible; ++i, y += kLineStep) {
        ui::print(screen, x, y, lines[i], style.accent, style.bg);
        const bool caret = static_cast<int>(i) == visible - 1 && !lines[i].empty();
        if (caret && static_cast<int>(ctx.elapsed * kCaretBlinkRate) % 2 == 0)  // 光标闪烁
            // 光标按**显示宽度**跟随（中文一字占 2 列，按字节数会偏出去一截）
            screen.put(x + text::display_width(lines[i]) + 1, y, U'|', style.fg, style.bg);
    }
}

} // namespace phos::boot

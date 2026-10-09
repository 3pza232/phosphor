#include "shell/boot_view.hpp"

#include "core/text.hpp"
#include "core/version.hpp"

#include <string>
#include <vector>

namespace phos::boot {

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
    int y = ctx.content.y + 12;
    for (size_t i = 0; i < lines.size() && static_cast<int>(i) < visible; ++i, y += 2) {
        ui::print(screen, ctx.content.x + 24, y, lines[i], style.accent, style.bg);
        const bool caret = static_cast<int>(i) == visible - 1 && !lines[i].empty();
        if (caret && static_cast<int>(ctx.elapsed * 5) % 2 == 0)  // 光标闪烁
            // 光标按**显示宽度**跟随（中文一字占 2 列，按字节数会偏出去一截）
            screen.put(ctx.content.x + 24 + text::display_width(lines[i]) + 1, y, U'|', style.fg,
                       style.bg);
    }
}

} // namespace phos::boot

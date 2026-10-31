#include "app/shelf_playback.hpp"

#include "api/host_api.hpp"

#include <memory>
#include <utility>

namespace phos {

void ShelfPlayback::reset() {
    script_.reset();
    time_ = 0.0f;
}

bool ShelfPlayback::load(const std::string& dir, HostContext& host, std::string& error) {
    auto script = std::make_unique<Cartridge>();
    if (!script->load_shelf(dir, host)) {
        error = script->error();
        return false;
    }
    script_ = std::move(script);
    time_ = 0.0f;
    return true;
}

bool ShelfPlayback::tick(float dt, std::string& error) {
    time_ += dt;  // 与旧行为一致：时钟先走，脚本这一步失败也不回拨
    if (!script_ || script_->update(dt)) return true;
    error = script_->error();
    return false;
}

bool ShelfPlayback::draw(Screen& screen, const ui::Rect& content, const ShelfView& view,
                         const ui::Style& style, Color panel, std::string& error) {
    if (!script_) return false;  // 无脚本：由 App 走内置样式（本类不拥有回退方案）

    // 把架子状态翻成只读 ctx：颜色取自卡带架所用的 ui::Style + 主题面板色，
    // 内容包照搬上色，引擎不替内容定色
    ShelfDrawContext ctx;
    ctx.carts = view.carts;
    ctx.cursor = view.cursor;
    ctx.content_x = content.x;
    ctx.content_y = content.y;
    ctx.content_w = content.w;
    ctx.content_h = content.h;
    ctx.english = view.lang == Lang::en;
    ctx.fg = style.fg;
    ctx.accent = style.accent;
    ctx.frame = style.frame;
    ctx.dim = style.dim;
    ctx.bg = style.bg;
    ctx.panel = panel;
    ctx.time = time_;

    if (script_->shelf_draw(ctx)) return true;
    error = script_->error();
    return false;
}

} // namespace phos

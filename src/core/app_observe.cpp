#include "core/app.hpp"

#include "core/log.hpp"
#include "core/version.hpp"
#include "render/font.hpp"
#include "render/screen_image.hpp"

#include <cstdio>

namespace phos {

std::string App::mode_name() const {
    if (in_boot_) return "BOOT";
    if (playing_) return "PLAYING";
    switch (shell_.mode()) {
        case ShellMode::boot: return "BOOT";
        case ShellMode::shelf: return "SHELF";
        case ShellMode::settings: return "SETTINGS";
        case ShellMode::paused: return "PAUSED";
        case ShellMode::tape: return "TAPE";
        case ShellMode::cart_error: return "CART_ERROR";
    }
    return "UNKNOWN";
}


void App::fill_debug_info(DebugInfo& info) {
    info.fps = fps_;
    info.frame_ms = fps_ > 0.0f ? 1000.0f / fps_ : 0.0f;
    info.frame = frame_count_;
    info.logic_hz = kLogicFps;
    info.mode = mode_name();
    info.playing = playing_;
    info.host_time = host_.time;
    info.grid_w = display_.screen.width();
    info.grid_h = display_.screen.height();
    info.content_w = kContentW;
    info.content_h = kContentH;
    info.panel_w = host_.panel_w;
    info.rng_seed = rng_seed_;
    info.update_ms = timing_.update_ms;
    info.draw_ms = timing_.draw_ms;

    if (cart_) {
        info.cart_id = cart_->info().id;
        info.cart_name = cart_->info().name;
        info.cart_version = cart_->info().version;
        info.cart_author = cart_->info().author;
        info.lua_mem_kb = cart_->lua_memory_kb();
    }
    info.cart_error = last_error_;

    info.skin_name = packs_.skin().name;
    info.boot_name = packs_.boots.empty()
                         ? "(built-in)"
                         : packs_.boots[static_cast<size_t>(packs_.boot_index)].name;
    info.shelf_style = shell_.shelf_style() == ShelfStyle::list ? "list" : "window";
    info.crt_level_name = crt_level_name(config_.crt_level);
    info.music_volume = shell_.music_volume();
    info.sfx_volume = shell_.sfx_volume();

    info.crt = &active_crt_;  // 仪表盘可直接调参，所以给的是可写指针

    // 键名表是动态的（卡带想用什么键就是什么键），所以这里遍历"见过的键名"，
    // 而不是某张写死在主机里的固定表
    for (const auto& name : input_.names()) {
        if (input_.down(name)) info.held_keys.push_back(name);
        if (input_.pressed(name))
            info.edge_keys.push_back(name + "+");
        else if (input_.released(name))
            info.edge_keys.push_back(name + "-");
    }
}


std::string App::window_title_for_state() const {
    if (control_port_ <= 0) return kProductName;
    return std::string(kProductName) + " - agent :" + std::to_string(control_port_) +
           (control_time_driven() ? " [stepping]" : " [live]");
}


void App::maybe_dump(const CliOptions& opts, long frame) const {
    if (opts.dump_every > 0 && frame % opts.dump_every == 0)
        std::printf("----- frame %ld -----\n%s", frame, display_.screen.to_text().c_str());
}


bool App::write_screenshot(const std::string& path, int& width, int& height,
                           std::string& error) const {
    ScreenImageOptions options;
    options.cell_w = kCellPx;
    options.cell_h = kCellPx;
    options.crt = active_crt_;
    // 截图必须与窗口所见一致：底 + 逐层叠画（像素级合成），
    // 而不是合成后的文本网格 —— 那条路一格只有一个字形，会把下层"顶掉"
    const bool layered = playing_ && host_.layers.active();
    const Screen& base = layered ? display_.base : display_.screen;
    // 有图层的卡带，分隔线只在 chrome 里（base 快照在写分隔线之前），截图要补上才与窗口一致
    const Screen* overlay = (layered && host_.panel_w > 0) ? &display_.chrome : nullptr;
    const auto image = render_screen_image(base, font_files_, options, error,
                                           layered ? &host_.layers : nullptr,
                                           host_.content_x, host_.content_y, overlay);
    if (!image) return false;
    if (!write_png(*image, path, error)) return false;
    width = image->width;
    height = image->height;
    return true;
}


void App::write_final_outputs(const CliOptions& opts) const {
    if (opts.dump_screen)
        std::printf("%s", display_.screen.to_text().c_str());

    if (!opts.screenshot) return;
    int width = 0, height = 0;
    std::string error;
    if (write_screenshot(*opts.screenshot, width, height, error))
        std::fprintf(stderr, "screenshot: %s (%dx%d)\n", opts.screenshot->c_str(), width, height);
    else
        std::fprintf(stderr, "WARN: screenshot failed: %s\n", error.c_str());
}


} // namespace phos

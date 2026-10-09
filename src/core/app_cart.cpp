#include "core/app.hpp"

#include "agent/json_lite.hpp"
#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/renderer.hpp"

#include <cstdio>

namespace phos {

void App::load_cart_path(const std::string& path) {
    if (path.empty()) return;

    audio_.stop_music();  // 上一张卡带的音乐到此为止
    cart_ = std::make_unique<Cartridge>();
    host_.time = 0.0;
    input_.release_all();
    pending_releases_.clear();

    if (!cart_->load(path, host_)) {
        last_error_ = cart_->error();
        cart_.reset();
        cart_path_.clear();
        shell_.show_error(last_error_);
        play_event("error");
        log_cart_error("load failed: " + last_error_);
        control_.send_event("cart.error", "\"message\":" + json::quote(last_error_));
        return;
    }

    cart_path_ = path;
    // 面板宽度由 Cartridge 在跑脚本之前设好（那里才是 manifest 已知的地方）
    playing_ = true;
    in_boot_ = false;
    insert_flash_ = kInsertFlashTime;  // 插卡瞬间的电压闪烁（时长与闪烁共同构成仪式感）
    play_event("insert");

    const CartInfo& info = cart_->info();
    log::info("cart loaded: id=" + info.id + " name=" + info.name + " version=" + info.version +
              " sidebar_w=" + std::to_string(cart_->sidebar_width()) + " path=" + cart_path_);
    control_.send_event("cart.loaded", "\"id\":" + json::quote(info.id) +
                                            ",\"path\":" + json::quote(cart_path_));
}


void App::eject_cart() {
    if (cart_) {
        eject_collapse_ = kEjectCollapseTime;  // 拔卡仪式：画面收缩熄灭
        audio_.set_paused(false);              // 保证拔卡音能听到
        audio_.stop_music();
        play_event("eject");
        log::info("cart ejected");
        control_.send_event("cart.ejected", "");
    }
    cart_.reset();
    cart_path_.clear();
    playing_ = false;
    host_.panel_w = 0;
    host_.save = nullptr;
    host_.cart_files = nullptr;
    host_.cart_info = nullptr;
    shell_.set_lamps_solid(false);
    input_.release_all();
    pending_releases_.clear();
}


} // namespace phos

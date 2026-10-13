#include "core/app.hpp"

#include "core/json_lite.hpp"
#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/renderer.hpp"

#include <cstdio>

namespace phos {

void App::load_cart_path(const std::string& path) {
    if (path.empty()) return;

    audio_.stop_music();  // 上一张卡带的音乐到此为止
    net_.stop();          // 联机随卡带生命周期：换卡/重载都先收线，端口不跨卡带留
    cart_ = std::make_unique<Cartridge>();
    host_.time = 0.0;
    host_.layers.reset(host_.content_w, host_.content_h);  // 层随卡带：新卡带从零开始
    chrome_.resize(host_.content_w, host_.content_h);      // 主机 chrome 铺满内容区（每帧重画）
    chrome_.clear_transparent();
    input_.release_all();
    pending_releases_.clear();
    capture_escape_ = false;    // Esc 接管随上一张卡带一起收（phos.sys.capture_escape）
    host_.rng.seed(rng_seed_);  // RNG 每张卡带从同一起始态开始：卡带间不串随机序列

    if (!cart_->load(path, host_)) {
        last_error_ = cart_->error();
        cart_.reset();
        // 保留 cart_path_：一次失败的 reload 不该让后续 cart.reload 变成"没有卡带可重载"
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
    net_.stop();  // 拔卡即离线（端口/线程随卡带一起收）
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
    capture_escape_ = false;  // Esc 接管随卡带一起收：否则拔卡后系统界面再也收不到 Esc
    host_.panel_w = 0;
    host_.save = nullptr;
    host_.cart_files = nullptr;
    host_.cart_info = nullptr;
    host_.layers.reset(host_.content_w, host_.content_h);  // 层随卡带销毁
    timing_.reset();  // 卡带逐帧耗时归零：否则拔卡后 state.query 还报着上一张的耗时
    shell_.set_lamps_solid(false);
    input_.release_all();
    pending_releases_.clear();
}


} // namespace phos

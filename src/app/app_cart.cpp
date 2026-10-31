#include "app/app.hpp"

#include "core/json_lite.hpp"
#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/renderer.hpp"

#include <cstdio>

namespace phos {

void App::load_cart_path(const std::string& path) {
    if (path.empty()) return;

    host_.scenes = nullptr;
    toasts_.clear();  // 旧卡带的场景栈马上要被销毁
    // 界面状态随卡带：换卡/重载不把上一张的焦点、滚动、输入缓冲带进来
    host_.cart_ui.screens.clear();
    host_.cart_ui_json.clear();
    host_.last_ui_focus.clear();
    host_.pending_ui_focus.clear();
    host_.pending_ui_activate.clear();
    audio_.stop_music();  // 上一张卡带的音乐到此为止
    net_.stop();          // 联机随卡带生命周期：换卡/重载都先收线，端口不跨卡带留
    cart_ = std::make_unique<Cartridge>();
    // 先武装会话绑定（构造=把脚本资源挂进 HostContext）：之后任何出口只要 reset 绑定，
    // 脚本态就由析构统一清掉，不必在每个失败/退出路径各记一次清理
    arm_script_binding(cart_.get());
    host_.time = 0.0;
    host_.layers.reset(host_.content_w, host_.content_h);  // 层随卡带：新卡带从零开始
    display_.chrome.resize(host_.content_w, host_.content_h);  // 主机 chrome 铺满内容区（每帧重画）
    display_.chrome.clear_transparent();
    input_.release_all();
    agent_.pending_releases.clear();
    capture_escape_ = false;    // Esc 接管随上一张卡带一起收（phos.sys.capture_escape）
    host_.rng.seed(rng_seed_);  // RNG 每张卡带从同一起始态开始：卡带间不串随机序列

    if (!cart_->load(path, host_)) {
        last_error_ = cart_->error();
        // 先解绑再销毁脚本：HostContext 不会出现"指向已析构卡带"的窗口
        script_binding_.reset();
        cart_.reset();
        // 退出 playing：否则"正在玩时 reload 失败"会让下一帧 tick_playing 去 cart_->update()
        // 一个空指针。加载失败就该回到错误屏、不再推进卡带。开机期间失败则保持 boot——
        // 一张坏卡带不该打断开机动画。
        // （**不清 cart_path_**：一次失败的 reload 不该让后续 cart.reload 变成"没有卡带可重载"）
        if (playing()) mode_ = Mode::shelf;
        shell_.show_error(last_error_);
        play_event("error");
        log_cart_error("load failed: " + last_error_);
        control_.send_event("cart.error", "\"message\":" + json::quote(last_error_));
        return;
    }

    cart_path_ = path;
    // 面板宽度由 Cartridge 在跑脚本之前设好（那里才是 manifest 已知的地方）
    mode_ = Mode::playing;
    insert_flash_ = kInsertFlashTime;  // 插卡瞬间的电压闪烁（时长与闪烁共同构成仪式感）
    play_event("insert");

    const CartInfo& info = cart_->info();
    log::info("cart loaded: id=" + info.id + " name=" + info.name.get(false) + " version=" + info.version +
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
    // 拔卡回到系统界面；开机期间拔卡保持 boot（不打断开机动画）
    if (playing()) mode_ = Mode::shelf;
    capture_escape_ = false;  // Esc 接管随卡带一起收：否则拔卡后系统界面再也收不到 Esc
    host_.panel_w = 0;
    clear_host_cart();  // save / cart_files / cart_info / cart 全是指向这张卡带的指针，一并清
    host_.layers.reset(host_.content_w, host_.content_h);  // 层随卡带销毁
    timing_.reset();  // 卡带逐帧耗时归零：否则拔卡后 state.query 还报着上一张的耗时
    shell_.set_lamps_solid(false);
    input_.release_all();
    agent_.pending_releases.clear();
}

void App::clear_host_cart() {
    if (script_binding_) {
        script_binding_.reset();  // RAII 路径：HostCartBinding 析构 → unbind_host_cart()
        return;
    }
    unbind_host_cart();  // 兼容路径：本次会话没有绑定对象（架子包的装配点在 app_settings）
}

void App::unbind_host_cart() {
    host_.scenes = nullptr;
    toasts_.clear();  // 场景栈随卡带销毁：任何查询都不能再落到它上面
    scene_audio_paused_ = false;
    // 界面快照与待办也是"当前卡带的"，一并清掉：否则 state.query.ui 会报上一张卡带的控件
    host_.cart_ui_json.clear();
    host_.cart_ui.screens.clear();
    host_.pending_ui_focus.clear();
    host_.pending_ui_activate.clear();
    // 这四处都指向"当前卡带（或宿主动画脚本）"。绑定析构必须走到这里，否则留下的是悬垂
    // 指针——phos.save / phos.assets / phos.cart / phos.debug 都靠它们，谁也不该读到已析构对象
    host_.save = nullptr;
    host_.cart_files = nullptr;
    host_.cart_info = nullptr;
    host_.cart = nullptr;
}

void App::arm_script_binding(Cartridge* cart) {
    if (script_binding_) return;  // 重载/换卡沿用同一会话：析构时清理由当时指向的脚本
    script_binding_ = std::make_unique<HostCartBinding>(host_, cart, [this] { unbind_host_cart(); });
}


} // namespace phos
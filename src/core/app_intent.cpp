#include "core/app.hpp"

#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/font.hpp"
#include "render/renderer.hpp"

#include <algorithm>

namespace phos {

void App::handle_escape() {
    if (console_.open) {  // 调试台优先
        console_.open = false;
        return;
    }
    if (in_boot_) {
        in_boot_ = false;
        boot_script_.reset();
        shell_.set_external_boot(false);
        shell_.to_shelf();
        return;
    }
    if (playing_) {
        playing_ = false;
        audio_.set_paused(true);  // 暂停：音乐随之冻结，恢复时原地续播
        shell_.to_paused();
        log::info("pause");
        return;
    }
    switch (shell_.mode()) {
        case ShellMode::boot:
            shell_.to_shelf();
            log::info("boot skipped -> shelf");
            break;
        case ShellMode::settings:
            shell_.to_shelf();
            log::info("settings closed -> shelf");
            break;
        case ShellMode::tape:
            shell_.to_paused();  // 磁带码界面回暂停菜单（卡带仍暂停着）
            log::info("tape closed -> paused");
            break;
        case ShellMode::cart_error:
            shell_.to_shelf();
            log::info("error screen dismissed -> shelf");
            break;
        case ShellMode::paused:
            playing_ = true;
            audio_.set_paused(false);  // 继续：音乐从冻结处续播
            log::info("resume");
            break;
        case ShellMode::shelf:
            log::info("power off");
            quit_ = true;
            break;
    }
}


void App::handle_intent(const Shell::Intent& intent, Renderer* renderer, Window* window) {
    if (intent.crt_changed) {
        config_.crt_level = shell_.crt_level();
        apply_crt(config_.crt_level, renderer);
        save_config_now();
        log::info("setting crt_level=" + std::to_string(config_.crt_level));
    }
    if (intent.filter_changed) {
        apply_filter(intent.filter_index, renderer);
        log::info("setting filter=" + active_filter_.id);
    }
    if (intent.font_changed) apply_font_scheme(intent.font_index, renderer);
    if (intent.language_changed) {
        config_.language = lang_name(shell_.language());
        host_.language = config_.language;  // 卡带下一帧就会跟着换文案
        save_config_now();
        log::info(std::string("setting language=") + config_.language);
    }
    if (intent.skin_changed) {
        apply_skin(intent.skin_index, window);
        log::info("setting skin=" + skins_[skin_index_].id);
    }
    if (intent.boot_changed) {
        apply_boot(intent.boot_index);
        log::info("setting boot=" + boots_[boot_index_].id);
    }
    if (intent.sound_changed) {
        apply_sound(intent.sound_index);
        play_event("confirm");  // 立即试听新音效包
        log::info("setting sound=" + sounds_[sound_index_].id);
    }
    if (intent.shelf_style_changed) {
        config_.shelf_style = shell_.shelf_style() == ShelfStyle::list ? "list" : "window";
        save_config_now();
        log::info("setting shelf_style=" + config_.shelf_style);
    }
    if (intent.music_volume_changed) {
        config_.music_volume = shell_.music_volume();
        audio_.set_music_volume(static_cast<float>(config_.music_volume) / 100.0f);
        save_config_now();
        log::info("setting music_volume=" + std::to_string(config_.music_volume));
    }
    if (intent.sfx_volume_changed) {
        config_.sfx_volume = shell_.sfx_volume();
        audio_.set_sfx_volume(static_cast<float>(config_.sfx_volume) / 100.0f);
        play_event("confirm");  // 立即试听音效音量
        save_config_now();
        log::info("setting sfx_volume=" + std::to_string(config_.sfx_volume));
    }
    if (intent.resume) {
        playing_ = true;
        audio_.set_paused(false);
        shell_.to_shelf();
    }
    if (intent.eject) {
        eject_cart();
        shell_.to_shelf();
    }
    if (intent.open_tape) {
        // 磁带码界面刚打开：把当前卡带的码交过去（Shell 自己拿不到存档）
        SaveStore* save = cart_ ? cart_->save() : nullptr;
        shell_.set_tape(cart_ ? cart_->info().name : std::string(),
                        save ? save->export_code() : std::string(), save != nullptr);
    }
    if (intent.tape_import) {
        SaveStore* save = cart_ ? cart_->save() : nullptr;
        if (!save) {
            shell_.set_tape_result(Shell::TapeResult::no_save);
        } else {
            const bool ok = save->import_code(intent.tape_code);
            // 卡带在 init 里读自己的存档，导入后要重新插卡才会用上新数据——如实写在状态行里
            shell_.set_tape_result(ok ? Shell::TapeResult::ok : Shell::TapeResult::invalid);
            log::info(std::string("tape import: ") + (ok ? "ok" : "rejected"));
        }
    }
    if (intent.insert_cart) load_cart(intent.cart_index);
}


} // namespace phos

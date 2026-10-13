#include "core/app.hpp"

#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/font.hpp"
#include "render/renderer.hpp"

#include <algorithm>
#include <cstdio>
#include <fstream>

namespace phos {

void App::save_config_now() {
    save_config(kConfigPath, config_);
}


void App::apply_skin(int index, Window* window, Renderer* renderer) {
    if (index < 0 || index >= static_cast<int>(packs_.skins.size())) return;
    packs_.skin_index = index;

    Skin& skin = packs_.skins[static_cast<size_t>(packs_.skin_index)];
    // 内容区尺寸统一由主机规定（皮肤只决定外壳装饰），避免切换时内容区尺寸漂移
    skin.screen_w = kContentW;
    skin.screen_h = kContentH;

    screen_.resize(skin.grid_w(), skin.grid_h());
    host_.content_x = skin.screen_x;
    host_.content_y = skin.screen_y;
    host_.content_w = kContentW;
    host_.content_h = kContentH;

    shell_.set_skin(skin);
    if (window) window->resize(skin.grid_w() * kCellPx, skin.grid_h() * kCellPx);

    // 主题自带色板：按皮肤声明的 palette 名解析出激活色板——卡带配色与 CRT 参数随主题一起变。
    // 色板随主题（skin.palette），设置里无独立项
    packs_.resolve_palette();
    active_palette_ = packs_.palette();
    host_.panel_bg = skin.panel;  // 侧栏默认底色随主题（卡带 init 里就会读到）
    apply_crt(config_.crt_level, renderer);
    if (cart_) cart_->apply_palette(active_palette_);

    config_.skin = skin.id;
    save_config_now();
}


void App::load_font_chain(const std::string& wanted) {
    const std::string font_dir = std::string(kFontDir) + "/";
    font_scheme_ = wanted;
    font_files_ = collect_font_files(font_dir + font_scheme_);

    // 方案不可用（目录被删、名字写错、里面没有字体）：退回出厂默认并告警。
    // 内容坏了不该让机器没字可用
    if (font_files_.empty() && font_scheme_ != kDefaultFontScheme) {
        log::warn("font scheme unusable, falling back to default: " + font_scheme_);
        font_scheme_ = kDefaultFontScheme;
        font_files_ = collect_font_files(font_dir + font_scheme_);
    }
    if (font_files_.empty()) log::warn("no font file in " + font_dir + font_scheme_);
}


void App::apply_font_scheme(int index, Renderer* renderer) {
    if (index < 0 || index >= static_cast<int>(font_schemes_.size())) return;
    load_font_chain(font_schemes_[static_cast<size_t>(index)]);

    // 窗口渲染的字形图集要跟着重建；截图/基线每次现读 font_files_，无需处理
    if (renderer) {
        std::string error;
        if (!renderer->reload_fonts(font_files_, error))
            log::warn("font atlas rebuild failed: " + error);
        // 墨迹度量随字体链走：换字体后回调依旧取当前字形的框
        host_.glyph_metrics = [renderer](char32_t cp) { return renderer->ink_box(cp); };
    }

    config_.font = font_scheme_;
    save_config_now();
    log::info("setting font=" + font_scheme_);
}


void App::log_cart_error(const std::string& message) {
    log::error("cart error: " + message);
}


void App::init_audio() {
    std::string error;
    if (audio_.init(error)) {
        audio_.set_music_volume(static_cast<float>(config_.music_volume) / 100.0f);
        audio_.set_sfx_volume(static_cast<float>(config_.sfx_volume) / 100.0f);
        std::fprintf(stderr, "audio: device ready\n");
        log::info("audio device ready");
    } else {
        log::warn(error + " (running silent)");
    }
}


void App::apply_crt(int level, Renderer* renderer) {
    active_crt_ = crt_params_for_level(level, active_palette_);
    if (renderer) renderer->set_crt(active_crt_);
}


void App::apply_boot(int index) {
    if (index < 0 || index >= static_cast<int>(packs_.boots.size())) return;
    packs_.boot_index = index;
    config_.boot = packs_.boots[static_cast<size_t>(packs_.boot_index)].id;
    save_config_now();
}


void App::apply_sound(int index) {
    if (index < 0 || index >= static_cast<int>(packs_.sounds.size())) return;
    packs_.sound_index = index;
    sample_cache_.clear();  // 包已切换，缓存句柄随旧包失效
    config_.sound = packs_.sounds[static_cast<size_t>(packs_.sound_index)].id;
    save_config_now();
}


int App::sample_handle_for(const std::string& event, const std::string& path) {
    const SoundPack& sound_pack = packs_.sounds[static_cast<size_t>(packs_.sound_index)];
    const std::string key = sound_pack.id + ":" + event;
    auto it = sample_cache_.find(key);
    if (it != sample_cache_.end()) return it->second;

    int handle = 0;
    if (host_.cart_files) {
        // 音效包的音频文件：按包目录读取（此处 path 相对包目录）
        if (auto bytes = [&]() -> std::optional<std::string> {
                std::ifstream in(sound_pack.dir + "/" + path, std::ios::binary);
                if (!in) return std::nullopt;
                std::ostringstream ss;
                ss << in.rdbuf();
                return ss.str();
            }()) {
            handle = audio_.load_sample(key, *bytes);
        }
    }
    sample_cache_[key] = handle;
    return handle;
}


void App::play_event(const std::string& event) {
    if (packs_.sounds.empty()) return;
    const SoundPack& pack = packs_.sounds[static_cast<size_t>(packs_.sound_index)];

    if (auto it = pack.files.find(event); it != pack.files.end()) {
        const int handle = sample_handle_for(event, it->second);
        if (handle > 0) {
            audio_.play_sample(handle, 0.9f, false);
            return;
        }
    }
    if (auto tone = pack.tones.find(event); tone != pack.tones.end())
        audio_.play_tone(tone->second);
}


} // namespace phos

#include "app/app.hpp"

#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/renderer.hpp"

#include <algorithm>
#include <cstdio>

namespace phos {

void App::save_config_now() {
    save_config(config_path_, config_);
}


void App::apply_skin(int index, Window* window, Renderer* renderer) {
    if (index < 0 || index >= static_cast<int>(packs_.skins.size())) return;
    packs_.skin_index = index;

    Skin& skin = packs_.skins[static_cast<size_t>(packs_.skin_index)];
    // 内容区尺寸统一由主机规定（皮肤只决定外壳装饰），避免切换时内容区尺寸漂移
    skin.screen_w = kContentW;
    skin.screen_h = kContentH;

    display_.screen.resize(skin.grid_w(), skin.grid_h());
    host_.content_x = skin.screen_x;
    host_.content_y = skin.screen_y;
    host_.content_w = kContentW;
    host_.content_h = kContentH;

    shell_.set_skin(skin);
    if (window) window->resize(skin.grid_w() * font_px_, skin.grid_h() * font_px_);

    // 主题自带色板：按皮肤声明的 palette 名解析出激活色板——卡带配色与 CRT 参数随主题一起变。
    // 色板随主题（skin.palette），设置里无独立项
    packs_.resolve_palette();
    active_palette_ = packs_.palette();
    host_.panel_bg = skin.panel;  // 侧栏默认底色随主题（卡带 init 里就会读到）
    apply_crt(config_.crt_level, renderer);
    if (cart()) cart()->apply_palette(active_palette_);

    config_.skin = skin.id;
    save_config_now();
}


void App::apply_font_px(Renderer* renderer, Window* window) {
    font_px_ = fonts_.effective_px(config_.font_size);
    host_.cell_px = font_px_;                       // ink_box 的兜底宽度随格边长
    if (renderer) renderer->set_cell_px(font_px_);  // 字形随格缩放
    const Skin& skin = packs_.skin();
    if (window) window->resize(skin.grid_w() * font_px_, skin.grid_h() * font_px_);
    // 设置行显示与实际生效保持同步；巡回范围也交给界面（方案声明的 min~max）
    shell_.set_font_size(font_px_, fonts_.min_px(), fonts_.max_px());
}


void App::apply_font_size(int px, Renderer* renderer, Window* window) {
    // 0 = 跟随字体方案；正数钳进**方案声明的范围**（越界不静默保留）
    config_.font_size = px <= 0 ? 0 : fonts_.clamp_px(px);
    apply_font_px(renderer, window);
    save_config_now();
}


void App::apply_font_scheme(int index, Renderer* renderer, Window* window) {
    if (index < 0 || index >= static_cast<int>(fonts_.names().size())) return;
    fonts_.load_chain(fonts_.names()[static_cast<size_t>(index)]);

    // 窗口渲染的字形图集要跟着重建；截图/基线每次现读 fonts_.files()，无需处理
    if (renderer) {
        std::string error;
        if (!renderer->reload_fonts(fonts_.files(), error))
            log::warn("font atlas rebuild failed: " + error);
        // 墨迹度量随字体链走：换字体后回调依旧取当前字形的框
        host_.glyph_metrics = [renderer](char32_t cp) { return renderer->ink_box(cp); };
    }
    // 换方案可能改变"方案声明的字号"（配置为 0=跟随时），字号与字体链一起落地
    apply_font_px(renderer, window);

    config_.font = fonts_.current();
    save_config_now();
    log::info("setting font=" + fonts_.current());
}


void App::log_cart_error(const std::string& message) {
    log::error("cart error: " + message);
}


void App::init_audio() {
    std::string error;
    if (audio_.init(error)) {
        sound_state_.apply_volumes(audio_, config_.music_volume, config_.sfx_volume);
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
    sound_state_.clear_cache();  // 包已切换，缓存句柄随旧包失效
    config_.sound = packs_.sounds[static_cast<size_t>(packs_.sound_index)].id;
    save_config_now();
}


void App::apply_shelf(int select) {
    const int count = 2 + static_cast<int>(packs_.shelves.size());
    if (select < 0 || select >= count) return;

    // 先卸下旧包脚本（连同它留下的 host 指针），并收回画家：新选择可能是内置样式，
    // 也可能加载失败——两种情况下内容区都必须能立即回退
    const bool had_script = shelf_playback_.active();
    shelf_playback_.reset();
    if (had_script) clear_host_cart();
    shell_.set_shelf_painter({});

    if (select == 0) {
        config_.shelf_style = "list";
    } else if (select == 1) {
        config_.shelf_style = "window";
    } else {
        const ShelfPack& pack = packs_.shelves[static_cast<size_t>(select - 2)];
        std::string error;
        if (shelf_playback_.load(pack.dir, host_, error)) {
            config_.shelf_style = pack.id;
            // 画家只在脚本可用时挂上：外部标记与它同步（见 Shell::shelf_view），
            // 于是"包在不在"与"内容区交给谁画"永远一致
            shell_.set_shelf_painter([this](Screen& screen, const ui::Rect& content,
                                            const ShelfView& view, const ui::Style& style) {
                draw_shelf_content(screen, content, view, style);
            });
        } else {
            // 包不可用（缺 shelf.lua / 缺 draw(ctx) / 语法错）：安静回退内置视窗样式并留痕
            log::warn("shelf pack unusable, falling back to window: " + error);
            select = 1;
            config_.shelf_style = "window";
        }
    }

    // 把包声明翻成 shell 的候选项：本地化名（缺 en 回落 zh，两者都缺回落文件夹名）+ 二维列数
    std::vector<ShelfOption> options;
    options.reserve(packs_.shelves.size());
    for (const ShelfPack& shelf : packs_.shelves) {
        ShelfOption option;
        option.zh = shelf.name_zh.empty() ? shelf.name : shelf.name_zh;
        option.en = shelf.name_en.empty() ? option.zh : shelf.name_en;
        option.cols = shelf.cols;
        options.push_back(std::move(option));
    }
    shell_.set_shelves(std::move(options), select);
    packs_.shelf_index = select >= 2 ? select - 2 : -1;
    save_config_now();
}


void App::draw_shelf_content(Screen& screen, const ui::Rect& content, const ShelfView& view,
                             const ui::Style& style) {
    if (!shelf_playback_.active()) {  // 脚本已在别处卸下：本帧直接回退内置样式
        shelf::draw_builtin(screen, content, view, style);
        return;
    }

    std::string error;
    if (shelf_playback_.draw(screen, content, view, style, packs_.skin().panel, error)) return;

    // 本帧报错：收回脚本、清画家，并**当帧**回退内置样式（不留半张脸）
    log::warn("shelf script draw failed, falling back to built-in: " + error);
    shelf_playback_.reset();
    clear_host_cart();
    shell_.set_shelf_painter({});
    shelf::draw_builtin(screen, content, view, style);
}


void App::play_event(const std::string& event) {
    // 薄转发：音效包选择、采样缓存与播放编排在 SoundState（见 app/sound_state.hpp）
    sound_state_.play_event(event, packs_, host_.cart_files, audio_);
}


} // namespace phos
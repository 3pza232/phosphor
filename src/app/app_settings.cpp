#include "app/app.hpp"

#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/renderer.hpp"

#include <algorithm>
#include <cstdio>
#include <filesystem>
#include <fstream>

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


void App::apply_shelf(int select) {
    const int count = 2 + static_cast<int>(packs_.shelves.size());
    if (select < 0 || select >= count) return;

    // 先卸下旧包脚本（连同它留下的 host 指针），并收回画家：新选择可能是内置样式，
    // 也可能加载失败——两种情况下内容区都必须能立即回退
    if (shelf_script_) {
        shelf_script_.reset();
        clear_host_cart();
    }
    shell_.set_shelf_painter({});
    shelf_time_ = 0.0f;

    if (select == 0) {
        config_.shelf_style = "list";
    } else if (select == 1) {
        config_.shelf_style = "window";
    } else {
        const ShelfPack& pack = packs_.shelves[static_cast<size_t>(select - 2)];
        auto script = std::make_unique<Cartridge>();
        if (script->load_shelf(pack.dir, host_)) {
            shelf_script_ = std::move(script);
            config_.shelf_style = pack.id;
            // 画家只在脚本可用时挂上：外部标记与它同步（见 Shell::shelf_view），
            // 于是"包在不在"与"内容区交给谁画"永远一致
            shell_.set_shelf_painter([this](Screen& screen, const ui::Rect& content,
                                            const ShelfView& view, const ui::Style& style) {
                draw_shelf_content(screen, content, view, style);
            });
        } else {
            // 包不可用（缺 shelf.lua / 缺 draw(ctx) / 语法错）：安静回退内置视窗样式并留痕
            log::warn("shelf pack unusable, falling back to window: " + script->error());
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
    if (!shelf_script_) {  // 脚本已在别处卸下：本帧直接回退内置样式
        shelf::draw_builtin(screen, content, view, style);
        return;
    }

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
    ctx.panel = packs_.skin().panel;
    ctx.time = shelf_time_;

    if (shelf_script_->shelf_draw(ctx)) return;

    // 本帧报错：收回脚本、清画家，并**当帧**回退内置样式（不留半张脸）
    log::warn("shelf script draw failed, falling back to built-in: " + shelf_script_->error());
    shelf_script_.reset();
    clear_host_cart();
    shell_.set_shelf_painter({});
    shelf::draw_builtin(screen, content, view, style);
}


int App::sample_handle_for(const std::string& event, const std::string& path) {
    const SoundPack& sound_pack = packs_.sounds[static_cast<size_t>(packs_.sound_index)];
    const std::string key = sound_pack.id + ":" + event;
    auto it = sample_cache_.find(key);
    if (it != sample_cache_.end()) return it->second;

    int handle = 0;
    if (host_.cart_files) {
        // 音效包的音频文件：按包目录读取（此处 path 相对包目录）。
        // 读之前**先看大小**：与卡带素材同一道闸，不把天量文件读进内存再交给解码器
        const std::string file = sound_pack.dir + "/" + path;
        std::error_code ec;
        const auto on_disk = std::filesystem::file_size(file, ec);
        if (!ec && on_disk <= kMaxAssetBytes) {
            std::ifstream in(file, std::ios::binary);
            if (in) {
                std::ostringstream ss;
                ss << in.rdbuf();
                handle = audio_.load_sample(key, ss.str());
            }
        }
    }
    sample_cache_[key] = handle;
    return handle;
}


namespace {

/// 主机事件音的声部优先级：错误反馈最高；确认/插拔/开机次之；按键音是氛围级。
/// 池被卡带音效压满时，至少不会把"操作失败"这种关键反馈丢掉
int host_event_priority(const std::string& event) {
    if (event == "error") return kPriorityCritical;
    if (event == "confirm" || event == "insert" || event == "eject" || event == "boot")
        return kPrioritySfx;
    return kPriorityMin;
}

} // namespace

void App::play_event(const std::string& event) {
    if (packs_.sounds.empty()) return;
    const SoundPack& pack = packs_.sounds[static_cast<size_t>(packs_.sound_index)];
    const int priority = host_event_priority(event);

    if (auto it = pack.files.find(event); it != pack.files.end()) {
        const int handle = sample_handle_for(event, it->second);
        if (handle > 0) {
            audio_.play_sample(handle, 0.9f, false, priority);
            return;
        }
    }
    if (auto tone = pack.tones.find(event); tone != pack.tones.end()) {
        ToneSpec spec = tone->second;
        if (spec.priority < priority) spec.priority = priority;
        audio_.play_tone(spec);
    }
}


} // namespace phos
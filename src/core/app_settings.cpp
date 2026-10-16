#include "core/app.hpp"

#include "core/log.hpp"
#include "platform/window.hpp"
#include "render/font.hpp"
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
    if (cart_) cart_->apply_palette(active_palette_);

    config_.skin = skin.id;
    save_config_now();
}


void App::load_font_chain(const std::string& wanted) {
    // 方案表里已含声明的回退顺序与字号；不查目录文件系统，避免"表里/盘上"两套排序
    const auto find = [this](const std::string& name) -> const FontScheme* {
        for (const FontScheme& s : font_scheme_list_)
            if (s.name == name) return &s;
        return nullptr;
    };
    const auto use = [this, &find](const std::string& name) {
        font_scheme_ = name;
        font_scheme_size_ = 0;
        font_min_px_ = kMinFontPx;
        font_max_px_ = kMaxFontPx;
        if (const FontScheme* s = find(name)) {
            font_files_ = s->files;
            font_scheme_size_ = s->size;
            font_min_px_ = s->min_size;
            font_max_px_ = s->max_size;  // 方案（或其 Mod 覆盖）声明的可调上限
        } else {
            // 方案不在表里（目录被删 / 名字写错）：现取一次，取不到再由下面兜底
            font_files_ = collect_font_files(std::string(kFontDir) + "/" + name);
        }
    };

    use(wanted);
    // 方案不可用（目录被删、名字写错、里面没有字体）：退回出厂默认并告警。内容坏了不该没字可用
    if (font_files_.empty() && font_scheme_ != kDefaultFontScheme) {
        log::warn("font scheme unusable, falling back to default: " + font_scheme_);
        use(kDefaultFontScheme);
    }
    if (font_files_.empty()) log::warn("no font file in " + std::string(kFontDir) + "/" + font_scheme_);
}


int App::effective_font_px() const {
    const auto in_range = [this](int px) {
        return px < font_min_px_ ? font_min_px_ : (px > font_max_px_ ? font_max_px_ : px);
    };
    if (config_.font_size > 0) return in_range(config_.font_size);      // 用户显式选择优先
    return font_scheme_size_ > 0 ? font_scheme_size_ : kDefaultFontPx;  // 否则方案声明，再否则出厂默认
}


void App::apply_font_px(Renderer* renderer, Window* window) {
    font_px_ = effective_font_px();
    host_.cell_px = font_px_;                       // ink_box 的兜底宽度随格边长
    if (renderer) renderer->set_cell_px(font_px_);  // 字形随格缩放
    const Skin& skin = packs_.skin();
    if (window) window->resize(skin.grid_w() * font_px_, skin.grid_h() * font_px_);
    // 设置行显示与实际生效保持同步；巡回范围也交给界面（方案声明的 min~max）
    shell_.set_font_size(font_px_, font_min_px_, font_max_px_);
}


void App::apply_font_size(int px, Renderer* renderer, Window* window) {
    // 0 = 跟随字体方案；正数钳进**方案声明的范围**（越界不静默保留）
    const auto in_range = [this](int v) {
        return v < font_min_px_ ? font_min_px_ : (v > font_max_px_ ? font_max_px_ : v);
    };
    config_.font_size = px <= 0 ? 0 : in_range(px);
    apply_font_px(renderer, window);
    save_config_now();
}


void App::apply_font_scheme(int index, Renderer* renderer, Window* window) {
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
    // 换方案可能改变"方案声明的字号"（配置为 0=跟随时），字号与字体链一起落地
    apply_font_px(renderer, window);

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

#include "core/app.hpp"

#include "cart/cart_scanner.hpp"
#include "render/font.hpp"
#include "core/effects.hpp"
#include "core/log.hpp"
#include "pack/builtin.hpp"
#include "core/version.hpp"
#include "platform/window.hpp"
#include "render/renderer.hpp"

#include <algorithm>
#include <chrono>
#include <cstdio>
#include <fstream>
#include <optional>
#include <sstream>
#include <thread>

namespace phos {

namespace {

/// 按"最近打开"重排卡带：最近的在最前，其余保持扫描顺序（stable）。
/// 用 id 匹配而不是路径——同一张卡带换个目录也认得出来；
/// 不在记录里的（新卡带）排在后面，位置由扫描顺序决定
void sort_by_recent(std::vector<CartInfo>& carts, const std::vector<std::string>& recent) {
    const auto rank = [&recent](const CartInfo& cart) {
        const auto it = std::find(recent.begin(), recent.end(), cart.id);
        return it == recent.end() ? recent.size() : static_cast<size_t>(it - recent.begin());
    };
    std::stable_sort(carts.begin(), carts.end(),
                     [&rank](const CartInfo& a, const CartInfo& b) { return rank(a) < rank(b); });
}

} // namespace

int App::run(const CliOptions& opts) {
    config_ = load_config(kConfigPath);

    filters_.push_back(raw_filter());
    merge_packs(filters_, scan_palettes(kUserFilterDir));
    merge_packs(filters_, scan_palettes(kFactoryFilterDir));
    filter_index_ = 0;
    for (size_t i = 0; i < filters_.size(); ++i)
        if (filters_[i].id == config_.filter) filter_index_ = static_cast<int>(i);
    active_filter_ = filters_[filter_index_];

    skins_ = scan_skins(kUserSkinDir);
    merge_packs(skins_, scan_skins(kFactorySkinDir));
    if (skins_.empty()) skins_.push_back(builtin_skin());
    skin_index_ = 0;
    for (size_t i = 0; i < skins_.size(); ++i)
        if (skins_[i].id == config_.skin) skin_index_ = static_cast<int>(i);

    boots_ = scan_boots(kUserBootDir);
    merge_packs(boots_, scan_boots(kFactoryBootDir));
    boot_index_ = 0;
    for (size_t i = 0; i < boots_.size(); ++i)
        if (boots_[i].id == config_.boot) boot_index_ = static_cast<int>(i);

    sounds_.push_back(silent_sound_pack());
    merge_packs(sounds_, scan_sounds(kUserSoundDir));
    merge_packs(sounds_, scan_sounds(kFactorySoundDir));
    sound_index_ = 0;
    for (size_t i = 0; i < sounds_.size(); ++i)
        if (sounds_[i].id == config_.sound) sound_index_ = static_cast<int>(i);

    apply_skin(skin_index_, nullptr);  // 建立几何与外壳
    apply_crt(config_.crt_level, nullptr);

    // 字体方案：theme/font/<方案名>/，方案内 font.* 是主字体（ASCII 与字形风格）、
    // font-cn.* 之类补齐它缺的码位
    font_schemes_ = font_scheme_names(kFontDir);
    load_font_chain(config_.font);

    host_.screen = &screen_;
    host_.input = &input_;
    host_.palette = &active_filter_;
    host_.language = config_.language;
    host_.audio = &audio_;
    rng_seed_ = opts.seed.value_or(
        static_cast<unsigned>(std::chrono::system_clock::now().time_since_epoch().count()));
    host_.rng.seed(rng_seed_);

    refresh_shelf_order();

    std::vector<std::string> names;
    for (const auto& skin : skins_) names.push_back(skin.name);
    shell_.set_skins(names, skin_index_);
    names.clear();
    for (const auto& filter : filters_) names.push_back(filter.name);
    shell_.set_filters(names, filter_index_);
    names.clear();
    for (const auto& boot : boots_) names.push_back(boot.name);
    shell_.set_boots(names, boot_index_);
    names.clear();
    for (const auto& sound : sounds_) names.push_back(sound.name);
    shell_.set_sounds(names, sound_index_);
    int font_index = 0;
    for (size_t i = 0; i < font_schemes_.size(); ++i)
        if (font_schemes_[i] == font_scheme_) font_index = static_cast<int>(i);
    shell_.set_fonts(font_schemes_, font_index);
    shell_.set_language(lang_from_name(config_.language));

    shell_.set_shelf_style(config_.shelf_style == "list" ? ShelfStyle::list : ShelfStyle::window);
    shell_.set_crt_level(config_.crt_level);
    shell_.set_fps(config_.fps);
    shell_.set_music_volume(config_.music_volume);
    shell_.set_sfx_volume(config_.sfx_volume);
    shell_.set_skin(skins_[skin_index_]);

    // 音频必须先于开机动画就绪：boot 事件音与动画脚本的 phos.audio.* 都在第一秒内发生
    if (!opts.headless) init_audio();

    start_boot_animation();

    headless_ = opts.headless;
    control_port_ = (opts.control && *opts.control > 0) ? *opts.control : 0;
    if (opts.save_dir) host_.save_dir = *opts.save_dir;  // 工具脚本用它隔离真实存档
    if (opts.headless) host_.fps = kLogicFps;  // 无头模式没有真实渲染帧率，报逻辑帧率

    // 控制通道（agent 接口）：仅在显式请求时开启，且只监听本机回环地址
    if (opts.control && *opts.control > 0) {
        std::string err;
        if (control_.start(static_cast<uint16_t>(*opts.control), err)) {
            std::fprintf(stderr, "control channel listening on 127.0.0.1:%d\n", *opts.control);
            log::info("control channel listening on 127.0.0.1:" + std::to_string(*opts.control));
        } else {
            log::warn("control channel unavailable: " + err);
        }
    }
    log::info("session start: mode=" + std::string(opts.headless ? "headless" : "window") +
              " skin=" + skins_[skin_index_].id + " filter=" + active_filter_.id +
              " boot=" + boots_[boot_index_].id + " sound=" + sounds_[sound_index_].id +
              " packs=" + std::to_string(skins_.size()) + "/" + std::to_string(filters_.size()) +
              "/" + std::to_string(boots_.size()) + "/" + std::to_string(sounds_.size()));

    const int code = opts.headless ? run_headless(opts) : run_windowed(opts);
    // 关机路径逐段留痕：机器"关不掉"时，日志的最后一行就是卡住的位置
    log::info("shutdown: main loop returned");
    control_.stop();
    log::info("shutdown: control channel closed");
    return code;
}

// ---------------------------------------------------------------- 主循环

void App::advance(float dt, Renderer* renderer, Window* window) {
    log::set_frame(frame_count_);  // 日志挂到帧时间线上
    host_.frame = frame_count_;    // 卡带侧 phos.sys.frame() 的取值来源

    // 拔卡收缩动画期间独占画面（机器"断电"的一瞬）
    if (eject_collapse_ > 0.0f) {
        eject_collapse_ -= dt;
        const float progress =
            1.0f - std::max(0.0f, eject_collapse_ / kEjectCollapseTime);
        shell_.draw_chassis(screen_);
        effects::draw_eject_collapse(screen_, content_rect(), progress,
                                     active_filter_.slots[static_cast<size_t>(PaletteSlot::white)],
                                     active_filter_.slots[static_cast<size_t>(PaletteSlot::black)]);
        input_.next_frame();
        return;
    }

    if (in_boot_) {
        shell_.draw(screen_);
        tick_boot(dt);
        if (boot_should_end()) end_boot();
        return;
    }
    if (playing_) {
        tick_playing(dt);
        return;
    }
    tick_shell(renderer, window);
}

void App::end_boot() {
    in_boot_ = false;
    boot_script_.reset();
    shell_.set_external_boot(false);
    shell_.to_shelf();
}

void App::tick_playing(float dt) {
    host_.time += dt;
    shell_.draw_chassis(screen_);
    shell_.set_lamps_solid(true);

    // 层与底层同一心智：每帧从透明开始。没建层的卡带这一步只是一次判断
    if (host_.layers.active()) host_.layers.clear_all();

    using clock = std::chrono::steady_clock;
    const auto t0 = clock::now();
    bool ok = cart_->update(dt);
    const auto t1 = clock::now();
    // 插卡瞬间的画面抖动：隔帧跳过一次绘制，形成电压不稳的闪烁
    const bool flicker = insert_flash_ > 0.0f && (frame_count_ % 3 == 0);
    const bool drawn = ok && !flicker;
    if (drawn) ok = cart_->draw();
    const auto t2 = clock::now();

    // 图层合成：只在这一帧真的画过、且卡带建过层时发生。
    // 没建层的卡带 `active()` 为假，这一步不存在——不是"快路径等价"，是根本没有它
    cart_merge_ms_ = 0.0f;
    if (drawn && ok && host_.layers.active()) {
        const auto m0 = clock::now();
        host_.layers.merge_over(screen_, host_.content_x, host_.content_y);
        cart_merge_ms_ = std::chrono::duration<float, std::milli>(clock::now() - m0).count();
    }

    if (insert_flash_ > 0.0f) {
        insert_flash_ -= dt;
        effects::draw_insert_flash(screen_, content_rect(),
                                   active_filter_.slots[static_cast<size_t>(PaletteSlot::white)],
                                   active_filter_.slots[static_cast<size_t>(PaletteSlot::green)],
                                   frame_count_);
    }

    cart_update_ms_ = std::chrono::duration<float, std::milli>(t1 - t0).count();
    cart_draw_ms_ = std::chrono::duration<float, std::milli>(t2 - t1).count();
    // 峰值按约 1 秒窗口滚动：瞬时值抓不到偶发卡顿，而卡顿恰恰是要查的东西
    cart_update_peak_ms_ = std::max(cart_update_peak_ms_, cart_update_ms_);
    cart_draw_peak_ms_ = std::max(cart_draw_peak_ms_, cart_draw_ms_);
    if (frame_count_ % kLogicFps == 0) {
        cart_update_peak_ms_ = 0.0f;
        cart_draw_peak_ms_ = 0.0f;
    }

    if (!ok) {
        last_error_ = cart_->error();
        log_cart_error(last_error_);  // 卡带脚本出错：日志里留下现场，便于事后定位
        eject_cart();
        shell_.show_error(last_error_);
        return;
    }

    // 侧栏分隔线由主机统一绘制，卡带只负责面板内容。
    // 宽度只认 host_.panel_w 这一个真源——卡带能在运行时改它（phos.panel.resize），
    // 这里若改读 manifest 的值，分隔线就会与面板实际宽度对不上
    if (host_.panel_w > 0) {
        // 分隔线贴着面板左缘：面板左缘由 panel_origin_x() 给出（内容区与面板宽度的函数），
        // 这里再抄一份"内容区宽 - 面板宽"就会与它脱节
        const int divider_x = host_.panel_origin_x() - 1;
        const Color divider_color =
            active_filter_.slots[static_cast<size_t>(PaletteSlot::dark_gray)];
        for (int y = host_.content_y; y < host_.content_y + host_.content_h; ++y)
            screen_.put(divider_x, y, U'|', divider_color);
    }
    input_.next_frame();
}

void App::tick_boot(float dt) {
    host_.time += dt;
    boot_elapsed_ += dt;
    if (boot_script_ && (!boot_script_->update(dt) || !boot_script_->draw())) {
        // 动画脚本出错：回退内置自检，不中断开机流程。
        // 必须留痕——静默回退会让作者以为自己的脚本生效了，排查时无从下手
        log::warn("boot script failed, falling back to built-in self-check: " +
                  boot_script_->error());
        boot_script_.reset();
        shell_.set_external_boot(false);
    }
    input_.next_frame();
}

void App::tick_shell(Renderer* renderer, Window* window) {
    const Shell::Intent intent = shell_.update(input_, kLogicStep);
    shell_.draw(screen_);
    shell_.set_lamps_solid(false);

    // 界面按键音：确认键与普通键区分
    if (any_key_edge()) play_event(input_.pressed(Key::start) ? "confirm" : "key");

    handle_intent(intent, renderer, window);
    input_.next_frame();
}

bool App::boot_should_end() const {
    return boot_elapsed_ >= kBootDuration || input_.pressed(Key::a);
}

/// 按卡带架上的下标插卡（路径来自卡带列表，见 Shell::cart_path_at）
void App::refresh_shelf_order() {
    std::vector<CartInfo> carts = scan_carts(kCartDir);
    sort_by_recent(carts, load_recent(kRecentPath));
    shell_.set_carts(std::move(carts));
}

void App::load_cart(int index) {
    // 记一次"最近打开"：拔卡回到架子时这张就排在最前
    remember_recent(kRecentPath, shell_.cart_id_at(index));
    load_cart_path(shell_.cart_path_at(index));
}

bool App::any_key_edge() const {
    for (const auto& name : input_.names())
        if (input_.pressed(name)) return true;
    return false;
}

ui::Rect App::content_rect() const {
    // 与外壳读同一份皮肤几何（core/skin.hpp 的 content_rect）：
    // host_.content_* 是给卡带 API 用的镜像，由 apply_skin 一处写入
    return phos::content_rect(skins_[static_cast<size_t>(skin_index_)]);
}

void App::start_boot_animation() {
    boot_elapsed_ = 0.0f;
    in_boot_ = true;
    boot_script_.reset();

    if (!boots_.empty()) {
        boot_script_ = std::make_unique<Cartridge>();
        if (!boot_script_->load_entry(boots_[boot_index_].dir, "main.lua", host_))
            boot_script_.reset();  // 加载失败：回退内置自检动画
    }
    shell_.set_external_boot(boot_script_ != nullptr);
    shell_.to_boot();

    // 启动日志：一行说明这轮开机动画来自哪里、音频是否已就绪
    // （"audio silent" 只应出现在 --headless 运行中）
    std::fprintf(stderr, "boot: %s (audio %s)\n",
                 boot_script_ ? boots_[boot_index_].id.c_str() : "built-in self-check",
                 audio_.active() ? "ready" : "silent");
    log::info("boot animation: " +
              (boot_script_ ? boots_[boot_index_].id : std::string("built-in self-check")));

    play_event("boot");
}

// ---------------------------------------------------------------- 输入落地



void App::apply_input_action(const InputAction& action, int hold_frames) {
    if (!action.host_key.empty()) {
        if (!action.down) return;  // 主机键只在按下沿生效
        if (action.host_key == kHostKeyEscape)
            handle_escape();
        else if (action.host_key == kHostKeySettings)
            shell_.open_settings();
        return;
    }
    if (action.key.empty()) return;
    input_.set_key(action.key, action.down);
    if (action.down && hold_frames > 0) pending_releases_.emplace_back(action.key, hold_frames);
}

// ---------------------------------------------------------------- 运行

int App::run_headless(const CliOptions& opts) {
    if (opts.cart) {
        load_cart_path(*opts.cart);
        if (!playing_) {
            std::fprintf(stderr, "ERROR: cart load failed: %s\n", last_error_.c_str());
            return 2;
        }
    }

    // headless 不初始化音频设备（agent/CI 场景保持静音且零设备依赖）
    // 帧预算：显式 --frames 优先；否则有控制通道时无限运行（由 agent 结束），无通道时跑 1 秒
    long budget = opts.frames;
    if (budget < 0 && !control_.running()) budget = kLogicFps;

    using clock = std::chrono::steady_clock;
    auto last = clock::now();
    long frame = 0;

    while (!quit_) {
        poll_control();

        // 单步模式：时间由 agent 的 time.step 驱动，空闲时不做任何推进
        if (control_time_driven() && pending_steps_ <= 0) {
            std::this_thread::sleep_for(std::chrono::milliseconds(1));
            continue;
        }
        if (budget >= 0 && frame >= budget) break;

        advance(kLogicStep, nullptr, nullptr);
        ++frame;
        ++frame_count_;
        release_expired_inputs();
        if (control_stepping_ && pending_steps_ > 0 && --pending_steps_ == 0)
            complete_step_request();
        maybe_dump(opts, frame);

        // 实时（非单步）且带控制通道时按逻辑帧率节流，避免空转吃满 CPU
        if (control_.running() && !control_time_driven()) {
            last += std::chrono::duration_cast<clock::duration>(
                std::chrono::duration<float>(kLogicStep));
            std::this_thread::sleep_until(last);
        }
    }

    write_final_outputs(opts);
    return 0;
}

int App::run_windowed(const CliOptions& opts) {
    std::string error;
    const Skin& skin = skins_[skin_index_];
    const WindowHandlers handlers{&input_, &escape_flag_,  &settings_flag_,
                                  &console_flag_, &input_blocked_};
    Window window = Window::create(skin.grid_w() * kCellPx, skin.grid_h() * kCellPx,
                                   kProductName, handlers, error);
    if (!window.valid()) {
        std::fprintf(stderr, "ERROR: %s\n", error.c_str());
        return 3;
    }

    Renderer renderer;
    if (!renderer.init(font_files_, kCellPx, kCellPx, error)) {
        std::fprintf(stderr, "ERROR: %s\n", error.c_str());
        return 3;
    }
    renderer.set_crt(active_crt_);
    // 字形度量交给 API 层（phos.text.ink_box）：与绘制同一份图集度量。
    // 无头模式不装它，调用方退回整格宽
    host_.glyph_metrics = [&renderer](char32_t cp) { return renderer.ink_box(cp); };

    if (!console_.init(window.handle(), error))
        std::fprintf(stderr, "WARN: %s (debug panel unavailable)\n", error.c_str());

    // 标题栏写明"谁在操作"：人看着窗口就知道是 agent 接管，还是自己在玩
    window.set_title(window_title_for_state());
    window_title_ = window_title_for_state();

    using clock = std::chrono::steady_clock;
    auto last = clock::now();
    float accumulator = 0.0f;

    if (opts.cart) load_cart_path(*opts.cart);

    while (!quit_ && !window.should_close()) {
        if (opts.frames > 0 && frame_count_ >= opts.frames) break;

        window.poll_events();
        poll_control();

        // agent 切换 实时/单步 时标题随之变化（只在变化时调 GLFW，避免每帧设置）
        if (const std::string title = window_title_for_state(); title != window_title_) {
            window_title_ = title;
            window.set_title(title);
        }

        if (console_flag_) {
            console_flag_ = false;
            console_.open = !console_.open;
        }
        input_blocked_ = console_.open && console_.wants_input();

        if (escape_flag_) {
            escape_flag_ = false;
            handle_escape();
        }
        if (settings_flag_) {
            settings_flag_ = false;
            shell_.open_settings();
        }

        const auto now = clock::now();
        float dt = std::chrono::duration<float>(now - last).count();
        last = now;
        if (dt > 0.25f) dt = 0.25f;  // 切出窗口后的时间爆炸保护
        if (dt > 0.0f) fps_ = fps_ * 0.9f + (1.0f / dt) * 0.1f;
        host_.fps = static_cast<int>(fps_ + 0.5f);  // 卡带侧 phos.sys.fps() 要的是真实帧率

        // 单步模式的推进**只看待推进帧数**，不攒墙钟时间：它的承诺是"推 N 帧，然后回包"，
        // 与显示器的刷新节奏无关。改成"攒够一个逻辑帧才走"就会在渲染循环快于逻辑帧的
        // 机器上（关垂直同步、高刷屏、窗口被遮挡）永远攒不够，time.step 永不回包
        if (control_time_driven()) {
            accumulator = 0.0f;
            while (pending_steps_ > 0) {
                // 一批里也要能被"关窗 / 退出 / 帧预算"打断：一次 time.step 要几百帧时，
                // 把这些检查推到批末就等于期间点关闭没有反应。停下前先回包，
                // 否则 agent 会等一个永远不会来的响应
                if (quit_ || window.should_close() ||
                    (opts.frames > 0 && frame_count_ >= opts.frames)) {
                    pending_steps_ = 0;
                    complete_step_request();
                    break;
                }
                advance(kLogicStep, &renderer, &window);
                ++frame_count_;
                release_expired_inputs();
                if (--pending_steps_ <= 0) complete_step_request();
                maybe_dump(opts, frame_count_);
            }
        } else {
            accumulator += dt;
            while (accumulator >= kLogicStep) {
                accumulator -= kLogicStep;
                advance(kLogicStep, &renderer, &window);
                ++frame_count_;
                release_expired_inputs();
                maybe_dump(opts, frame_count_);
            }
        }

        renderer.draw(screen_);
        if (console_.open) {
            DebugInfo info;
            fill_debug_info(info);
            console_.render(info);
            renderer.set_crt(active_crt_);  // 仪表盘可直接调参并即时生效
        }
        window.swap_buffers();

        // 帧率档位：每秒最多刷新这么多次画面。**只在实时（非单步）时生效** ——
        // 单步模式的承诺是"推 N 帧就回包"，给它加节流只会让 agent 的 time.step 越等越久。
        // 逻辑帧率恒为 kLogicFps（累加器按墙钟走），所以这里限制的是刷新率与 CPU 占用，
        // **不是**游戏速度：30 更省电、更有老机器的顿感，120/180 让扫描线与镜头平移更顺。
        // 睡眠基准取 last（本轮起点）而不是 now：慢帧不会被"追债"式补跑，也就不会抖
        if (!control_time_driven() && config_.fps > 0) {
            const auto budget = std::chrono::duration_cast<clock::duration>(
                std::chrono::duration<float>(1.0f / static_cast<float>(config_.fps)));
            const auto deadline = last + budget;
            // sleep 只能睡到下一个系统时钟片（Windows 默认约 15.6ms）：直接睡到点会睡过头，
            // 60 档实测只有 36 帧。所以先睡掉大半、留 1ms 自旋等到底，档位才说到做到。
            // 这 1ms 自旋是刷新率档位的代价（180 档约占 18% 的一个核），换来读数不撒谎
            // 自旋段不用 yield()：Windows 上它会把线程让出去好几个毫秒，等于又睡过头
            // （实测 60 档只有 46 帧）。纯自旋才准，代价就是那 1ms 的 CPU
            const auto slack = std::chrono::milliseconds(1);
            if (clock::now() + slack < deadline) std::this_thread::sleep_until(deadline - slack);
            while (clock::now() < deadline) {
            }
        }
    }

    host_.glyph_metrics = nullptr;  // 渲染器即将销毁：先收回度量回调
    console_.shutdown();

    write_final_outputs(opts);
    return 0;
}

} // namespace phos

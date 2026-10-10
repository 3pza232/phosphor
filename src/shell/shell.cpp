#include "shell/shell.hpp"

#include "core/defaults.hpp"
#include "core/text.hpp"
#include "core/version.hpp"
#include "shell/boot_view.hpp"
#include "shell/layout.hpp"
#include "shell/messages.hpp"
#include "shell/settings_view.hpp"
#include "shell/tape_view.hpp"

#include <cmath>

namespace phos {

namespace {

constexpr float kBootLineInterval = 0.4f;       // 内置兜底自检动画的逐行间隔
constexpr Color kFaultColor{255, 80, 80};       // 故障红：界面语义色，非主题色

} // namespace

// ---------------------------------------------------------------- 状态

void Shell::set_skin(const Skin& skin) {
    skin_ = skin;
    style_ = ui::style_from_skin(skin);
}

void Shell::set_carts(std::vector<CartInfo> carts) {
    carts_ = std::move(carts);
    if (shelf_cursor_ >= static_cast<int>(carts_.size())) shelf_cursor_ = 0;
    shelf_pos_ = static_cast<float>(shelf_cursor_);
}

void Shell::set_filters(std::vector<std::string> names, int active) {
    filter_names_ = std::move(names);
    if (active >= 0 && active < static_cast<int>(filter_names_.size()))
        filter_index_ = active;
}

void Shell::set_fonts(std::vector<std::string> names, int active) {
    font_names_ = std::move(names);
    if (active >= 0 && active < static_cast<int>(font_names_.size()))
        font_index_ = active;
}

void Shell::set_skins(std::vector<std::string> names, int active) {
    skin_names_ = std::move(names);
    if (active >= 0 && active < static_cast<int>(skin_names_.size()))
        skin_index_ = active;
}

void Shell::set_boots(std::vector<std::string> names, int active) {
    boot_names_ = std::move(names);
    if (active >= 0 && active < static_cast<int>(boot_names_.size()))
        boot_index_ = active;
}

void Shell::set_sounds(std::vector<std::string> names, int active) {
    sound_names_ = std::move(names);
    if (active >= 0 && active < static_cast<int>(sound_names_.size()))
        sound_index_ = active;
}

void Shell::set_shelf_style(ShelfStyle style) { shelf_style_ = style; }

void Shell::open_settings() {
    mode_ = ShellMode::settings;
    settings_cursor_ = 0;
}

void Shell::to_tape() {
    mode_ = ShellMode::tape;
    tape_.open();
}

void Shell::set_tape(std::string cart_name, std::string code, bool available) {
    tape_.set_tape(std::move(cart_name), std::move(code), available);
}

void Shell::set_fps(int fps) {
    // 落进档位表：手改配置写了个表外的数（如 75）时，界面不能显示一个不会生效的值
    auto dist = [fps](int value) { return value > fps ? value - fps : fps - value; };
    fps_ = kFpsChoices[0];
    for (int i = 1; i < kFpsChoiceCount; ++i)
        if (dist(kFpsChoices[i]) < dist(fps_)) fps_ = kFpsChoices[i];
}

void Shell::set_crt_level(int level) {
    crt_level_ = level < 0 ? 0 : (level >= kCrtLevelCount ? kCrtLevelCount - 1 : level);
}

void Shell::set_music_volume(int volume) {
    music_volume_ = volume < 0 ? 0 : (volume > 100 ? 100 : volume);
}

void Shell::set_sfx_volume(int volume) {
    sfx_volume_ = volume < 0 ? 0 : (volume > 100 ? 100 : volume);
}

std::string Shell::cart_path_at(int index) const {
    if (index < 0 || index >= static_cast<int>(carts_.size())) return {};
    return carts_[index].path;
}

std::string Shell::cart_id_at(int index) const {
    if (index < 0 || index >= static_cast<int>(carts_.size())) return {};
    return carts_[index].id;
}

void Shell::focus_cart(const std::string& id) {
    if (id.empty()) return;
    for (size_t i = 0; i < carts_.size(); ++i) {
        if (carts_[i].id == id) {
            shelf_cursor_ = static_cast<int>(i);
            shelf_pos_ = static_cast<float>(i);  // 视窗样式不要滑一段动画，直接落位
            return;
        }
    }
}

void Shell::show_error(const std::string& message) {
    error_message_ = message;
    mode_ = ShellMode::cart_error;
}

void Shell::to_boot() {
    mode_ = ShellMode::boot;
    boot_time_ = 0.0f;
}

void Shell::to_shelf() { mode_ = ShellMode::shelf; }

void Shell::to_paused() {
    mode_ = ShellMode::paused;
    pause_cursor_ = 0;
}

// ---------------------------------------------------------------- 更新

Shell::Intent Shell::update(const Input& input, float dt) {
    time_ += dt;

    // 视窗样式的滑动缓动（指数逼近，与帧率无关）
    const float target = static_cast<float>(shelf_cursor_);
    shelf_pos_ += (target - shelf_pos_) * (1.0f - std::exp(-10.0f * dt));
    if (std::fabs(target - shelf_pos_) < 0.001f) shelf_pos_ = target;

    switch (mode_) {
        case ShellMode::boot:
            boot_time_ += dt;
            if (boot_time_ > kBootDuration || input.pressed(Key::start))  // Enter 跳过自检
                mode_ = ShellMode::shelf;
            return {};
        case ShellMode::shelf: return update_shelf(input);
        case ShellMode::settings: return update_settings(input);
        case ShellMode::paused: return update_paused(input);
        case ShellMode::tape: return update_tape(input);
        case ShellMode::cart_error:
            if (input.pressed(Key::start)) return {.eject = true};  // Enter 返回卡带架
            return {};
    }
    return {};
}

void Shell::shelf_sync_cursor() {
    const std::vector<int> matches = shelf_matches();
    if (matches.empty()) return;   // 没结果：光标留在原处，插卡由"命中集为空"挡住
    for (int index : matches)
        if (index == shelf_cursor_) return;   // 还在结果里就不动，免得边打字边跳
    shelf_cursor_ = matches.front();   // 不在结果里：落到第一条（= 分数最高的那条）
}

Shell::Intent Shell::update_shelf(const Input& input) {
    Intent intent;

    // 输入框开着时，这一帧敲的字符全进查询串：方向键、插卡、搜索键都让位给打字。
    // 结算放在这里而不是让 App 代为转发——搜索是架面自己的状态
    if (shelf_search_.editing()) {
        shelf_search_.apply_text(input.text());
        if (input.pressed(Key::start)) shelf_search_.commit();
        // 每敲一个字都要把光标收进新的命中集：不然后面那次 Enter 插的是旧光标那张
        shelf_sync_cursor();
        // Esc 在这里不处理：架面上的 Esc 是主机关机键，由 App::handle_escape 统一裁决
        return intent;
    }
    if (input.pressed("f")) shelf_search_.begin_edit();

    // 先对齐再取命中集：下面的插卡用的是 shelf_cursor_，它必须已经在结果里
    shelf_sync_cursor();
    const std::vector<int> matches = shelf_matches();
    if (!matches.empty()) {
        // 光标在**命中集**里走，不是在整表里走：搜出三只就该一下一只，
        // 而不是跳过十几个不匹配的
        auto move = [&matches, this](int delta) {
            const int n = static_cast<int>(matches.size());
            int at = 0;
            for (int i = 0; i < n; ++i)
                if (matches[static_cast<std::size_t>(i)] == shelf_cursor_) at = i;
            shelf_cursor_ = matches[static_cast<std::size_t>((at + delta + n) % n)];
        };
        if (input.pressed(Key::left))  move(-1);
        if (input.pressed(Key::right)) move(1);
        if (shelf_style_ == ShelfStyle::list) {
            // 列表样式下用上下键更符合直觉
            if (input.pressed(Key::up))   move(-1);
            if (input.pressed(Key::down)) move(1);
        }
    }

    // 主机界面按 PC 习惯：Enter 插卡，Esc 返回/关机，F2 进设置（F2 由 App 转发到 open_settings）
    if (input.pressed(Key::start) && !matches.empty() && carts_[shelf_cursor_].error.empty()) {
        intent.insert_cart = true;
        intent.cart_index = shelf_cursor_;
    }
    return intent;
}

Shell::Intent Shell::update_settings(const Input& input) {
    Intent intent;
    const int items = settings_item_count();
    if (input.pressed(Key::up))   settings_cursor_ = (settings_cursor_ + items - 1) % items;
    if (input.pressed(Key::down)) settings_cursor_ = (settings_cursor_ + 1) % items;

    const bool confirm = input.pressed(Key::start);  // 主机界面：Enter 确认
    const bool left = input.pressed(Key::left);
    const bool right = input.pressed(Key::right);
    const bool adjust = left || right || confirm;

    // 选项行的共性：一份候选名字 + 一个当前下标。左右键（或 Enter）在这份列表上循环，
    // 列表为空说明该功能没有可选内容，此时不动。所有"选一个"的行都走这里。
    auto cycle = [](int index, int count, bool backward) {
        return (index + (backward ? count - 1 : 1)) % count;
    };
    auto pick_next = [&](const std::vector<std::string>& names, int& index) {
        if (names.empty() || !adjust) return false;
        index = cycle(index, static_cast<int>(names.size()), left);
        return true;
    };
    // 档位行同理，但候选是固定档数（扫描线）：左键等价于向前一档
    auto pick_level = [&](int& level, int count) {
        if (!adjust) return false;
        level = (level + (right ? 1 : count - 1)) % count;
        return true;
    };
    // 音量行：左右键改值，Enter 不改（与"选一个"的行区分开）
    auto adjust_volume = [&](int& volume, bool& changed) {
        if (!left && !right) return;
        volume = std::clamp(volume + (right ? kVolumeStep : -kVolumeStep), 0, 100);
        changed = true;
    };

    switch (static_cast<SettingId>(settings_cursor_)) {
        case SettingId::theme:
            if (pick_next(skin_names_, skin_index_)) {
                intent.skin_changed = true;
                intent.skin_index = skin_index_;
            }
            break;
        case SettingId::filter:
            if (pick_next(filter_names_, filter_index_)) {
                intent.filter_changed = true;
                intent.filter_index = filter_index_;
            }
            break;
        case SettingId::font:
            if (pick_next(font_names_, font_index_)) {
                intent.font_changed = true;
                intent.font_index = font_index_;
            }
            break;
        case SettingId::scanlines:
            intent.crt_changed = pick_level(crt_level_, kCrtLevelCount);
            break;
        case SettingId::fps: {
            // 与扫描线同规矩：左键往前一档，Enter 也算调整（一个键就能走遍四档）
            if (adjust) {
                int at = 0;
                for (int i = 0; i < kFpsChoiceCount; ++i)
                    if (kFpsChoices[i] == fps_) at = i;
                const int step = right ? 1 : kFpsChoiceCount - 1;
                fps_ = kFpsChoices[(at + step) % kFpsChoiceCount];
                intent.fps_changed = true;
            }
            break;
        }
        case SettingId::sound_pack:
            if (pick_next(sound_names_, sound_index_)) {
                intent.sound_changed = true;
                intent.sound_index = sound_index_;
            }
            break;
        case SettingId::music_volume:
            adjust_volume(music_volume_, intent.music_volume_changed);
            break;
        case SettingId::sfx_volume:
            adjust_volume(sfx_volume_, intent.sfx_volume_changed);
            break;
        case SettingId::boot:
            if (pick_next(boot_names_, boot_index_)) {
                intent.boot_changed = true;
                intent.boot_index = boot_index_;
            }
            break;
        case SettingId::shelf_view:
            if (adjust) {
                shelf_style_ =
                    shelf_style_ == ShelfStyle::list ? ShelfStyle::window : ShelfStyle::list;
                intent.shelf_style_changed = true;
            }
            break;
        case SettingId::language:
            if (adjust) {
                lang_ = lang_ == Lang::zh ? Lang::en : Lang::zh;  // 两选一，直接翻面
                intent.language_changed = true;
            }
            break;
        case SettingId::back:
            if (confirm) mode_ = ShellMode::shelf;
            break;
        default:
            break;
    }

    if (input.pressed(Key::b)) mode_ = ShellMode::shelf;
    return intent;
}

Shell::Intent Shell::update_tape(const Input& input) {
    Intent intent;
    // 按键、滚动、输入缓冲与过滤都在 shell/tape_view.cpp；这里只把它的请求翻成外壳意图
    const std::string code = tape_.update(input);
    if (!code.empty()) {
        intent.tape_import = true;
        intent.tape_code = code;
    }
    return intent;
}

Shell::Intent Shell::update_paused(const Input& input) {
    Intent intent;
    constexpr int kItems = 3;
    if (input.pressed(Key::up))   pause_cursor_ = (pause_cursor_ + kItems - 1) % kItems;
    if (input.pressed(Key::down)) pause_cursor_ = (pause_cursor_ + 1) % kItems;
    if (input.pressed(Key::start)) {  // Enter 确认（Esc 直接继续，见 handle_escape）
        if (pause_cursor_ == 0) intent.resume = true;
        else if (pause_cursor_ == 1) {
            to_tape();
            intent.open_tape = true;  // App 据此填入当前卡带的磁带码
        } else
            intent.eject = true;
    }
    return intent;
}

// ---------------------------------------------------------------- 布局

ui::Rect Shell::content_rect() const { return phos::content_rect(skin_); }

ShelfView Shell::shelf_view(const std::vector<CartInfo>& shown, int cursor) const {
    // 搜索生效时不做滑动动效：那个动效状态是按**整表**下标攒的，过滤后下标含义变了，
    // 混用会让图标来回窜。瞬时定位更好——搜东西时没人想等动画
    const float position = shelf_search_.visible() ? static_cast<float>(cursor) : shelf_pos_;
    return ShelfView{&shown, shelf_style_, cursor, position, lang_};
}

// ---------------------------------------------------------------- 绘制

void Shell::draw_chassis(Screen& screen) const { draw_bezel(screen); }

void Shell::draw(Screen& screen) const {
    draw_bezel(screen);
    switch (mode_) {
        case ShellMode::boot: draw_boot(screen); break;
        case ShellMode::shelf: draw_shelf(screen); break;
        case ShellMode::settings: draw_settings(screen); break;
        case ShellMode::paused: draw_paused(screen); break;
        case ShellMode::tape: draw_tape(screen); break;
        case ShellMode::cart_error: draw_error(screen); break;
    }
}

void Shell::draw_bezel(Screen& screen) const {
    const ui::Rect content = content_rect();
    screen.fill(0, 0, screen.width(), screen.height(), U' ', style_.fg, style_.bg);

    auto pad_to_grid = [&screen](std::string row) {
        row.resize(static_cast<size_t>(screen.width()), ' ');
        return row;
    };
    for (size_t i = 0; i < skin_.top.size() && static_cast<int>(i) < content.y; ++i)
        ui::print(screen, 0, static_cast<int>(i), pad_to_grid(skin_.top[i]),
                  style_.frame, style_.bg);
    for (size_t i = 0; i < skin_.bottom.size(); ++i) {
        const int y = content.bottom() + 1 + static_cast<int>(i);
        if (y < screen.height())
            ui::print(screen, 0, y, pad_to_grid(skin_.bottom[i]), style_.frame, style_.bg);
    }

    // 左右侧壁：字符按行轮换
    for (int row = 0; row < content.h; ++row) {
        const int y = content.y + row;
        for (int x = 0; x < content.x; ++x) {
            if (!skin_.left.empty())
                screen.put(x, y, static_cast<unsigned char>(skin_.left[row % skin_.left.size()]),
                           style_.frame, style_.bg);
            if (!skin_.right.empty()) {
                const char rc = skin_.right[row % skin_.right.size()];
                screen.put(screen.width() - 1 - x, y, static_cast<unsigned char>(rc),
                           style_.frame, style_.bg);
            }
        }
    }

    // 指示灯：待机时呼吸，卡带运行时常亮（机器被唤醒）
    for (const auto& lamp : skin_.lamps) {
        float glow = 1.0f;
        if (!lamps_solid_) {
            const float phase = std::fmod(time_ / lamp.period, 1.0f);
            glow = 0.35f + 0.65f * (0.5f + 0.5f * std::sin(phase * 6.28318f));
        }
        const Color color{static_cast<uint8_t>(lamp.color.r * glow),
                          static_cast<uint8_t>(lamp.color.g * glow),
                          static_cast<uint8_t>(lamp.color.b * glow)};
        if (lamp.x >= 0 && lamp.x < screen.width() && lamp.y >= 0 && lamp.y < screen.height())
            screen.put(lamp.x, lamp.y, U'*', color, style_.bg);
    }
}

void Shell::draw_chrome(Screen& screen, const std::string& title,
                        const std::string& right_text) const {
    const ui::Rect content = content_rect();
    ui::fill(screen, content, U' ', style_.fg, style_.bg);
    ui::print(screen, content.x + ShellLayout::kMarginX, content.y + ShellLayout::kTitleY, title,
              style_.accent, style_.bg);
    if (!right_text.empty())
        ui::print(screen, content.right() - ShellLayout::kMarginX -
                              text::display_width(right_text) + 1,
                  content.y + ShellLayout::kTitleY, right_text, style_.dim, style_.bg);
    ui::divider(screen, content.x, content.y + ShellLayout::kRuleY, content.w, style_.dim, style_.bg);
}

void Shell::draw_footer(Screen& screen, const std::string& hints) const {
    const ui::Rect content = content_rect();
    ui::print(screen, content.x + ShellLayout::kMarginX,
              content.bottom() - ShellLayout::kFooterGap + 1, hints, style_.dim, style_.bg);
}

void Shell::draw_boot(Screen& screen) const {
    if (external_boot_) return;  // 由启动动画包作画

    // 兜底：一个启动动画包都没有时，主机画内置自检（渲染见 shell/boot_view.cpp）
    boot::draw(screen, boot::BootContext{lang_, content_rect(), boot_time_, kBootLineInterval},
               style_);
}

void Shell::draw_shelf(Screen& screen) const {
    const std::vector<int> matches = shelf_matches();
    // 视图只认"一串卡带 + 一个光标"：把命中结果拷成一份临时表递过去，
    // 渲染层不必知道有搜索这回事（搜索是外壳的状态，不是渲染的知识）
    std::vector<CartInfo> shown;
    shown.reserve(matches.size());
    int shown_cursor = 0;
    for (std::size_t i = 0; i < matches.size(); ++i) {
        shown.push_back(carts_[static_cast<std::size_t>(matches[i])]);
        if (matches[i] == shelf_cursor_) shown_cursor = static_cast<int>(i);
    }

    const std::string counter = shown.empty()
        ? std::string("0 / 0")
        : std::to_string(shown_cursor + 1) + " / " + std::to_string(shown.size());
    draw_chrome(screen, tr(lang_, Msg::shelf_title), counter);

    const ui::Rect content = content_rect();
    shelf::draw(screen, content, shelf_view(shown, shown_cursor), style_);

    if (shelf_search_.visible()) {
        // 搜索框压在上栏区域的居中位置：盖住标题与计数是有意的——正在搜索时，
        // 它才是注意力的中心，被它盖住的两行没有信息量
        const int room = content.w - 4;
        const ui::Rect box{content.x + (content.w - (room < 46 ? room : 46)) / 2,
                           content.y + ShellLayout::kTitleY, room < 46 ? room : 46, 3};
        ui::fill(screen, box, U' ', style_.fg, style_.bg);
        ui::frame(screen, box, tr(lang_, Msg::shelf_search_title), style_);
        const std::string field = "> " + shelf_search_.query() + (shelf_search_.editing() ? "_" : "");
        ui::print(screen, box.x + 2, box.y + 1,
                  text::truncate(field, box.w - 4), style_.fg, style_.bg);
    }

    if (!shelf_search_.visible())
        draw_footer(screen, tr(lang_, Msg::shelf_insert_hint));
    else if (matches.empty() && !carts_.empty())
        draw_footer(screen, tr(lang_, Msg::shelf_search_empty));
    else
        draw_footer(screen, tr(lang_, Msg::shelf_search_hint));
}

void Shell::draw_settings(Screen& screen) const {
    draw_chrome(screen, tr(lang_, Msg::settings_title), "");

    SettingsContext ctx;
    ctx.skins = skin_names_;
    ctx.filters = filter_names_;
    ctx.fonts = font_names_;
    ctx.boots = boot_names_;
    ctx.sounds = sound_names_;
    ctx.skin_index = skin_index_;
    ctx.filter_index = filter_index_;
    ctx.font_index = font_index_;
    ctx.boot_index = boot_index_;
    ctx.sound_index = sound_index_;
    ctx.crt_level = crt_level_;
    ctx.fps = fps_;
    ctx.music_volume = music_volume_;
    ctx.sfx_volume = sfx_volume_;
    ctx.window_style = shelf_style_ == ShelfStyle::window;
    ctx.lang = lang_;
    ctx.lang_index = lang_ == Lang::en ? 1 : 0;

    ui::Rect area = content_rect();
    area.y += ShellLayout::kContentTop;
    area.h -= ShellLayout::kContentTop + ShellLayout::kFooterGap;
    phos::draw_settings(screen, area, ctx, style_, settings_cursor_);  // 界面布局见 settings_view.cpp

    draw_footer(screen, tr(lang_, Msg::settings_footer));
}

void Shell::draw_paused(Screen& screen) const {
    const ui::Rect content = content_rect();
    const ui::Rect box = ui::Rect::centered(content, ShellLayout::kPauseW, ShellLayout::kPauseH);
    ui::fill(screen, box, U' ', style_.fg, style_.bg);
    ui::frame(screen, box, tr(lang_, Msg::pause_title), style_);

    const std::vector<std::string> items = {tr(lang_, Msg::pause_resume),
                                            tr(lang_, Msg::pause_tape),
                                            tr(lang_, Msg::pause_eject)};
    ui::menu(screen, ui::Rect{box.x + 6, box.y + 3, box.w - 12, 5}, items, pause_cursor_, style_);

    draw_footer(screen, tr(lang_, Msg::pause_footer));
}

void Shell::draw_tape(Screen& screen) const {
    // 标题栏与页脚是全机统一的，所以由外壳画；页面文案编号由界面模块报出——
    // 模块不碰语言，它只说自己"现在是哪一页、页脚该提示什么"
    draw_chrome(screen, tr(lang_, Msg::tape_title), tr(lang_, tape_.page_hint()));
    tape_.draw(screen, content_rect(), lang_, style_);
    draw_footer(screen, tr(lang_, tape_.footer_hint()));
}

void Shell::draw_error(Screen& screen) const {
    const ui::Rect content = content_rect();
    ui::fill(screen, content, U' ', style_.fg, style_.bg);
    ui::print(screen, content.x + 2, content.y + 1, tr(lang_, Msg::error_title), kFaultColor,
              style_.bg);
    ui::divider(screen, content.x, content.y + 2, content.w, style_.dim, style_.bg);
    ui::print(screen, content.x + 4, content.y + 6, tr(lang_, Msg::error_body), style_.fg,
              style_.bg);
    ui::text_block(screen, content.x + 4, content.y + 8, 70, error_message_, 12, style_);
    ui::print(screen, content.x + 4, content.bottom() - 2, tr(lang_, Msg::error_footer),
              style_.dim, style_.bg);
}

} // namespace phos

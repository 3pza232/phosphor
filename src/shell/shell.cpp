#include "shell/shell.hpp"

#include "core/color.hpp"
#include "core/defaults.hpp"
#include "core/text.hpp"
#include "core/version.hpp"
#include "shell/boot_view.hpp"
#include "shell/layout.hpp"
#include "shell/messages.hpp"
#include "shell/settings_view.hpp"
#include "shell/tape_view.hpp"

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <string_view>
#include <utility>

namespace phos {

namespace {

constexpr float kBootLineInterval = 0.4f;       // 内置兜底自检动画的逐行间隔
constexpr Color kFaultColor{255, 80, 80};       // 故障红：界面语义色，非主题色
constexpr int kModsMinWidth = 24;               // MODS 浮窗最小宽度（短名字也别太窄）
constexpr int kModsPad = 6;                     // 列表左右留白：'>' 光标 + 文本起点 + 右边距

// 组件层按 screen id 存跨帧状态（焦点/列表光标）。屏 id 与元素 id 在这里各写一次：
// 分散成字符串字面量后，改一个忘一个就是"光标回到别处"这类难查的错
constexpr const char* kPausedScreen = "shell.paused";
constexpr const char* kPauseMenu = "paused/menu";
constexpr const char* kModsScreen = "shell.mods";
constexpr const char* kModsBox = "mods/box";
constexpr const char* kModsConfirm = "mods/confirm";
constexpr const char* kModsRowPrefix = "mods/row/";
constexpr const char* kTapeScreen = "shell.tape";
constexpr const char* kShelfScreen = "shell.shelf";
constexpr const char* kShelfSearchField = "shelf/search";
constexpr int kShelfSearchMaxW = 46;  // 搜索浮窗宽度上限（窄屏按可用宽度收缩）

// 暂停浮窗：外框尺寸仍取 ShellLayout（逐格位置与旧版面一致）；
// 列表在框内的缩进改写**内边距**——旧实现是 +6/+3 的硬编码坐标，与盒模型各说一套
constexpr int kPausePadX = 5;
constexpr int kPausePadY = 2;

// MODS 行：光标贴内容区左缘，文本从它 +3 列起；"[x] " 前缀由勾选控件自己画
constexpr int kModsIndent = 0;
constexpr int kModsTextGap = 3;
constexpr int kModsRowPadY = 1;   // 浮窗上下各留一行：行区从框内第二行起（旧版面同格）

std::string mods_row_id(int index) { return std::string(kModsRowPrefix) + std::to_string(index); }

/// 由元素 id 反解行号；不是 mod 行返回 false
bool mods_row_index(const std::string& id, int& index) {
    const std::string prefix = kModsRowPrefix;
    if (id.rfind(prefix, 0) != 0) return false;
    index = std::atoi(id.c_str() + prefix.size());
    return true;
}

/// MODS 浮窗的键位：A / 空格切换勾选、激活确认行。方向键**不交给组件**——
/// 单列光标要跨"滚动窗口"首尾循环，组件级的焦点导航在一个会重新排布的窗口里做不到
ui::Keys mods_keys() {
    ui::Keys keys;
    keys.confirm = {"a", "space"};
    // 方向键与 Tab 都不交给组件：旧版的 Mod 浮窗只认 A/空格，方向键由宿主做光标环绕
    keys.up.clear();
    keys.down.clear();
    keys.left.clear();
    keys.right.clear();
    keys.next_focus.clear();
    keys.prev_focus.clear();
    return keys;
}

/// 绝对定位节点的 x/y 相对**父内容区**：把整屏坐标换过去（宽高仍按整框声明）
std::pair<int, int> offset_in(const ui::Rect& area, const ui::Rect& rect) {
    return {rect.x - area.x, rect.y - area.y};
}

/// 搜索框：压在标题栏区域的居中浮窗（盖住标题与计数是**有意的**——搜索时它才是注意力中心）
ui::Rect search_box(const ui::Rect& content) {
    const int room = content.w - 4;
    const int w = std::min(room, kShelfSearchMaxW);
    return ui::Rect{content.x + (content.w - w) / 2, content.y + ShellLayout::kTitleY, w, 3};
}

/// 某控件当前的光标（没有状态就是 0）：宿主要读回组件记的光标才能对外观测
int widget_cursor(const ui::State& state, const char* screen_id, const char* widget_id) {
    const auto screen = state.screens.find(screen_id);
    if (screen == state.screens.end()) return 0;
    const auto widget = screen->second.widgets.find(widget_id);
    return widget == screen->second.widgets.end() ? 0 : widget->second.cursor;
}


/// ShellMode ↔ 屏栈 id：栈里只存字符串（ScreenStack 不依赖 shell），切换处做映射
const char* shell_mode_id(ShellMode mode) {
    switch (mode) {
        case ShellMode::boot: return "boot";
        case ShellMode::shelf: return "shelf";
        case ShellMode::settings: return "settings";
        case ShellMode::paused: return "paused";
        case ShellMode::mods: return "mods";
        case ShellMode::tape: return "tape";
        case ShellMode::cart_error: return "cart_error";
    }
    return "shelf";
}

bool shell_mode_from(std::string_view id, ShellMode& mode) {
    if (id == "boot") mode = ShellMode::boot;
    else if (id == "shelf") mode = ShellMode::shelf;
    else if (id == "settings") mode = ShellMode::settings;
    else if (id == "paused") mode = ShellMode::paused;
    else if (id == "mods") mode = ShellMode::mods;
    else if (id == "tape") mode = ShellMode::tape;
    else if (id == "cart_error") mode = ShellMode::cart_error;
    // 关于页是 settings 之上的普通浮层：对 App 仍报告 settings（Esc 路由不必改）
    else if (id == "about") mode = ShellMode::settings;
    // 存档管理同样是 settings 之上的浮层：对 App 仍报告 settings
    else if (id == "saves") mode = ShellMode::settings;
    else return false;
    return true;
}

} // namespace

ShellMode Shell::mode() const {
    ShellMode mode = ShellMode::boot;
    if (!shell_mode_from(screens_.top(), mode)) return ShellMode::boot;
    return mode;
}

void Shell::push_screen(ShellMode mode, bool modal) {
    screens_.push(shell_mode_id(mode), modal);
}

void Shell::pop_screen() {
    // 正常路径总有根屏（shelf/paused）；空栈兜底回卡带架，避免 Shell 没有可画模式
    if (!screens_.pop()) screens_.push(shell_mode_id(ShellMode::shelf));
}

void Shell::reset_screen(ShellMode mode, bool modal) { screens_.reset(shell_mode_id(mode), modal); }

void Shell::open_about() {
    settings_search_clear(settings_search_);
    screens_.push("about");
}

bool Shell::about_open() const { return screens_.top() == "about"; }

// ---------------------------------------------------------------- 状态

void Shell::set_skin(const Skin& skin) {
    skin_ = skin;
    style_ = ui::style_from_skin(skin);
    ui_theme_ = ui::theme_from_skin(skin);
}

void Shell::set_carts(std::vector<CartInfo> carts) {
    carts_ = std::move(carts);
    if (shelf_cursor_ >= static_cast<int>(carts_.size())) shelf_cursor_ = 0;
    shelf_pos_ = static_cast<float>(shelf_cursor_);
}

void Shell::set_fonts(std::vector<std::string> names, int active) {
    font_names_ = std::move(names);
    if (active >= 0 && active < static_cast<int>(font_names_.size()))
        font_index_ = active;
}

void Shell::set_font_size(int px, int min_px, int max_px) {
    font_px_ = px;
    font_min_ = min_px;
    font_max_ = max_px;
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

void Shell::set_shelves(std::vector<ShelfOption> options, int active) {
    shelf_options_ = std::move(options);
    const int count = 2 + static_cast<int>(shelf_options_.size());
    shelf_index_ = (active >= 0 && active < count) ? active : 1;  // 越界回退 window
}

void Shell::set_mods(std::vector<ModOption> mods) {
    mods_ = std::move(mods);
}

void Shell::open_settings() {
    // 设置只在**卡带架**（主机主界面）唤起。暂停/磁带码等是在运行中的卡带之上开的浮层，
    // 从那里跳进设置会让"关掉设置回哪去"变得含糊；卡带运行时读盘/换卡也不该被打断
    if (mode() != ShellMode::shelf) return;
    push_screen(ShellMode::settings);
    settings_cursor_ = 0;
    settings_search_clear(settings_search_);  // 每次进设置都是完整列表
}

bool Shell::settings_on_sound_row() const {
    // 关于页/存档管理是 settings 之上的浮层：它们没有"音效行"，
    // 别让底下的旧光标在浮层里误触发试听
    return !about_open() && !saves_open() && mode() == ShellMode::settings &&
           static_cast<SettingId>(settings_cursor_) == SettingId::sound_pack;
}

void Shell::to_tape() {
    tape_over_saves_ = saves_open();  // 从存档管理打开：关闭时回列表而不是暂停菜单
    push_screen(ShellMode::tape);
    tape_.open();
    // 输入页的文本域状态也归零：不清的话上次没导完的码会留在框里（旧实现的 open 同样清缓冲）
    ui_state_.forget(kTapeScreen);
}

void Shell::set_tape(std::string cart_name, std::string code, bool available) {
    tape_.set_tape(std::move(cart_name), std::move(code), available);
}

void Shell::set_save_hooks(SaveListFn list, SaveDeleteFn remove, SaveCodeFn code) {
    save_list_ = std::move(list);
    save_delete_ = std::move(remove);
    save_code_ = std::move(code);
}

bool Shell::saves_open() const { return screens_.top() == "saves"; }

void Shell::open_saves() {
    settings_search_clear(settings_search_);  // 与关于页同一规则：进浮层先收起搜索
    screens_.push("saves");
    saves_.open();
    if (save_list_) saves_.set_entries(save_list_());
    ui_state_.forget(save::ScreenState::kScreenId);  // 焦点从第一项开始，不沿用上次屏幕
}

Shell::Intent Shell::update_saves(const Input& input) {
    Intent intent;
    const ui::Rect area = content_rect();
    ui::Frame frame(save::ScreenState::kScreenId, ui_state_, ui_theme_, area, &input,
                    ui::Keys::host());
    saves_.build(frame.root(), area, lang_);

    const auto row_index = [](const std::string& id) {
        return id.rfind("saves/row/", 0) == 0 ? std::atoi(id.c_str() + 10) : -1;
    };

    for (const ui::Event& event : frame.run()) {
        if (event.kind == ui::EventKind::cancelled) {
            saves_.set_confirm(false);
            pop_screen();
            break;
        }

        // 列表行是 option：Enter 产生 changed(confirm=true)，而非 activated；
        // 左右键的 changed(delta) 只是浏览，不该触发导出
        const int index = row_index(event.id);
        if (index >= 0) {
            const bool open_code =
                event.kind == ui::EventKind::activated ||
                (event.kind == ui::EventKind::changed && event.confirm);
            if (!open_code) continue;

            // Enter 在一行存档上 = 查看导出码：数据由 App 钩子读（复用 SaveStore 的导出逻辑），
            // 然后进既有磁带码界面；关掉磁带码会回到存档列表（见 to_paused）
            saves_.select(index);
            const save::Entry* entry = saves_.selected_entry();
            if (!entry || !save_code_) continue;
            std::string cart_name;
            std::string code;
            if (save_code_(*entry, cart_name, code)) {
                const bool available = !code.empty();  // 先判定再 move，避免看空串
                set_tape(std::move(cart_name), std::move(code), available);
            } else {
                set_tape(entry->cart_id, std::string(), false);  // 读不出：按"无存档"处理
            }
            to_tape();
            return intent;
        }
        if (event.kind != ui::EventKind::activated) continue;

        if (event.id == save::ScreenState::kBackId) {
            saves_.set_confirm(false);
            pop_screen();
            break;
        }
        if (event.id == save::ScreenState::kDeleteId) {
            saves_.set_confirm(true);
            break;
        }
        if (event.id == save::ScreenState::kCancelId) {
            saves_.set_confirm(false);
            break;
        }
        if (event.id == save::ScreenState::kConfirmId) {
            const save::Entry* entry = saves_.selected_entry();
            const bool removed = entry && save_delete_ && save_delete_(*entry);
            saves_.set_confirm(false);
            if (removed && save_list_) {
                saves_.set_entries(save_list_());  // 删除后刷新列表
                // 行 id 是按下标编的：删掉一条后旧焦点可能指向不存在的行，重置到第一项
                ui_state_.forget(save::ScreenState::kScreenId);
            }
            break;
        }
    }

    // 焦点行即选中项：上下移动后，删除/导出目标必须跟着变
    const std::string& focused = frame.focused_id();
    const int focused_index = row_index(focused);
    if (focused_index >= 0) saves_.select(focused_index);
    return intent;
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
    reset_screen(ShellMode::shelf);
    push_screen(ShellMode::cart_error, true);
}

void Shell::to_boot() {
    reset_screen(ShellMode::boot);
    boot_time_ = 0.0f;
}

void Shell::to_shelf() {
    // 存档管理是 settings 栈上的浮层：Esc 先回设置（再按一次才回卡带架）
    if (saves_open()) {
        saves_.set_confirm(false);
        screens_.pop();
        return;
    }
    // 关于页是 settings 栈上的浮层：App 的 Esc 路由调到这里时先 pop 回设置，不离开设置。
    if (about_open()) {
        screens_.pop();
        return;
    }
    // App 的 Esc 路由在 Shell::update 之前执行：设置搜索中按 Esc 先退出搜索、留在设置，
    // 再按一次才回卡带架（与卡带架搜索"Esc 只清搜索"的语义一致）
    if (mode() == ShellMode::settings && settings_search_.active) {
        settings_search_clear(settings_search_);
        return;
    }
    reset_screen(ShellMode::shelf);
}

void Shell::to_paused() {
    // 从存档管理里打开的磁带码：Esc 先回存档列表，而不是暂停菜单
    if (tape_over_saves_) {
        tape_over_saves_ = false;
        screens_.pop();
        return;
    }
    reset_screen(ShellMode::paused);
    pause_cursor_ = 0;
    // 光标由组件按元素 id 记着：进屏时显式归位，否则会停在上次退出的那一项
    ui_state_.screen(kPausedScreen).widgets[kPauseMenu].cursor = 0;
}

void Shell::open_mods() {
    if (mods_.empty()) return;   // 没有 mod 就没有可管理的东西
    push_screen(ShellMode::mods);
    // 勾选态 = 当前有效启用态（由 App 从 default_off + 两个配置列表算好）；
    // 快照存下来，"关掉又开回"才不会误判成变化
    mods_checked_.assign(mods_.size(), true);
    for (size_t i = 0; i < mods_.size(); ++i) mods_checked_[i] = mods_[i].enabled;
    // 快照只含现有 mod 的启用态：配置里指向已删除 mod 的陈旧项不算改动，
    // 否则打开后原样确认也会被判成"有变化"而平白重启
    mods_enabled_snapshot_ = mods_enabled_now();
    mods_cursor_ = 0;
}

std::vector<std::string> Shell::mods_enabled_now() const {
    std::vector<std::string> out;
    for (size_t i = 0; i < mods_.size(); ++i)
        if (i < mods_checked_.size() && mods_checked_[i]) out.push_back(mods_[i].id);
    return out;
}

bool Shell::mods_changed() const {
    // 集合语义比较：内容相同即"没变"，与列举顺序、按键历史无关
    auto normalize = [](std::vector<std::string> v) {
        std::sort(v.begin(), v.end());
        v.erase(std::unique(v.begin(), v.end()), v.end());
        return v;
    };
    return normalize(mods_enabled_now()) != normalize(mods_enabled_snapshot_);
}

ui::Rect Shell::mods_box() const {
    const ui::Rect content = content_rect();
    const int items = static_cast<int>(mods_.size()) + 1;  // + 确认（Esc 即取消）
    int h = items + 4;
    const int max_h = content.h - 2;
    if (h > max_h) h = max_h;
    if (h < 6) h = 6;
    // 宽度按最宽的 mod **显示名**算（含 "[x] " 前缀与左右留白），并给一个最小宽度；
    // 列表长时仍单列，只是更高的内容靠滚动容纳
    int w = kModsMinWidth;
    for (const ModOption& mod : mods_) {
        const std::string& name = lang_ == Lang::en ? mod.en : mod.zh;
        const int row = text::display_width("[x] ") + text::display_width(name);
        if (row + kModsPad > w) w = row + kModsPad;
    }
    const int max_w = content.w - 2;
    if (w > max_w) w = max_w;
    return ui::Rect::centered(content, w, h);
}

// ---------------------------------------------------------------- 更新

Shell::Intent Shell::update(const Input& input, float dt) {
    time_ += dt;

    // 视窗样式的滑动缓动（指数逼近，与帧率无关）
    const float target = static_cast<float>(shelf_cursor_);
    shelf_pos_ += (target - shelf_pos_) * (1.0f - std::exp(-10.0f * dt));
    if (std::fabs(target - shelf_pos_) < 0.001f) shelf_pos_ = target;

    switch (mode()) {
        case ShellMode::boot:
            boot_time_ += dt;
            if (boot_time_ > kBootDuration || input.pressed(Key::start))  // Enter 跳过自检
                reset_screen(ShellMode::shelf);
            return {};
        case ShellMode::shelf: return update_shelf(input);
        case ShellMode::settings: return update_settings(input);
        case ShellMode::paused: return update_paused(input);
        case ShellMode::mods: return update_mods(input);
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
    // M：打开 Mod 管理器（仅当有 mod 时）。架面上的自定义键，与 F 搜索同级
    if (!mods_.empty() && input.pressed("m")) {
        open_mods();
        return intent;
    }

    // 先对齐再取命中集：下面的插卡用的是 shelf_cursor_，它必须已经在结果里
    shelf_sync_cursor();
    const std::vector<int> matches = shelf_matches();
    if (!matches.empty()) {
        const int n = static_cast<int>(matches.size());
        // 光标在**命中集**里走，不是在整表里走：搜出三只就该一下一只，
        // 而不是跳过十几个不匹配的
        auto at_of = [&matches, this]() {
            for (int i = 0; i < static_cast<int>(matches.size()); ++i)
                if (matches[static_cast<std::size_t>(i)] == shelf_cursor_) return i;
            return 0;
        };
        // 环绕：内置与内容包一致——越过一端从另一端回来。上下按行（±cols）、
        // 左右按格（±1）；delta 可能大于命中集长度，取模前先归正到 [0,n)
        auto move = [&, this](int delta) {
            const int at = ((at_of() + delta) % n + n) % n;
            shelf_cursor_ = matches[static_cast<std::size_t>(at)];
        };

        const bool external = shelf_index_ >= 2;  // 内容包接管时的二维导航
        const int cols = shelf_cols();            // 0 = 包未声明列数
        if (input.pressed(Key::left))  move(-1);
        if (input.pressed(Key::right)) move(1);
        if (input.pressed(Key::up)) {
            if (external)
                move(-(cols > 0 ? cols : 1));  // 逐行上移；无列数声明也至少动一格
            else if (shelf_index_ == 0)
                move(-1);  // 列表样式下用上下键更符合直觉（内置行为不变）
        }
        if (input.pressed(Key::down)) {
            if (external)
                move(cols > 0 ? cols : 1);
            else if (shelf_index_ == 0)
                move(1);
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
    if (saves_open()) return update_saves(input);  // 存档管理浮层有自己的选中/确认逻辑
    if (about_open()) return intent;  // 关于页只画/等 Esc；输入由 App 的 Esc 路由处理

    // F5：请求 App 重扫内容包（skin/sound/boot/font/shelf）；当前卡带与卡带脚本不重载
    if (input.pressed("f5")) intent.reload_content = true;

    // F3：打开存档管理（列表数据由 App 钩子注入；Esc 由 App 转到 to_shelf() 并 pop 回设置）
    if (input.pressed("f3")) {
        open_saves();
        return intent;
    }

    // F1：在设置里打开关于页（settings 栈上 push；Esc pop 回设置）
    if (input.pressed("f1")) {
        open_about();
        return intent;
    }

    const ui::Rect area = settings_area();
    const SettingsContext ctx = make_settings_context();

    // 搜索：/ 进入；编辑期间把本帧文本交给 settings_view 的纯函数。
    // 方向键/Enter 仍由组件处理，所以"过滤后上下选、Enter 改值"保持原语义。
    if (settings_search_.active) {
        if (!input.pressed("slash")) settings_search_apply_text(settings_search_, input.text());
    } else if (input.pressed("slash")) {
        settings_search_begin(settings_search_);
    }

    // 界面只声明"有哪些行、当前值是什么"；上下换焦点、左右改值、事件语义由组件层负责
    ui::Frame frame("shell.settings", ui_state_, ui_theme_, area, &input, ui::Keys::host());
    build_settings(frame.root(), ctx, area, &settings_search_);

    for (const ui::Event& event : frame.run()) {
        if (event.kind == ui::EventKind::cancelled) {
            if (settings_search_.active) {
                settings_search_clear(settings_search_);
            } else {
                pop_screen();
            }
            break;
        }
        if (event.kind != ui::EventKind::changed && event.kind != ui::EventKind::activated) continue;
        if (event.id.rfind("settings/", 0) != 0) continue;
        const SettingId id = setting_from_key(std::string_view(event.id).substr(9));
        if (id == SettingId::count) continue;
        if (event.kind == ui::EventKind::activated) {
            if (id == SettingId::back) {
                settings_search_clear(settings_search_);
                pop_screen();
            }
            continue;
        }

        const int step = event.delta;
        auto cycle = [](int index, int count, int by) {
            if (count <= 0) return 0;
            return ((index + by) % count + count) % count;
        };
        auto pick_next = [&](const std::vector<std::string>& names, int& index) {
            if (names.empty() || step == 0) return false;
            index = cycle(index, static_cast<int>(names.size()), step);
            return true;
        };

        switch (id) {
            case SettingId::theme:
                if (pick_next(skin_names_, skin_index_)) {
                    intent.skin_changed = true;
                    intent.skin_index = skin_index_;
                }
                break;
            case SettingId::font:
                if (pick_next(font_names_, font_index_)) {
                    intent.font_changed = true;
                    intent.font_index = font_index_;
                }
                break;
            case SettingId::font_size: {
                const int count = font_max_ - font_min_ + 1;
                if (count <= 0 || step == 0) break;
                int at = font_px_ >= font_min_ && font_px_ <= font_max_ ? font_px_ - font_min_ : 0;
                at = cycle(at, count, step);
                font_px_ = font_min_ + at;
                intent.font_size_changed = true;
                intent.font_size = font_px_;
                break;
            }
            case SettingId::scanlines:
                if (step != 0) {
                    crt_level_ = cycle(crt_level_, kCrtLevelCount, step);
                    intent.crt_changed = true;
                }
                break;
            case SettingId::fps: {
                if (step == 0) break;
                int at = 0;
                for (int i = 0; i < kFpsChoiceCount; ++i)
                    if (kFpsChoices[i] == fps_) at = i;
                fps_ = kFpsChoices[cycle(at, kFpsChoiceCount, step)];
                intent.fps_changed = true;
                break;
            }
            case SettingId::sound_pack:
                // 左右 = 换音效包（App 立即用新包试听）；确认 = 只试听当前包，不切换
                if (event.confirm) {
                    intent.preview_sound = true;
                } else if (pick_next(sound_names_, sound_index_)) {
                    intent.sound_changed = true;
                    intent.sound_index = sound_index_;
                }
                break;
            case SettingId::music_volume:
                if (event.confirm) break;
                music_volume_ = std::clamp(music_volume_ + step * kVolumeStep, 0, 100);
                intent.music_volume_changed = true;
                break;
            case SettingId::sfx_volume:
                if (event.confirm) break;
                sfx_volume_ = std::clamp(sfx_volume_ + step * kVolumeStep, 0, 100);
                intent.sfx_volume_changed = true;
                break;
            case SettingId::boot:
                if (pick_next(boot_names_, boot_index_)) {
                    intent.boot_changed = true;
                    intent.boot_index = boot_index_;
                }
                break;
            case SettingId::shelf_view: {
                const int count = 2 + static_cast<int>(shelf_options_.size());
                if (step == 0) break;
                shelf_index_ = cycle(shelf_index_, count, step);
                intent.shelf_style_changed = true;
                intent.shelf_index = shelf_index_;
                break;
            }
            case SettingId::language:
                if (step == 0) break;
                lang_ = lang_ == Lang::zh ? Lang::en : Lang::zh;  // 两选一，直接翻面
                intent.language_changed = true;
                break;
            default:
                break;
        }
    }

    // 焦点即光标：state.query.cursor 与"音效行试听"都读这一个值，不再各存一份
    const std::string& focused = frame.focused_id();
    if (focused.rfind("settings/", 0) == 0) {
        const int index = setting_item_index(setting_from_key(std::string_view(focused).substr(9)));
        if (index >= 0) settings_cursor_ = index;
    } else if (settings_search_.active) {
        settings_cursor_ = -1;  // 过滤到 0 项：没有行被选中，别让旧光标骗过"音效行试听"
    }
    return intent;
}

Shell::Intent Shell::update_tape(const Input& input) {
    Intent intent;
    const ui::Rect content = content_rect();
    // 切页与滚动在**建树前**生效：这一帧敲进来的字符要落到当前这一页上
    tape_.update(input);
    ui::Frame frame(kTapeScreen, ui_state_, ui_theme_, content, &input, ui::Keys::host());
    tape_.build(frame.root(), content, lang_, frame.field_text(tape::ScreenState::kFieldId));
    for (const ui::Event& event : frame.run()) {
        // 输入页的文本域提交 = 请求导入。查看页没有文本域，Enter 仍然什么都不做
        if (event.kind != ui::EventKind::submitted) continue;
        if (event.id != tape::ScreenState::kFieldId || event.text.empty()) continue;
        intent.tape_import = true;
        intent.tape_code = event.text;
    }
    return intent;
}

void Shell::build_paused_menu(ui::Node& root, const ui::Rect& area) const {
    const ui::Rect box = ui::Rect::centered(area, ShellLayout::kPauseW, ShellLayout::kPauseH);
    const std::pair<int, int> at = offset_in(area, box);
    ui::Node& dialog = root.add_box("paused/box", tr(lang_, Msg::pause_title));
    // 绝对定位节点的宽高按**整框**声明（含边框与内边距）；内边距再把列表摆到旧版面的位置
    dialog.props.absolute = true;
    dialog.props.x = at.first;
    dialog.props.y = at.second;
    dialog.props.width = box.w;
    dialog.props.height = box.h;
    dialog.props.padding = ui::Insets{kPausePadX, kPausePadY, kPausePadX, kPausePadY};
    dialog.props.border = ui::Border::single;
    dialog.props.opaque = true;
    dialog.props.gap = 0;

    ui::Node& menu = dialog.add_list(kPauseMenu, {tr(lang_, Msg::pause_resume),
                                                  tr(lang_, Msg::pause_tape),
                                                  tr(lang_, Msg::pause_eject)});
    menu.props.indent = 0;
    menu.props.text_gap = 1;
}

Shell::Intent Shell::update_paused(const Input& input) {
    Intent intent;
    const ui::Rect area = content_rect();
    // 上下移动、确认都由组件处理（焦点在列表上）；Esc = 继续，由 App 统一裁决
    ui::Frame frame(kPausedScreen, ui_state_, ui_theme_, area, &input, ui::Keys::host());
    build_paused_menu(frame.root(), area);

    for (const ui::Event& event : frame.run()) {
        if (event.kind != ui::EventKind::activated || event.id != kPauseMenu) continue;
        switch (event.index) {
            case 0: intent.resume = true; break;   // 继续游戏
            case 1:                                // 磁带码（App 据此填入本机的码）
                to_tape();
                intent.open_tape = true;
                break;
            default: intent.eject = true; break;   // 拔出卡带
        }
    }
    // 光标真源在组件里：读回给 cursor()，agent 读到的行号与画面高亮必须一致
    pause_cursor_ = widget_cursor(ui_state_, kPausedScreen, kPauseMenu);
    return intent;
}

void Shell::build_mods_dialog(ui::Node& root, const ui::Rect& area) const {
    const ui::Rect box = mods_box();
    const std::pair<int, int> at = offset_in(area, box);
    const int mods = static_cast<int>(mods_.size());
    const int items = mods + 1;                 // + 确认行（取消由 Esc 承担）
    const int visible = std::max(1, box.h - 4);  // 边框 + 上下各留一行

    ui::Node& dialog = root.add_box(kModsBox, tr(lang_, Msg::mods_title));
    dialog.props.absolute = true;
    dialog.props.x = at.first;
    dialog.props.y = at.second;
    dialog.props.width = box.w;
    dialog.props.height = box.h;
    dialog.props.padding = ui::Insets{0, kModsRowPadY, 0, kModsRowPadY};
    dialog.props.border = ui::Border::single;
    dialog.props.opaque = true;
    dialog.props.gap = 0;

    // 滚动窗口：让光标停在中间，首尾夹紧——公式与旧平滑滚动的**目标行**完全相同
    int first = 0;
    if (items > visible) first = std::clamp(mods_cursor_ - visible / 2, 0, items - visible);
    const int row_w = box.w - 2;  // 内容区宽（左右不留内边距）：行宽定死才能按列截断
    for (int index = first; index < first + visible && index < items; ++index) {
        if (index < mods) {
            const ModOption& mod = mods_[static_cast<size_t>(index)];
            const std::string& shown = lang_ == Lang::en ? mod.en : mod.zh;
            const bool on = index < static_cast<int>(mods_checked_.size()) && mods_checked_[index];
            ui::Node& row = dialog.add_checkbox(mods_row_id(index), shown.empty() ? mod.id : shown);
            row.props.width = row_w;
            row.props.indent = kModsIndent;
            row.props.text_gap = kModsTextGap;
            row.props.dim = !on;  // 未勾选 = 不生效：暗色，一眼能分辨（与旧版一致）
        } else {
            ui::Node& confirm = dialog.add_button(
                kModsConfirm, std::string("[ ") + tr(lang_, Msg::mods_confirm) + " ]");
            confirm.props.width = row_w;
            confirm.props.indent = kModsIndent;
            confirm.props.text_gap = kModsTextGap;
        }
    }
}

void Shell::sync_mods_checked(ui::Frame& frame) const {
    for (size_t i = 0; i < mods_.size(); ++i)
        frame.set_checked(mods_row_id(static_cast<int>(i)),
                          i < mods_checked_.size() && mods_checked_[i]);
}

Shell::Intent Shell::update_mods(const Input& input) {
    Intent intent;
    const int mods = static_cast<int>(mods_.size());
    const int items = mods + 1;  // 单列：N 个 mod 行 + 确认（取消由 Esc 承担）
    if (mods == 0) {             // 理论上不会（无 mod 打不开），兜底回架面
        pop_screen();
        return intent;
    }
    // 首尾循环（与旧版一致）。方向键由宿主处理：光标要在会重排的滚动窗口里循环
    if (input.pressed(Key::up))   mods_cursor_ = (mods_cursor_ + items - 1) % items;
    if (input.pressed(Key::down)) mods_cursor_ = (mods_cursor_ + 1) % items;

    const ui::Rect area = content_rect();
    ui::Frame frame(kModsScreen, ui_state_, ui_theme_, area, &input, mods_keys());
    build_mods_dialog(frame.root(), area);
    sync_mods_checked(frame);
    // 焦点只决定"哪一行显示光标/高亮"：A / 空格由组件翻成 changed / activated 事件
    ui_state_.screen(kModsScreen).focus =
        mods_cursor_ < mods ? mods_row_id(mods_cursor_) : std::string(kModsConfirm);

    for (const ui::Event& event : frame.run()) {
        int row = 0;
        if (event.kind == ui::EventKind::changed && mods_row_index(event.id, row)) {
            if (row >= 0 && row < static_cast<int>(mods_checked_.size()))
                mods_checked_[static_cast<size_t>(row)] = event.flag;
        } else if (event.kind == ui::EventKind::activated && event.id == kModsConfirm) {
            if (mods_changed()) {   // 没变就只关窗，不重启
                intent.mods_applied = true;
                // 按每个 mod 的 default_off 把新勾选态拆成两个列表：
                // 默认关的打开→mods_enabled；默认开的关闭→mods_disabled（其余都留在默认侧）
                for (size_t i = 0; i < mods_.size(); ++i) {
                    const ModOption& m = mods_[i];
                    const bool on = i < mods_checked_.size() && mods_checked_[i];
                    if (m.default_off) {
                        if (on) intent.mods_enabled.push_back(m.id);
                    } else if (!on) {
                        intent.mods_disabled.push_back(m.id);
                    }
                }
            }
            pop_screen();
        }
    }
    return intent;
}

// ---------------------------------------------------------------- 布局

ui::Rect Shell::content_rect() const { return phos::content_rect(skin_); }

ui::Rect Shell::settings_area() const {
    const ui::Rect content = content_rect();
    // 行区左缘对齐分区标题（content.x+4）、首行在标题栏与分隔线之下（content.y+8）；
    // 预览框绝对定位在底部六行，坐标与旧版逐格一致
    return ui::Rect{content.x + 4, content.y + ShellLayout::kContentTop * 2, content.w - 8,
                    content.h - ShellLayout::kContentTop * 2};
}

SettingsContext Shell::make_settings_context() const {
    SettingsContext ctx;
    ctx.skins = skin_names_;
    ctx.fonts = font_names_;
    ctx.boots = boot_names_;
    ctx.sounds = sound_names_;
    ctx.skin_index = skin_index_;
    ctx.font_index = font_index_;
    ctx.boot_index = boot_index_;
    ctx.sound_index = sound_index_;
    ctx.crt_level = crt_level_;
    ctx.fps = fps_;
    ctx.music_volume = music_volume_;
    ctx.sfx_volume = sfx_volume_;
    // 内容包显示名按**当前界面语言**解析：语言一切换，同一帧的设置行就跟着变
    ctx.shelves.clear();
    for (const ShelfOption& option : shelf_options_)
        ctx.shelves.push_back(lang_ == Lang::en ? option.en : option.zh);
    ctx.shelf_index = shelf_index_;
    ctx.font_px = font_px_;
    ctx.lang = lang_;
    ctx.theme = ui_theme_;
    return ctx;
}

ShelfView Shell::shelf_view(const std::vector<CartInfo>& shown, int cursor) const {
    // 搜索生效时不做滑动动效：那个动效状态是按**整表**下标攒的，过滤后下标含义变了，
    // 混用会让图标来回窜。瞬时定位更好——搜东西时没人想等动画
    const float position = shelf_search_.visible() ? static_cast<float>(cursor) : shelf_pos_;
    // 内置样式只区分 list / window；有画家 = 内容区由内容包接管（external 标记）
    const ShelfStyle style = shelf_index_ == 0 ? ShelfStyle::list : ShelfStyle::window;
    return ShelfView{&shown, style,         cursor, position,          lang_,
                     static_cast<bool>(shelf_painter_), ui_theme_};
}

// ---------------------------------------------------------------- 绘制

void Shell::draw_chassis(Screen& screen) const { draw_bezel(screen); }

void Shell::draw(Screen& screen) {
    draw_bezel(screen);
    switch (mode()) {
        case ShellMode::boot: draw_boot(screen); break;
        case ShellMode::shelf: draw_shelf(screen); break;
        case ShellMode::settings:
            if (saves_open()) {
                draw_saves(screen);
            } else if (about_open()) {
                draw_about(screen);
            } else {
                draw_settings(screen);
            }
            break;
        case ShellMode::paused: draw_paused(screen); break;
        case ShellMode::mods: draw_mods(screen); break;
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
        const Color color = scale_color(lamp.color, glow);
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

void Shell::draw_shelf(Screen& screen) {
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
    shelf::draw(screen, content, shelf_view(shown, shown_cursor), style_, shelf_painter_);

    if (shelf_search_.visible()) {
        // 浮窗外框仍用绘制原语：它的标题是**这道浮层**的一部分，这里保持逐字节不变
        const ui::Rect box = search_box(content);
        ui::fill(screen, box, U' ', style_.fg, style_.bg);
        ui::frame(screen, box, tr(lang_, Msg::shelf_search_title), style_);

        // 输入行是一个真正的文本域：查询串的真源仍在 ShelfSearch（它参与匹配与输入法判定），
        // 所以这里用"只排布/绘制"的帧，字符结算仍在 update_shelf 里——界面状态不存两份
        ui::Frame frame(kShelfScreen, ui_state_, ui_theme_, content, nullptr, ui::Keys::host());
        ui::Node& field = frame.root().add(ui::Kind::field, kShelfSearchField);
        field.props.absolute = true;
        field.props.x = box.x + 2 - content.x;
        field.props.y = box.y + 1 - content.y;
        field.props.width = box.w - 4;
        field.props.text = shelf_search_.editing() ? "_" : "";  // 空查询时的光标占位
        // 未输入时不抢焦点：否则已确认的搜索框会多挂一个光标，看起来像还在打字
        field.props.enabled = shelf_search_.editing();
        frame.set_field_text(kShelfSearchField, shelf_search_.query());
        frame.run();  // draw 路径只排布
        frame.paint(screen);
    }

    if (!shelf_search_.visible()) {
        // 有 mod 才追加 M 提示（没有 mod 时页脚与从前逐字节一致）
        std::string hints = tr(lang_, Msg::shelf_insert_hint);
        if (!mods_.empty()) hints += std::string("   ") + tr(lang_, Msg::mods_hint);
        draw_footer(screen, hints);
    } else if (matches.empty() && !carts_.empty())
        draw_footer(screen, tr(lang_, Msg::shelf_search_empty));
    else
        draw_footer(screen, tr(lang_, Msg::shelf_search_hint));
}

void Shell::draw_settings(Screen& screen) {
    draw_chrome(screen, tr(lang_, Msg::settings_title), "");

    const ui::Rect area = settings_area();
    ui::Frame frame("shell.settings", ui_state_, ui_theme_, area, nullptr, ui::Keys::host());
    build_settings(frame.root(), make_settings_context(), area, &settings_search_);
    frame.run();  // draw 路径只排布（输入在 update_settings 里已处理）
    frame.paint(screen);

    draw_footer(screen, tr(lang_, Msg::settings_footer));
}

void Shell::draw_saves(Screen& screen) {
    const bool en = lang_ == Lang::en;
    draw_chrome(screen, en ? "SAVES" : "存档管理", "");

    const ui::Rect area = content_rect();
    ui::Frame frame(save::ScreenState::kScreenId, ui_state_, ui_theme_, area, nullptr,
                    ui::Keys::host());
    saves_.build(frame.root(), area, lang_);
    frame.run();  // draw 路径只排布（输入在 update_saves 里已处理）
    frame.paint(screen);

    draw_footer(screen, en ? "Enter view code   Esc back to settings"
                           : "Enter 查看导出码   Esc 返回设置");
}

void Shell::draw_about(Screen& screen) {
    const bool en = lang_ == Lang::en;
    draw_chrome(screen, en ? "ABOUT" : "关于", "");

    const ui::Rect area = settings_area();
    ui::Frame frame("shell.about", ui_state_, ui_theme_, area, nullptr, ui::Keys::host());
    build_about(frame.root(), lang_, area);
    frame.run();  // 关于页无输入：Esc 由 App 转发到 to_shelf()（pop 回设置）
    frame.paint(screen);

    draw_footer(screen, en ? "Esc back to settings" : "Esc 返回设置");
}

void Shell::draw_paused(Screen& screen) {
    const ui::Rect area = content_rect();
    ui::Frame frame(kPausedScreen, ui_state_, ui_theme_, area, nullptr, ui::Keys::host());
    build_paused_menu(frame.root(), area);
    frame.run();  // draw 路径只排布（输入在 update_paused 里已处理）
    frame.paint(screen);
    draw_footer(screen, tr(lang_, Msg::pause_footer));
}

void Shell::draw_mods(Screen& screen) {
    draw_chrome(screen, tr(lang_, Msg::mods_title), "");
    const ui::Rect area = content_rect();
    ui::Frame frame(kModsScreen, ui_state_, ui_theme_, area, nullptr);
    build_mods_dialog(frame.root(), area);
    sync_mods_checked(frame);
    frame.run();
    frame.paint(screen);
    draw_footer(screen, tr(lang_, Msg::mods_footer));
}

void Shell::draw_tape(Screen& screen) {
    // 标题栏与页脚是全机统一的，所以由外壳画；页面文案编号由界面模块报出——
    // 模块不碰语言，它只说自己"现在是哪一页、页脚该提示什么"
    draw_chrome(screen, tr(lang_, Msg::tape_title), tr(lang_, tape_.page_hint()));
    const ui::Rect content = content_rect();
    ui::Frame frame(kTapeScreen, ui_state_, ui_theme_, content, nullptr, ui::Keys::host());
    tape_.build(frame.root(), content, lang_, frame.field_text(tape::ScreenState::kFieldId));
    frame.run();  // draw 路径只排布（输入在 update_tape 里已处理）
    frame.paint(screen);
    draw_footer(screen, tr(lang_, tape_.footer_hint()));
}

void Shell::draw_error(Screen& screen) {
    const ui::Rect content = content_rect();

    ui::Frame frame("shell.error", ui_state_, ui_theme_, content, nullptr, ui::Keys::host());
    ui::Node& root = frame.root();
    root.props.opaque = true;
    root.props.has_bg = true;
    root.props.bg = ui_theme_.bg;
    root.props.has_fg = true;
    root.props.fg = ui_theme_.text;

    // 错误屏是"固定版面"：坐标与旧实现逐格一致，故意用绝对定位而不是流式布局
    auto place = [&root](ui::Kind kind, std::string id, int x, int y, int w) -> ui::Node& {
        ui::Node& node = root.add(kind, std::move(id));
        node.props.absolute = true;
        node.props.x = x;
        node.props.y = y;
        node.props.width = w;
        return node;
    };

    ui::Node& title = place(ui::Kind::text, "error/title", 2, 1, content.w - 2);
    title.props.text = tr(lang_, Msg::error_title);
    title.props.danger = true;

    ui::Node& rule = place(ui::Kind::divider, "error/rule", 0, 2, content.w);
    rule.props.has_fg = true;
    rule.props.fg = ui_theme_.text_dim;

    ui::Node& body = place(ui::Kind::text, "error/body", 4, 6, content.w - 4);
    body.props.text = tr(lang_, Msg::error_body);

    // 卡带给出的错误原文：折行 + 最多 12 行，超出的部分不再画（与旧 text_block 一致）
    ui::Node& message = place(ui::Kind::text, "error/message", 4, 8, 70);
    message.props.text = error_message_;
    message.props.overflow = ui::Overflow::wrap;
    message.props.lines = 12;

    ui::Node& footer = place(ui::Kind::text, "error/footer", 4, content.h - 3, content.w - 4);
    footer.props.text = tr(lang_, Msg::error_footer);
    footer.props.dim = true;

    frame.run();
    frame.paint(screen);
}

} // namespace phos
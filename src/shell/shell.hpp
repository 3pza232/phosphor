#pragma once

#include "cart/cartridge.hpp"
#include "shell/messages.hpp"
#include "core/crt.hpp"
#include "core/defaults.hpp"
#include "core/input.hpp"
#include "core/screen.hpp"
#include "core/skin.hpp"
#include "core/ui.hpp"
#include "shell/controls_view.hpp"
#include "shell/save_view.hpp"
#include "shell/settings_view.hpp"
#include "shell/shelf_search.hpp"
#include "shell/shelf_view.hpp"
#include "shell/tape_view.hpp"
#include "ui/frame.hpp"
#include "ui/screen_stack.hpp"
#include "ui/theme.hpp"

#include <functional>
#include <map>
#include <string>
#include <vector>

namespace phos {

/// 主机外壳模式（游戏运行时不归 shell 管）
enum class ShellMode {
    boot,
    shelf,
    settings,
    paused,
    mods,        // Mod 管理器：开关覆盖层 Mod（改后重启生效）
    tape,        // 磁带码：查看本机存档的码 / 输入别人的码
    cart_error
};

/// 卡带架样式候选项里的一个内容包：本地化显示名 + 顶层声明的二维列数。
/// 内置 LIST/WINDOW 不是包，不在这里——Shell 的候选项 = [LIST, WINDOW, ...这些]。
/// `zh`/`en` 由调用方补好文件夹名兜底，故按界面语言直接取用即可，不会空
struct ShelfOption {
    std::string zh;
    std::string en;
    int cols = 0;  // 0 = 包未声明列数：上下键按一维（∓1）处理
};

/// MODS 管理器里的一条：`id` 是启用集比较与写盘用的 mod 名，`zh`/`en` 是显示名。
/// `default_off` 决定写盘时落进 `mods_enabled` 还是 `mods_disabled`；`enabled` 是打开
/// 管理器时的有效启用态（勾选初值）。显示名由调用方（pack 的 `scan_mods`）补好兜底
struct ModOption {
    std::string id;
    std::string zh;
    std::string en;
    bool default_off = false;
    bool enabled = true;
};

/// 外壳界面：机身装饰 + 开机动画 + 卡带架 + 设置 + 暂停 + 错误画面。
/// 界面绘制全部经由 core/ui 原语，与卡带可用的 phos.ui 同源，风格天然统一。
class Shell {
public:
    /// 用户意图（由 App 执行）
    struct Intent {
        bool insert_cart = false;
        int cart_index = -1;
        bool resume = false;
        bool eject = false;
        bool font_changed = false;
        int font_index = -1;
        bool font_size_changed = false;
        int font_size = 0;  // 0 = 跟随字体方案；否则为用户选定的字号
        bool skin_changed = false;
        int skin_index = -1;
        bool boot_changed = false;
        int boot_index = -1;
        bool sound_changed = false;
        int sound_index = -1;
        bool shelf_style_changed = false;
        int shelf_index = -1;  // 卡带架样式候选项下标：0=list、1=window、2+i=第 i 个 shelf 包
        bool crt_changed = false;
        bool fps_changed = false;   // 画面刷新率已改（节流在主循环里，界面自己不改硬件）
        bool music_volume_changed = false;
        bool sfx_volume_changed = false;
        bool open_tape = false;    // 进入磁带码界面（App 需填入当前卡带的码）
        bool tape_import = false;  // 请求导入磁带码
        std::string tape_code;     // 待导入的码（十六进制）
        bool language_changed = false;  // 界面语言已切换（App 读 shell_.language() 落盘）
        bool preview_sound = false;     // 音效行按 Enter：试听**当前**音效包（不切换）
        /// 设置屏 F5：请求 App 重新扫描内容包并重新应用当前选择（当前卡带不重载）
        bool reload_content = false;
        /// MODS 浮窗"确认"且启用集**确有变化**：App 写盘并重启。没变时这里恒为 false
        /// （关掉又开回算没变——用集合语义比较，不看按键历史）
        bool mods_applied = false;
        /// 确认后按各 mod 的 default_off 拆成的两个列表：默认开的被关掉落 mods_disabled，
        /// 默认关的被打开落 mods_enabled（不在表里 = 回到各自默认）
        std::vector<std::string> mods_disabled;
        std::vector<std::string> mods_enabled;
    };

    /// 换皮肤（同时重建几何：格子尺寸与外壳尺寸随主题变）
    void set_skin(const Skin& skin);
    /// 告知卡带架上有哪些卡带：架面显示、插卡、拔卡都按这份列表
    void set_carts(std::vector<CartInfo> carts);
    /// 架子上的卡带（玩家眼里的顺序：最近打开优先）。控制通道据此暴露 `shelf`，
    /// agent 才能"数到第几张再插卡"——`cursor` 就是它的下标
    const std::vector<CartInfo>& carts() const { return carts_; }
    /// 告知可选字体方案名与当前项
    void set_fonts(std::vector<std::string> names, int active);
    /// 告知当前生效字号（= 单元格像素边长）与**方案声明的可调范围**。改值经 Intent 交回主机落盘
    void set_font_size(int px, int min_px, int max_px);
    int font_px() const { return font_px_; }
    /// 告知可选皮肤名与当前项
    void set_skins(std::vector<std::string> names, int active);
    /// 告知可选启动动画名与当前项
    void set_boots(std::vector<std::string> names, int active);
    /// 告知可选音效包名与当前项
    void set_sounds(std::vector<std::string> names, int active);
    /// 卡带插入后指示灯转为常亮（仪式感：机器"醒了"）
    void set_lamps_solid(bool on) { lamps_solid_ = on; }
    /// 磁带码导入的结果。语义定义在 `tape::ScreenState` 里：界面只收语义、自己按语言取词
    /// （若让 App 直接塞中文串，界面就没有语言可切，文案属于界面层）
    using TapeResult = tape::ScreenState::Result;

    /// 磁带码界面的数据：卡带名、码本体、该卡带是否有存档（由 App 在进入时填入）
    void set_tape(std::string cart_name, std::string code, bool available);
    /// 存档管理屏的数据钩子（App 注入）：列表快照 / 删除 / 读取导出码。
    /// Shell 只做视图与状态，不直接碰文件系统或 SaveStore 的读写逻辑
    using SaveListFn = std::function<std::vector<save::Entry>()>;
    using SaveDeleteFn = std::function<bool(const save::Entry&)>;
    using SaveCodeFn =
        std::function<bool(const save::Entry&, std::string& cart_name, std::string& code)>;
    void set_save_hooks(SaveListFn list, SaveDeleteFn remove, SaveCodeFn code);
    /// 按键重绑定屏的钩子（App 注入）：映射快照 / 保存映射 / 开始捕获 / 取消捕获。
    /// 真实物理键捕获在 Window 层（key_callback），Shell 只做视图与冲突提示
    using ControlsListFn = std::function<std::map<std::string, std::string>()>;
    using ControlsSaveFn = std::function<void(const std::map<std::string, std::string>&)>;
    using CaptureFn = std::function<void()>;
    void set_control_hooks(ControlsListFn list, ControlsSaveFn save, CaptureFn start, CaptureFn cancel);
    /// App 轮询到 Window 捕获的物理键后回调（非捕获态忽略）
    void on_key_captured(const std::string& physical);
    /// 磁带码界面的结果行（导入成功 / 码无效…），由 App 回报
    void set_tape_result(TapeResult result) { tape_.set_result(result); }
    /// 切到磁带码界面（从暂停菜单进入）
    void to_tape();
    /// 告知可选的卡带架样式包与当前项。候选项是 `[LIST, WINDOW, <包…>]`，
    /// `active` = 0（list）/ 1（window）/ 2+i（第 i 个包）
    void set_shelves(std::vector<ShelfOption> options, int active);
    /// 告知覆盖层 Mod 清单（含各自的本地化显示名、default_off 与有效启用态）：
    /// 架面只在有 mod 时显示 M 提示、才响应 M 键
    void set_mods(std::vector<ModOption> mods);
    /// 设置卡带架内容区的绘制回调。非空 = 内容区由内容包接管（ShelfView 标记 external）；
    /// 清空即回退内置样式 —— 包加载失败时 App 就是这样兜底的
    void set_shelf_painter(shelf::Painter painter) { shelf_painter_ = std::move(painter); }
    /// 当前菜单光标位置（-1 = 当前模式没有"可选项列表"）。供 agent 驱动界面时读回，
    /// 免得靠"按几下"去猜——菜单项一增减，猜的次数就全错。
    int cursor() const {
        switch (mode()) {
            case ShellMode::shelf: return shelf_cursor_;
            case ShellMode::paused: return pause_cursor_;
            case ShellMode::settings:
                return controls_open() ? controls_.selected()
                                       : (saves_open() ? saves_.selected() : settings_cursor_);
            case ShellMode::mods: return mods_cursor_;
            default: return -1;
        }
    }
    /// 界面语言（主机界面文案；切换经 Intent 交回 App 落盘）
    void set_language(Lang lang) { lang_ = lang; }
    Lang language() const { return lang_; }
    /// 设置界面显示的扫描线档位（改值经 Intent 交回主机，界面自己不改硬件）
    void set_crt_level(int level);
    /// 设置界面显示的画面刷新率（改值同样经 Intent 交回主机：节流发生在主循环里）
    void set_fps(int fps);
    int fps() const { return fps_; }
    /// 设置界面显示的音乐音量（0~100）
    void set_music_volume(int volume);
    /// 设置界面显示的音效音量（0~100）
    void set_sfx_volume(int volume);
    /// 开机动画是否由内容包（而非内置）提供：决定自检屏的文案与时长来源
    void set_external_boot(bool on) { external_boot_ = on; }

    /// 切到错误屏并显示信息（卡带装载失败等），玩家按键后返回卡带架
    void show_error(const std::string& message);
    /// 切到开机自检屏
    void to_boot();
    /// 推进内置自检的动画时钟。开机由 App 驱动（App::Mode::boot），期间 Shell::update
    /// 不会被调用 —— 时钟只能由 App 的 tick_boot 代为推进，否则自检永远停在第一行
    void advance_boot(float dt) { boot_time_ += dt; }
    /// 切到卡带架
    void to_shelf();
    /// 打开设置界面（主机保留键 F2，由 App 转发）
    void open_settings();
    /// 切到暂停菜单（游戏画面由卡带自己保持）
    void to_paused();

    /// 设置光标是否停在"音效包"那一行：该行的声音由 App 自己处理
    /// （切换时放**新**音效包、Enter 试听当前），以免先响一次旧包的键音
    bool settings_on_sound_row() const;

    ShellMode mode() const;
    /// 当前卡带架样式候选项下标（0=list、1=window、2+i=第 i 个包）
    int shelf_index() const { return shelf_index_; }
    /// 当前主题（外壳）：转场特效等系统绘制取它的配色
    const Skin& skin() const { return skin_; }
    int crt_level() const { return crt_level_; }
    int music_volume() const { return music_volume_; }
    int sfx_volume() const { return sfx_volume_; }

    /// 卡带架搜索的只读状态：架面绘制与 App 的 Esc 路由都要看它
    const ShelfSearch& shelf_search() const { return shelf_search_; }
    /// 清空查询串并收起搜索框（Esc 在输入框内的语义，见 App::handle_escape）
    void cancel_shelf_search() { shelf_search_.cancel(); }

    std::string cart_path_at(int index) const;
    /// 卡带 id（"最近打开"记录就按它匹配；坏卡带的 id 可能为空）
    std::string cart_id_at(int index) const;
    /// 把架子光标移到指定 id 的卡带上（找不到就保持原位）
    void focus_cart(const std::string& id);

    Intent update(const Input& input, float dt);
    void draw(Screen& screen);
    void draw_chassis(Screen& screen) const;

private:
    // 布局常量见 shell/layout.hpp（ShellLayout）：外壳与各屏幕模块共用同一套边距

    /// 屏栈：shelf/paused 是根（reset 进栈），settings/mods/tape/cart_error 是叠在上面的浮层。
    /// boot→shelf 不是"返回"，用 reset；App 的 playing 不算 shell 屏，暂停时 reset(paused)。
    void push_screen(ShellMode mode, bool modal = false);
    void pop_screen();
    void reset_screen(ShellMode mode, bool modal = false);
    /// 关于页：settings 栈上的普通浮层（push/pop，不 reset）；ShellMode 仍映射为 settings，
    /// 这样 App 的 Esc 路由（to_shelf）不必改就能"第一次返回设置"
    void open_about();
    bool about_open() const;

    Intent update_shelf(const Input& input);
    Intent update_settings(const Input& input);
    /// 存档管理浮层：settings 栈上的普通浮层（Esc 由 App 转发到 to_shelf，先 pop 回设置）
    bool saves_open() const;
    void open_saves();
    Intent update_saves(const Input& input);
    /// 按键重绑定浮层：动作列表 + 捕获下一个物理键（Esc 取消捕获/返回设置）
    bool controls_open() const;
    void open_controls();
    Intent update_controls(const Input& input);
    Intent update_paused(const Input& input);
    Intent update_mods(const Input& input);
    Intent update_tape(const Input& input);

    /// 打开 MODS 浮窗（快照当前启用集）；仅在已有 mod 时有意义
    void open_mods();
    /// 当前勾选状态推出的**有效启用集**（勾上的即生效）
    std::vector<std::string> mods_enabled_now() const;
    /// 启用集是否相对打开时的快照有变化（**集合语义**：关掉又开回 = 没变）
    bool mods_changed() const;
    /// MODS 浮窗矩形（居中）：输入（滚动视口）与绘制共用同一份布局
    ui::Rect mods_box() const;
    /// 暂停菜单的元素树：居中浮窗 + 列表（**焦点在列表上**）。
    /// 光标存在组件的 ScreenState 里，Shell 只把最后一行读回给 agent 观测
    void build_paused_menu(ui::Node& root, const ui::Rect& area) const;
    /// MODS 浮窗的元素树：N 个勾选行 + 确认行。勾选态的**真源仍是 mods_checked_**，
    /// 组件每帧经 sync_mods_checked 同步，切换事件再写回来
    void build_mods_dialog(ui::Node& root, const ui::Rect& area) const;
    void sync_mods_checked(ui::Frame& frame) const;

    ui::Rect content_rect() const;
    /// 设置屏的可用区域（行区 + 底部预览框的锚点）
    ui::Rect settings_area() const;
    SettingsContext make_settings_context() const;
    void draw_bezel(Screen& screen) const;
    void draw_boot(Screen& screen) const;
    void draw_shelf(Screen& screen);
    void draw_settings(Screen& screen);
    void draw_saves(Screen& screen);
    void draw_controls(Screen& screen);
    void draw_about(Screen& screen);
    void draw_paused(Screen& screen);
    /// 磁带码界面（两态渲染见 shell/tape_view.cpp）
    void draw_tape(Screen& screen);
    void draw_error(Screen& screen);
    void draw_mods(Screen& screen);
    void draw_chrome(Screen& screen, const std::string& title,
                     const std::string& right_text) const;
    void draw_footer(Screen& screen, const std::string& hints) const;
    /// 搜索命中的卡带下标（查询串为空即全部）。架面绘制与光标移动共用同一份判据，
    /// 两处各算一次就会出现"能选到但看不见"这类错位
    std::vector<int> shelf_matches() const { return shelf_search_.match(carts_); }
    /// 把光标收进命中集：查询串一变，原光标就可能不在结果里了。不收的后果很具体——
    /// 画面上高亮着第一条（视图找不到光标就退回第一条），而 Enter 插进去的却是旧光标那张
    void shelf_sync_cursor();
    /// 卡带架视图（渲染逻辑见 shell/shelf_view.cpp）。传的是**过滤后**的那一串：
    /// 视图不必知道有搜索这回事，它只要一串卡带与一个光标
    ShelfView shelf_view(const std::vector<CartInfo>& shown, int cursor) const;

    Skin skin_;
    ui::Style style_;
    /// UI 组件库的主题与跨帧状态（焦点/滚动/文本域值）。画布变了只换 token，控件代码不动
    ui::Theme ui_theme_;
    ui::State ui_state_;
    ui::ScreenStack screens_{"boot"};
    float time_ = 0.0f;
    float boot_time_ = 0.0f;
    bool external_boot_ = false;

    std::vector<CartInfo> carts_;
    int shelf_cursor_ = 0;
    float shelf_pos_ = 0.0f;
    /// 卡带架样式候选项 `[LIST, WINDOW, <shelf 包…>]` 与当前下标。
    /// 默认 1 = window（与出厂配置一致）
    std::vector<ShelfOption> shelf_options_;
    int shelf_index_ = 1;
    /// 当前选中包声明的列数（<2 的内置样式返回 0）。供上下键逐行移动
    int shelf_cols() const {
        return shelf_index_ >= 2 ? shelf_options_[static_cast<size_t>(shelf_index_ - 2)].cols : 0;
    }
    /// 内容区绘制回调（内容包接管时非空；见 shelf::Painter）
    shelf::Painter shelf_painter_;
    ShelfSearch shelf_search_;
    int settings_cursor_ = 0;
    /// 设置搜索态：查询缓冲/过滤是 settings_view 的纯函数，Shell 只负责把输入转过去
    SettingsSearch settings_search_;
    int fps_ = kDefaultFps;
    /// 暂停菜单光标（组件里那份的镜像，供 cursor() 观测；真源在组件的 ScreenState）
    int pause_cursor_ = 0;

    /// 覆盖层 Mod 清单（全部，含未启用的；带各自显示名与 default_off）与编辑/快照态
    std::vector<ModOption> mods_;
    int mods_cursor_ = 0;              // 单列光标：N 个 mod 行 + 确认（Esc 即取消）
    std::vector<bool> mods_checked_;   // 编辑态勾选 = 有效启用态（下标与 mods_ 对齐）
    std::vector<std::string> mods_enabled_snapshot_;  // 打开时的有效启用集（比较用）

    std::vector<std::string> skin_names_;
    int skin_index_ = 0;
    std::vector<std::string> boot_names_;
    int boot_index_ = 0;
    std::vector<std::string> sound_names_;
    int sound_index_ = 0;
    std::vector<std::string> font_names_;
    int font_index_ = 0;
    int font_px_ = kDefaultFontPx;  // 当前生效字号（= 单元格像素边长）
    int font_min_ = kMinFontPx;     // 可调范围下限（方案声明）
    int font_max_ = kMaxFontPx;     // 可调范围上限（方案声明；Mod 可抬高）
    bool lamps_solid_ = false;

    int crt_level_ = kDefaultCrtLevel;
    int music_volume_ = kDefaultMusicVolume;
    int sfx_volume_ = kDefaultSfxVolume;

    // 磁带码界面：状态、输入与绘制都在 shell/tape_view.cpp，外壳只负责转达
    tape::ScreenState tape_;
    /// 存档管理屏：视图/选中/确认在 shell/save_view.cpp；数据由 App 的钩子注入
    save::ScreenState saves_;
    SaveListFn save_list_;
    SaveDeleteFn save_delete_;
    SaveCodeFn save_code_;
    /// 磁带码是从存档管理里打开的：Esc 关掉磁带码时要回存档列表，而不是暂停菜单
    bool tape_over_saves_ = false;
    /// 按键重绑定屏：动作列表/捕获/冲突提示在 shell/controls_view.cpp；
    /// 映射保存与捕获开关由 App 钩子注入（Window 的 key_callback 真正拦截按键）
    controls::ScreenState controls_;
    ControlsListFn control_list_;
    ControlsSaveFn control_save_;
    CaptureFn control_capture_start_;
    CaptureFn control_capture_cancel_;

    Lang lang_ = Lang::zh;  // 界面语言（默认中文，App 启动时按配置设定）

    std::string error_message_;
};

} // namespace phos
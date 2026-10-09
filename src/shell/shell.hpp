#pragma once

#include "cart/cartridge.hpp"
#include "shell/messages.hpp"
#include "core/crt.hpp"
#include "core/defaults.hpp"
#include "core/input.hpp"
#include "core/screen.hpp"
#include "core/skin.hpp"
#include "core/ui.hpp"
#include "shell/shelf_view.hpp"
#include "shell/tape_view.hpp"

#include <string>
#include <vector>

namespace phos {

/// 主机外壳模式（游戏运行时不归 shell 管）
enum class ShellMode {
    boot,
    shelf,
    settings,
    paused,
    tape,        // 磁带码：查看本机存档的码 / 输入别人的码
    cart_error
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
        bool filter_changed = false;
        int filter_index = -1;
        bool font_changed = false;
        int font_index = -1;
        bool skin_changed = false;
        int skin_index = -1;
        bool boot_changed = false;
        int boot_index = -1;
        bool sound_changed = false;
        int sound_index = -1;
        bool shelf_style_changed = false;
        bool crt_changed = false;
        bool music_volume_changed = false;
        bool sfx_volume_changed = false;
        bool open_tape = false;    // 进入磁带码界面（App 需填入当前卡带的码）
        bool tape_import = false;  // 请求导入磁带码
        std::string tape_code;     // 待导入的码（十六进制）
        bool language_changed = false;  // 界面语言已切换（App 读 shell_.language() 落盘）
    };

    /// 换皮肤（同时重建几何：格子尺寸与外壳尺寸随主题变）
    void set_skin(const Skin& skin);
    /// 告知卡带架上有哪些卡带：架面显示、插卡、拔卡都按这份列表
    void set_carts(std::vector<CartInfo> carts);
    /// 告知可选滤镜名与当前项（设置界面据此显示与翻页）
    void set_filters(std::vector<std::string> names, int active);
    /// 告知可选字体方案名与当前项
    void set_fonts(std::vector<std::string> names, int active);
    /// 告知可选皮肤名与当前项
    void set_skins(std::vector<std::string> names, int active);
    /// 告知可选启动动画名与当前项
    void set_boots(std::vector<std::string> names, int active);
    /// 告知可选音效包名与当前项
    void set_sounds(std::vector<std::string> names, int active);
    /// 卡带插入后指示灯转为常亮（仪式感：机器"醒了"）
    void set_lamps_solid(bool on) { lamps_solid_ = on; }
    /// 磁带码导入的结果。语义定义在 `tape::ScreenState` 里（界面只收语义、自己按语言
    /// 取词——若让 App 直接塞中文串，界面就没有语言可切，文案属于界面层）。
    /// 这里留个别名，App 既有的 `Shell::TapeResult::ok` 写法不必改
    using TapeResult = tape::ScreenState::Result;

    /// 磁带码界面的数据：卡带名、码本体、该卡带是否有存档（由 App 在进入时填入）
    void set_tape(std::string cart_name, std::string code, bool available);
    /// 磁带码界面的结果行（导入成功 / 码无效…），由 App 回报
    void set_tape_result(TapeResult result) { tape_.set_result(result); }
    /// 切到磁带码界面（从暂停菜单进入）
    void to_tape();
    /// 卡带架样式：列表 / 橱窗
    void set_shelf_style(ShelfStyle style);
    /// 当前菜单光标位置（-1 = 当前模式没有"可选项列表"）。供 agent 驱动界面时读回，
    /// 免得靠"按几下"去猜——菜单项一增减，猜的次数就全错。
    int cursor() const {
        switch (mode_) {
            case ShellMode::shelf: return shelf_cursor_;
            case ShellMode::paused: return pause_cursor_;
            case ShellMode::settings: return settings_cursor_;
            default: return -1;
        }
    }
    /// 界面语言（主机界面文案；切换经 Intent 交回 App 落盘）
    void set_language(Lang lang) { lang_ = lang; }
    Lang language() const { return lang_; }
    /// 设置界面显示的扫描线档位（改值经 Intent 交回主机，界面自己不改硬件）
    void set_crt_level(int level);
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
    /// 切到卡带架
    void to_shelf();
    /// 打开设置界面（主机保留键 F2，由 App 转发）
    void open_settings();
    /// 切到暂停菜单（游戏画面由卡带自己保持）
    void to_paused();

    ShellMode mode() const { return mode_; }
    ShelfStyle shelf_style() const { return shelf_style_; }
    int crt_level() const { return crt_level_; }
    int music_volume() const { return music_volume_; }
    int sfx_volume() const { return sfx_volume_; }

    std::string cart_path_at(int index) const;

    Intent update(const Input& input, float dt);
    void draw(Screen& screen) const;
    void draw_chassis(Screen& screen) const;

private:
    // 布局常量见 shell/layout.hpp（ShellLayout）：外壳与各屏幕模块共用同一套边距，
    // 谁也不许自己另写一份——那样迟早会出现"标题贴着边框"这类走样

    Intent update_shelf(const Input& input);
    Intent update_settings(const Input& input);
    Intent update_paused(const Input& input);
    Intent update_tape(const Input& input);

    ui::Rect content_rect() const;
    void draw_bezel(Screen& screen) const;
    void draw_boot(Screen& screen) const;
    void draw_shelf(Screen& screen) const;
    void draw_settings(Screen& screen) const;
    void draw_paused(Screen& screen) const;
    /// 磁带码界面（两态渲染见 shell/tape_view.cpp）
    void draw_tape(Screen& screen) const;
    void draw_error(Screen& screen) const;
    void draw_chrome(Screen& screen, const std::string& title,
                     const std::string& right_text) const;
    void draw_footer(Screen& screen, const std::string& hints) const;
    /// 卡带架视图（渲染逻辑见 shell/shelf_view.cpp）
    ShelfView shelf_view() const;

    Skin skin_;
    ui::Style style_;
    ShellMode mode_ = ShellMode::boot;
    float time_ = 0.0f;
    float boot_time_ = 0.0f;
    bool external_boot_ = false;

    std::vector<CartInfo> carts_;
    int shelf_cursor_ = 0;
    float shelf_pos_ = 0.0f;
    ShelfStyle shelf_style_ = ShelfStyle::window;
    int settings_cursor_ = 0;
    int pause_cursor_ = 0;

    std::vector<std::string> filter_names_;
    int filter_index_ = 0;
    std::vector<std::string> skin_names_;
    int skin_index_ = 0;
    std::vector<std::string> boot_names_;
    int boot_index_ = 0;
    std::vector<std::string> sound_names_;
    int sound_index_ = 0;
    std::vector<std::string> font_names_;
    int font_index_ = 0;
    bool lamps_solid_ = false;

    int crt_level_ = kDefaultCrtLevel;
    int music_volume_ = kDefaultMusicVolume;
    int sfx_volume_ = kDefaultSfxVolume;

    // 磁带码界面：状态、输入与绘制都在 shell/tape_view.cpp，外壳只负责转达
    tape::ScreenState tape_;

    Lang lang_ = Lang::zh;  // 界面语言（默认中文，App 启动时按配置设定）

    std::string error_message_;
};

} // namespace phos

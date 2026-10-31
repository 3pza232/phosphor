#pragma once

#include "core/input.hpp"

#include <map>
#include <memory>
#include <set>
#include <string>

struct GLFWwindow;

namespace phos {

/// 窗口事件出口：物理输入经此流向主机各处
struct WindowHandlers {
    Input* input;          // 虚拟手柄输入注入
    bool* escape_flag;     // Esc 按下置位（主机保留键，App 按模式解释）
    bool* settings_flag;   // F2 按下置位（主机保留键：打开设置）
    bool* screenshot_flag; // F12 按下置位（主机保留键：保存当前画面 PNG）
    bool* console_flag;    // ` 键按下置位（调试台开关）
    bool* input_block;     // true 时物理输入不注入游戏（调试台打开期间）
    bool* capture_escape;  // true 时卡带接管 Esc：Esc 作为普通键注入，不再触发主机暂停
    /// --- 手柄/键盘共存辅助（Window 内部回填，调用方留空即可） ---
    /// 键盘当前按下的虚拟键：手柄松开同名键时据此判断是否该真正释放
    std::set<std::string>* keyboard_down = nullptr;
    /// 手柄当前按下的虚拟键（key_callback 只读）：键盘松开时若手柄仍按着则跳过释放
    std::set<std::string>* gamepad_down = nullptr;
    /// --- 输入重绑定 / 捕获（App 持有；Window 只读映射、回填捕获结果） ---
    /// 物理键名 → 虚拟键名；nullptr 或空表 = 恒等映射（旧行为）
    const std::map<std::string, std::string>* input_bindings = nullptr;
    /// true 时下一个普通物理键只交给 App，不注入游戏（设置里的重绑定捕获）
    bool* capture_next_key = nullptr;
    /// 捕获到的物理键名（Window 写入，App 轮询后清空）；capture_next_key 同时被置回 false
    std::string* captured_physical_key = nullptr;
};

/// GLFW 窗口封装（RAII）。OS 窗口与物理输入的唯一聚集地。
class Window {
public:
    /// 失败时返回空 Window（valid() == false）并填充 err
    static Window create(int width, int height, const std::string& title,
                         const WindowHandlers& handlers, std::string& err);
    ~Window();
    Window(const Window&) = delete;
    Window& operator=(const Window&) = delete;
    Window(Window&& other) noexcept;
    Window& operator=(Window&& other) noexcept;

    bool valid() const { return window_ != nullptr; }
    bool should_close() const;
    /// 调整窗口尺寸（切换游戏机主题时几何变化）
    void resize(int width, int height) const;
    /// 帧缓冲尺寸（**物理像素**）。高 DPI / 分数缩放下会大于窗口的逻辑尺寸——
    /// 渲染与读回必须用它，否则画面只填到左下角一块（见 Renderer::set_framebuffer_size）
    int framebuffer_width() const;
    int framebuffer_height() const;

    /// 开关本窗口的**系统输入法**：只让声明了 `ime = true` 的输入框收中文。
    /// 仅 Windows 实现（`ImmAssociateContext`）；其它平台是空操作。幂等，可按帧调
    void set_ime_enabled(bool enabled);
    /// 改写标题栏文字（agent 接管时用于提示"谁在操作"）
    void set_title(const std::string& title) const;
    /// 轮询窗口事件并同步手柄状态（键盘/手柄任一来源按下即按下）
    void poll_events();
    void swap_buffers() const;
    void make_context_current() const;

    GLFWwindow* handle() const { return window_; }

private:
    Window() = default;
    GLFWwindow* window_ = nullptr;
    /// 本窗口的回调上下文：存在 user pointer 里，多个窗口各一份（不再用文件级全局）
    std::unique_ptr<WindowHandlers> handlers_;
    /// 系统给的输入法上下文（Windows 的 HIMC，用 void* 存以保持头文件平台无关）；
    /// 关输入法前记住它，开回来时原样还给它
    void* ime_context_ = nullptr;

    /// 本帧由键盘/手柄分别按下的虚拟键（共存判断用；避免松开一边把另一边还按着的键清掉）
    std::set<std::string> keyboard_keys_;
    std::set<std::string> gamepad_keys_;
    /// 轮询所有已连接的标准布局手柄（热插拔；失焦/断开时释放手柄键）
    void poll_gamepad();
};

} // namespace phos

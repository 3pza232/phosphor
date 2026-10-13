#pragma once

#include "core/input.hpp"

#include <string>

struct GLFWwindow;

namespace phos {

/// 窗口事件出口：物理输入经此流向主机各处
struct WindowHandlers {
    Input* input;          // 虚拟手柄输入注入
    bool* escape_flag;     // Esc 按下置位（主机保留键，App 按模式解释）
    bool* settings_flag;   // F2 按下置位（主机保留键：打开设置）
    bool* console_flag;    // ` 键按下置位（调试台开关）
    bool* input_block;     // true 时物理输入不注入游戏（调试台打开期间）
    bool* capture_escape;  // true 时卡带接管 Esc：Esc 作为普通键注入，不再触发主机暂停
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
    void poll_events() const;
    void swap_buffers() const;
    void make_context_current() const;

    GLFWwindow* handle() const { return window_; }

private:
    Window() = default;
    GLFWwindow* window_ = nullptr;
    /// 系统给的输入法上下文（Windows 的 HIMC，用 void* 存以保持头文件平台无关）；
    /// 关输入法前记住它，开回来时原样还给它
    void* ime_context_ = nullptr;
};

} // namespace phos

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
    /// 改写标题栏文字（agent 接管时用于提示"谁在操作"）
    void set_title(const std::string& title) const;
    void poll_events() const;
    void swap_buffers() const;
    void make_context_current() const;

    GLFWwindow* handle() const { return window_; }

private:
    Window() = default;
    GLFWwindow* window_ = nullptr;
};

} // namespace phos

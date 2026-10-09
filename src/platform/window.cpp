#include "platform/window.hpp"

#include "core/text.hpp"

#include <glad/glad.h>
#include <GLFW/glfw3.h>

#include <optional>

namespace phos {

namespace {

/// 转发回调所需的用户指针（WindowHandlers 的副本）
WindowHandlers g_handlers{};  // NOTE: 单窗口假设，多窗口时需重构为映射表

// 物理键盘 → 虚拟按键。这是唯一权威映射，卡带里的提示文字（phos.input.key_name）
// 直接写成这里的**主键**，所以两边必须一起改。
//
// 设计取舍：主机没有手柄，玩家坐在键盘前——所以四个面键就用字母 A/B/X/Y 本身，
// 而不是"手柄上的 A 键对应键盘某个别的键"。
// 方向键**只**用方向键：A/S/D/W 与面键语义冲突（按 A 是"向左"还是 A 键，不能两全）。
//
// **一个功能一个键**：不为同一按钮准备替代键，免得提示与习惯出现两套说法。
// 左右 Shift、主键盘与小键盘的回车是**同一个键的两个物理位置**，保留。
/// GLFW 物理键 → 虚拟键名。约定的名字就是键名本身的小写（"a" / "space" / "k"），
/// 只有四颗方向键与 ENTER/SHIFT 例外：它们保留手柄式的名字（"left" / "start" /
/// "select"），这样老卡带的提示与存档绑定不会因为改名而失效。
/// 不认识的键返回空串：主机不会为它们造键，也不会拦着别的层用文本通道接。
std::string key_name_from_glfw(int glfw_key) {
    if (glfw_key >= GLFW_KEY_A && glfw_key <= GLFW_KEY_Z) {
        return std::string(1, static_cast<char>('a' + (glfw_key - GLFW_KEY_A)));
    }
    if (glfw_key >= GLFW_KEY_0 && glfw_key <= GLFW_KEY_9) {
        return std::string(1, static_cast<char>('0' + (glfw_key - GLFW_KEY_0)));
    }
    if (glfw_key >= GLFW_KEY_F1 && glfw_key <= GLFW_KEY_F12) {
        return "f" + std::to_string(glfw_key - GLFW_KEY_F1 + 1);
    }
    switch (glfw_key) {
        case GLFW_KEY_LEFT: return "left";
        case GLFW_KEY_RIGHT: return "right";
        case GLFW_KEY_UP: return "up";
        case GLFW_KEY_DOWN: return "down";
        case GLFW_KEY_ENTER: case GLFW_KEY_KP_ENTER: return "start";
        case GLFW_KEY_LEFT_SHIFT: case GLFW_KEY_RIGHT_SHIFT: return "select";
        case GLFW_KEY_SPACE: return "space";
        case GLFW_KEY_COMMA: return "comma";
        case GLFW_KEY_PERIOD: return "period";
        case GLFW_KEY_SLASH: return "slash";
        case GLFW_KEY_SEMICOLON: return "semicolon";
        case GLFW_KEY_APOSTROPHE: return "apostrophe";
        case GLFW_KEY_MINUS: return "minus";
        case GLFW_KEY_EQUAL: return "equal";
        case GLFW_KEY_LEFT_BRACKET: return "lbrace";
        case GLFW_KEY_RIGHT_BRACKET: return "rbrace";
        case GLFW_KEY_BACKSLASH: return "backslash";
        case GLFW_KEY_TAB: return "tab";
        default: return {};
    }
}

void key_callback(GLFWwindow*, int key, int, int action, int) {
    if (key == GLFW_KEY_ESCAPE && action == GLFW_PRESS) {
        *g_handlers.escape_flag = true;
        return;
    }
    if (key == GLFW_KEY_GRAVE_ACCENT && action == GLFW_PRESS) {
        *g_handlers.console_flag = true;
        return;
    }
    // 设置键用 F2 而不是字母：字母会被卡带的文本输入吃掉（F2 不产生字符）
    if (key == GLFW_KEY_F2 && action == GLFW_PRESS) {
        *g_handlers.settings_flag = true;
        return;
    }
    if (*g_handlers.input_block) return;  // 调试台打开期间输入不注入游戏

    // 退格走文本通道：GLFW 的字符回调不会为它触发，所以在这里补一次，
    // 让输入层照约定把 '\b' 交给文本缓冲（磁带码输入、卡带的文本输入都靠它）
    if (key == GLFW_KEY_BACKSPACE && (action == GLFW_PRESS || action == GLFW_REPEAT)) {
        g_handlers.input->push_text(std::string(1, text::kBackspace));
        return;
    }

    if (action == GLFW_PRESS || action == GLFW_RELEASE) {
        const std::string name = key_name_from_glfw(key);
        if (!name.empty()) g_handlers.input->set_key(name, action == GLFW_PRESS);
    }
}

void char_callback(GLFWwindow*, unsigned int codepoint) {
    if (*g_handlers.input_block) return;
    // 按 UTF-8 编码整段交给输入层，中文等全角字符也走这里。
    // 注意：退格**不会**经过这个回调（它不是字符），见 key_callback 里的显式转发。
    std::string utf8;
    text::append_utf8(utf8, static_cast<char32_t>(codepoint));
    g_handlers.input->push_text(std::move(utf8));
}

} // namespace

Window Window::create(int width, int height, const std::string& title,
                      const WindowHandlers& handlers, std::string& err) {
    g_handlers = handlers;

    if (!glfwInit()) {
        err = "GLFW 初始化失败";
        return {};
    }

    glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 3);
    glfwWindowHint(GLFW_CONTEXT_VERSION_MINOR, 3);
    glfwWindowHint(GLFW_OPENGL_PROFILE, GLFW_OPENGL_CORE_PROFILE);
    glfwWindowHint(GLFW_RESIZABLE, GLFW_FALSE);

    Window win;
    win.window_ = glfwCreateWindow(width, height, title.c_str(), nullptr, nullptr);
    if (!win.window_) {
        err = "窗口创建失败（需要 OpenGL 3.3 支持）";
        glfwTerminate();
        return {};
    }

    glfwSetKeyCallback(win.window_, key_callback);
    glfwSetCharCallback(win.window_, char_callback);

    win.make_context_current();
    glfwSwapInterval(1);  // 与显示器刷新同步，避免空转烧显卡

    if (!gladLoadGLLoader(reinterpret_cast<GLADloadproc>(glfwGetProcAddress))) {
        err = "glad 加载 OpenGL 函数失败";
        return {};
    }
    return win;
}

Window::~Window() {
    if (window_) {
        glfwDestroyWindow(window_);
        glfwTerminate();
    }
}

Window::Window(Window&& other) noexcept : window_(other.window_) {
    other.window_ = nullptr;
}

Window& Window::operator=(Window&& other) noexcept {
    if (this != &other) {
        if (window_) glfwDestroyWindow(window_);
        window_ = other.window_;
        other.window_ = nullptr;
    }
    return *this;
}

bool Window::should_close() const {
    return glfwWindowShouldClose(window_);
}

void Window::resize(int width, int height) const {
    glfwSetWindowSize(window_, width, height);
}

void Window::set_title(const std::string& title) const {
    if (window_) glfwSetWindowTitle(window_, title.c_str());
}

void Window::poll_events() const {
    glfwPollEvents();
}

void Window::swap_buffers() const {
    glfwSwapBuffers(window_);
}

void Window::make_context_current() const {
    glfwMakeContextCurrent(window_);
}

} // namespace phos

#include "platform/window.hpp"

#include "core/log.hpp"
#include "core/text.hpp"

#include <glad/glad.h>
#include <GLFW/glfw3.h>
#include <stb_image.h>

#ifdef _WIN32
#define GLFW_EXPOSE_NATIVE_WIN32  // 取 HWND，供输入法开关使用
#include <GLFW/glfw3native.h>
#include <imm.h>  // 输入法上下文（ImmAssociateContext）：按输入框声明开关系统输入法
#endif

#include <optional>

namespace phos {

namespace {

/// 转发回调所需的用户指针（WindowHandlers 的副本）
WindowHandlers g_handlers{};  // NOTE: 单窗口假设，多窗口时需重构为映射表

/// GLFW 物理键 → 虚拟键名。这是**唯一权威映射**：卡带提示里的键名（phos.input.key_name）
/// 用的就是这里的名字，两边必须一起改。
/// 命名：键名本身的小写（"a" / "space" / "k"），面键即字母本身（主机没有手柄，
/// 不模仿"手柄上的 A 对应键盘某个键"）；例外是方向键（"left"/"right"/"up"/"down"）、
/// 回车与 Shift（"start"/"select"）、方括号（"lbrace"/"rbrace"）。
/// 方向键只用方向键：A/S/D/W 与面键语义冲突（按 A 是"向左"还是 A 键，不能两全）；
/// 物理键 → 虚拟键名。这是**唯一权威映射**：卡带提示里的键名（`phos.input.key_name`）用的就是这里。
/// **覆盖全部按键**（字母/数字/F1-F25/方向/符号/功能区/小键盘/修饰键），卡带想用哪个键都可以，
/// 主机不必为某个键改代码。左右两个物理位置的同一键（左右 Shift、主/小键盘回车）算同一个名字。
/// 只返回空串给真正不认识的键（未来的新键）。
std::string key_name_from_glfw(int glfw_key) {
    if (glfw_key >= GLFW_KEY_A && glfw_key <= GLFW_KEY_Z) {
        return std::string(1, static_cast<char>('a' + (glfw_key - GLFW_KEY_A)));
    }
    if (glfw_key >= GLFW_KEY_0 && glfw_key <= GLFW_KEY_9) {
        return std::string(1, static_cast<char>('0' + (glfw_key - GLFW_KEY_0)));
    }
    if (glfw_key >= GLFW_KEY_F1 && glfw_key <= GLFW_KEY_F25) {
        return "f" + std::to_string(glfw_key - GLFW_KEY_F1 + 1);
    }
    if (glfw_key >= GLFW_KEY_KP_0 && glfw_key <= GLFW_KEY_KP_9) {
        return "kp" + std::string(1, static_cast<char>('0' + (glfw_key - GLFW_KEY_KP_0)));
    }
    switch (glfw_key) {
        // 方向 / 手柄面键（主机没有手柄，面键就是键盘上的 A/B/X/Y）
        case GLFW_KEY_LEFT: return "left";
        case GLFW_KEY_RIGHT: return "right";
        case GLFW_KEY_UP: return "up";
        case GLFW_KEY_DOWN: return "down";
        case GLFW_KEY_ENTER: case GLFW_KEY_KP_ENTER: return "start";
        case GLFW_KEY_LEFT_SHIFT: case GLFW_KEY_RIGHT_SHIFT: return "select";
        // 主键盘符号（键盘专属的功能位）
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
        case GLFW_KEY_GRAVE_ACCENT: return "grave";
        // 功能区
        case GLFW_KEY_TAB: return "tab";
        case GLFW_KEY_BACKSPACE: return "backspace";
        case GLFW_KEY_INSERT: return "insert";
        case GLFW_KEY_DELETE: return "delete";
        case GLFW_KEY_HOME: return "home";
        case GLFW_KEY_END: return "end";
        case GLFW_KEY_PAGE_UP: return "pageup";
        case GLFW_KEY_PAGE_DOWN: return "pagedown";
        case GLFW_KEY_CAPS_LOCK: return "capslock";
        case GLFW_KEY_SCROLL_LOCK: return "scrolllock";
        case GLFW_KEY_NUM_LOCK: return "numlock";
        case GLFW_KEY_PRINT_SCREEN: return "printscreen";
        case GLFW_KEY_PAUSE: return "pause";
        case GLFW_KEY_MENU: return "menu";
        // 小键盘
        case GLFW_KEY_KP_DECIMAL: return "kpdecimal";
        case GLFW_KEY_KP_DIVIDE: return "kpdivide";
        case GLFW_KEY_KP_MULTIPLY: return "kpmultiply";
        case GLFW_KEY_KP_SUBTRACT: return "kpsubtract";
        case GLFW_KEY_KP_ADD: return "kpadd";
        case GLFW_KEY_KP_EQUAL: return "kpequal";
        // 修饰键（Ctrl / Alt / Super）
        case GLFW_KEY_LEFT_CONTROL: case GLFW_KEY_RIGHT_CONTROL: return "control";
        case GLFW_KEY_LEFT_ALT: case GLFW_KEY_RIGHT_ALT: return "alt";
        case GLFW_KEY_LEFT_SUPER: case GLFW_KEY_RIGHT_SUPER: return "super";
        default: return {};
    }
}

void key_callback(GLFWwindow*, int key, int, int action, int) {
    if (key == GLFW_KEY_ESCAPE) {
        // 卡带声明"接管 Esc"（phos.sys.capture_escape）时，Esc 作为普通键交给卡带，
        // 主机不再拿它做暂停/返回；否则维持主机保留键语义
        if ((action == GLFW_PRESS || action == GLFW_RELEASE) && g_handlers.capture_escape &&
            *g_handlers.capture_escape) {
            g_handlers.input->set_key("escape", action == GLFW_PRESS);
            return;
        }
        if (action == GLFW_PRESS) *g_handlers.escape_flag = true;
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

    // 退格：GLFW 的字符回调不为它触发，所以这里补一次 '\b' 给**文本通道**
    // （磁带码输入、卡带的文本框靠它，见 worms 昵称框）。**不 return**——下面的通用键映射
    // 照常把 "backspace" 也交给卡带当功能键（如象棋悔棋）
    if (key == GLFW_KEY_BACKSPACE && (action == GLFW_PRESS || action == GLFW_REPEAT)) {
        g_handlers.input->push_text(std::string(1, text::kBackspace));
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

/// 窗口与任务栏图标。取路径的约定与字体、主题相同：**相对运行目录**
/// （发行目录就是 exe 所在目录，`theme/` 由构建时同步过去）。
/// 读不到不算错误——少一张图不该让机器开不起来，退回系统默认图标即可，但必须留痕。
/// stb_image 的实现体在 render/screen_image.cpp，这里只用它的声明（再定义一次会重复符号）。
void apply_window_icon(GLFWwindow* window, const std::string& path) {
    int width = 0, height = 0, channels = 0;
    unsigned char* pixels = stbi_load(path.c_str(), &width, &height, &channels, 4);
    if (!pixels) {
        log::warn("icon: cannot read " + path + "（用系统默认图标）");
        return;
    }
    GLFWimage image{};
    image.width = width;
    image.height = height;
    image.pixels = pixels;
    glfwSetWindowIcon(window, 1, &image);
    stbi_image_free(pixels);
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

    apply_window_icon(win.window_, "theme/icon/phos_icon.jpg");

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

Window::Window(Window&& other) noexcept : window_(other.window_), ime_context_(other.ime_context_) {
    other.window_ = nullptr;
    other.ime_context_ = nullptr;
}

Window& Window::operator=(Window&& other) noexcept {
    if (this != &other) {
        if (window_) glfwDestroyWindow(window_);
        window_ = other.window_;
        ime_context_ = other.ime_context_;
        other.window_ = nullptr;
        other.ime_context_ = nullptr;
    }
    return *this;
}

bool Window::should_close() const {
    return glfwWindowShouldClose(window_);
}

void Window::resize(int width, int height) const {
    glfwSetWindowSize(window_, width, height);
}

int Window::framebuffer_width() const {
    int w = 0, h = 0;
    if (window_) glfwGetFramebufferSize(window_, &w, &h);
    return w;
}

int Window::framebuffer_height() const {
    int w = 0, h = 0;
    if (window_) glfwGetFramebufferSize(window_, &w, &h);
    return h;
}

void Window::set_ime_enabled(bool enabled) {
#ifdef _WIN32
    if (!window_) return;
    HWND hwnd = glfwGetWin32Window(window_);
    if (!hwnd) return;
    if (enabled) {
        if (ime_context_) ImmAssociateContext(hwnd, static_cast<HIMC>(ime_context_));
    } else {
        // 首次关之前先把系统给的默认上下文记下来，之后才能原样开回来；**每次关都要重新
        // 解除关联**——否则开过一次之后再关就变成空操作，输入法会一直挂着
        if (ime_context_ == nullptr) ime_context_ = ImmGetContext(hwnd);
        ImmAssociateContext(hwnd, nullptr);
    }
#else
    (void)enabled;  // 其它平台的输入法由各自 IM 框架管，这里不介入
#endif
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

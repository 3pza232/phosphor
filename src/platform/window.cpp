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
WindowHandlers* handlers_for(GLFWwindow* window) {
    return static_cast<WindowHandlers*>(glfwGetWindowUserPointer(window));
}

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

/// 标准布局手柄 → 现有虚拟键名（与键盘共用同一套名字，不新增输入层概念）。
/// 左摇杆与十字键都映射到方向键：任一来源按下即按下；摇杆带死区，十字键是数字量。
std::set<std::string> gamepad_key_names(const GLFWgamepadstate& state) {
    constexpr float kStickDeadzone = 0.35f;
    std::set<std::string> keys;
    const auto button = [&keys, &state](int index, const char* name) {
        if (state.buttons[index] == GLFW_PRESS) keys.insert(name);
    };
    const auto axis = [&keys, &state](int index, float sign, const char* name) {
        if (state.axes[index] * sign > kStickDeadzone) keys.insert(name);
    };
    // 左摇杆（GLFW：左摇杆 X 右正 / Y 下正）与十字键
    axis(GLFW_GAMEPAD_AXIS_LEFT_X, -1.0f, "left");
    axis(GLFW_GAMEPAD_AXIS_LEFT_X, 1.0f, "right");
    axis(GLFW_GAMEPAD_AXIS_LEFT_Y, -1.0f, "up");
    axis(GLFW_GAMEPAD_AXIS_LEFT_Y, 1.0f, "down");
    button(GLFW_GAMEPAD_BUTTON_DPAD_LEFT, "left");
    button(GLFW_GAMEPAD_BUTTON_DPAD_RIGHT, "right");
    button(GLFW_GAMEPAD_BUTTON_DPAD_UP, "up");
    button(GLFW_GAMEPAD_BUTTON_DPAD_DOWN, "down");
    // 面键 / START / BACK / 肩键（肩键落到已有的 lbrace/rbrace 名字上，不新增键名）
    button(GLFW_GAMEPAD_BUTTON_A, "a");
    button(GLFW_GAMEPAD_BUTTON_B, "b");
    button(GLFW_GAMEPAD_BUTTON_X, "x");
    button(GLFW_GAMEPAD_BUTTON_Y, "y");
    button(GLFW_GAMEPAD_BUTTON_START, "start");
    button(GLFW_GAMEPAD_BUTTON_BACK, "select");
    button(GLFW_GAMEPAD_BUTTON_LEFT_BUMPER, "lbrace");
    button(GLFW_GAMEPAD_BUTTON_RIGHT_BUMPER, "rbrace");
    return keys;
}

void key_callback(GLFWwindow* window, int key, int, int action, int) {
    WindowHandlers* handlers = handlers_for(window);
    if (!handlers) return;
    // 键盘按下集只服务"手柄/键盘共存"判断：手柄松开同一键时不误清键盘仍按着的
    const auto note_keyboard = [handlers](const std::string& name, bool down) {
        if (!handlers->keyboard_down) return;
        if (down) handlers->keyboard_down->insert(name);
        else handlers->keyboard_down->erase(name);
    };
    if (key == GLFW_KEY_ESCAPE) {
        // 卡带声明"接管 Esc"（phos.sys.capture_escape）时，Esc 作为普通键交给卡带，
        // 主机不再拿它做暂停/返回；否则维持主机保留键语义
        if ((action == GLFW_PRESS || action == GLFW_RELEASE) && handlers->capture_escape &&
            *handlers->capture_escape) {
            note_keyboard("escape", action == GLFW_PRESS);
            handlers->input->set_key("escape", action == GLFW_PRESS);
            return;
        }
        if (action == GLFW_PRESS) *handlers->escape_flag = true;
        return;
    }
    if (key == GLFW_KEY_GRAVE_ACCENT && action == GLFW_PRESS) {
        *handlers->console_flag = true;
        return;
    }
    // 设置键用 F2 而不是字母：字母会被卡带的文本输入吃掉（F2 不产生字符）
    if (key == GLFW_KEY_F2 && action == GLFW_PRESS) {
        *handlers->settings_flag = true;
        return;
    }
    // F12：系统截图（与 --screenshot 同一条 CPU 光栅化路径）。放在 input_block 之前——
    // 调试台打开时也能截，且不让卡带输入吃掉
    if (key == GLFW_KEY_F12 && action == GLFW_PRESS) {
        *handlers->screenshot_flag = true;
        return;
    }
    if (*handlers->input_block) return;  // 调试台打开期间输入不注入游戏

    // 退格：GLFW 的字符回调不为它触发，所以这里补一次 '\b' 给**文本通道**
    // （磁带码输入、卡带的文本框靠它，见 worms 昵称框）。**不 return**——下面的通用键映射
    // 照常把 "backspace" 也交给卡带当功能键（如象棋悔棋）
    if (key == GLFW_KEY_BACKSPACE && (action == GLFW_PRESS || action == GLFW_REPEAT)) {
        handlers->input->push_text(std::string(1, text::kBackspace));
    }

    if (action == GLFW_PRESS || action == GLFW_RELEASE) {
        const std::string name = key_name_from_glfw(key);
        if (name.empty()) return;
        const bool down = action == GLFW_PRESS;
        note_keyboard(name, down);
        // 手柄仍按着同名键：键盘松开不能把它清掉（任一来源按下即按下）
        if (!down && handlers->gamepad_down && handlers->gamepad_down->count(name)) return;
        handlers->input->set_key(name, down);
    }
}

void focus_callback(GLFWwindow* window, int focused) {
    // 失焦时物理按键的 release 事件可能根本收不到（Alt+Tab / 点别的窗口）：
    // 不释放就会"卡键"——回到游戏还在往一个方向走。这里直接把所有键松开。
    if (!focused) {
        WindowHandlers* handlers = handlers_for(window);
        if (!handlers) return;
        // 失焦时物理键盘的 release 可能收不到：清掉键盘按下集并释放全部虚拟键。
        // 手柄键由下一次 poll_gamepad 在"未聚焦"分支里释放（那里的释放不被重复按下覆盖）
        if (handlers->keyboard_down) handlers->keyboard_down->clear();
        if (handlers->input) handlers->input->release_all();
    }
}

void char_callback(GLFWwindow* window, unsigned int codepoint) {
    WindowHandlers* handlers = handlers_for(window);
    if (!handlers) return;
    if (*handlers->input_block) return;
    // 按 UTF-8 编码整段交给输入层，中文等全角字符也走这里。
    // 注意：退格**不会**经过这个回调（它不是字符），见 key_callback 里的显式转发。
    std::string utf8;
    text::append_utf8(utf8, static_cast<char32_t>(codepoint));
    handlers->input->push_text(std::move(utf8));
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

    // 回调上下文挂在窗口自己的 user pointer 上：多个窗口各一份，不再有文件级全局
    win.handlers_ = std::make_unique<WindowHandlers>(handlers);
    // 回填共存判断用的键集（调用方传进来的这两个指针为 null，不参与）
    win.handlers_->keyboard_down = &win.keyboard_keys_;
    win.handlers_->gamepad_down = &win.gamepad_keys_;
    glfwSetWindowUserPointer(win.window_, win.handlers_.get());

    apply_window_icon(win.window_, "theme/icon/phos_icon.jpg");

    glfwSetKeyCallback(win.window_, key_callback);
    glfwSetCharCallback(win.window_, char_callback);
    glfwSetWindowFocusCallback(win.window_, focus_callback);

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

Window::Window(Window&& other) noexcept
    : window_(other.window_), ime_context_(other.ime_context_),
      handlers_(std::move(other.handlers_)) {
    other.window_ = nullptr;
    other.ime_context_ = nullptr;
    if (window_) glfwSetWindowUserPointer(window_, handlers_.get());
}

Window& Window::operator=(Window&& other) noexcept {
    if (this != &other) {
        if (window_) glfwDestroyWindow(window_);
        window_ = other.window_;
        ime_context_ = other.ime_context_;
        handlers_ = std::move(other.handlers_);
        other.window_ = nullptr;
        other.ime_context_ = nullptr;
        if (window_) glfwSetWindowUserPointer(window_, handlers_.get());
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

void Window::poll_events() {
    glfwPollEvents();
    poll_gamepad();
}

void Window::poll_gamepad() {
    if (!window_) return;
    std::set<std::string> pressed;

    // 失焦或调试台吞输入期间视为没有手柄输入：按下集合为空，下面的释放逻辑会松掉
    // 手柄独占的键（键盘在 key_callback 里同一时刻也被 input_block 挡住）
    const bool blocked = handlers_->input_block && *handlers_->input_block;
    if (!blocked && glfwGetWindowAttrib(window_, GLFW_FOCUSED) == GLFW_TRUE) {
        GLFWgamepadstate state{};
        for (int jid = GLFW_JOYSTICK_1; jid <= GLFW_JOYSTICK_LAST; ++jid) {
            if (glfwJoystickIsGamepad(jid) != GLFW_TRUE) continue;
            if (glfwGetGamepadState(jid, &state) != GLFW_TRUE) continue;
            const std::set<std::string> names = gamepad_key_names(state);
            pressed.insert(names.begin(), names.end());
        }
    }

    // 松开：手柄这帧没按、且键盘也没按着 → 真正释放
    for (const std::string& key : gamepad_keys_) {
        if (pressed.count(key)) continue;
        if (handlers_->keyboard_down && handlers_->keyboard_down->count(key)) continue;
        if (handlers_->input) handlers_->input->set_key(key, false);
    }
    // 按下：新手柄键（键盘已按着同名键时重复 set_key(true) 不会重记按下沿）
    for (const std::string& key : pressed) {
        if (gamepad_keys_.count(key)) continue;
        if (handlers_->input) handlers_->input->set_key(key, true);
    }
    gamepad_keys_ = std::move(pressed);
}

void Window::swap_buffers() const {
    glfwSwapBuffers(window_);
}

void Window::make_context_current() const {
    glfwMakeContextCurrent(window_);
}

} // namespace phos
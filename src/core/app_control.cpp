#include "agent/cart_json.hpp"
#include "core/json_lite.hpp"
#include "cart/cart_scanner.hpp"
#include "core/app.hpp"
#include "core/log.hpp"
#include "render/renderer.hpp"
#include "render/screen_image.hpp"

#include <cmath>
#include <cstdio>
#include <cstring>
#include <sstream>

namespace phos {

namespace {

/// 一次 time.step 最多推进多少逻辑帧：防止一个超大帧数把主机卡住，或 agent_.pending_steps 累加溢出
constexpr int kMaxStepFrames = 100000;

/// 图层清单 → JSON 数组（空数组 = 该卡带没建层）。
/// 次序与合成一致（z 升序），agent 据此知道谁压在谁上面
std::string layers_json(const LayeredScreen& layers) {
    std::string out = "[";
    bool first = true;
    for (const Layer* layer : layers.ordered()) {
        if (!first) out += ",";
        out += "{\"name\":" + json::quote(layer->name) + ",\"z\":" + std::to_string(layer->z) +
               ",\"visible\":" + (layer->visible ? "true" : "false") + "}";
        first = false;
    }
    return out + "]";
}

/// 屏幕文本 → JSON 字符串数组
std::string screen_lines_json(const Screen& screen) {
    std::istringstream stream(screen.to_text());
    std::string line;
    std::string out = "[";
    bool first = true;
    while (std::getline(stream, line)) {
        if (!line.empty() && line.back() == '\r') line.pop_back();
        if (!first) out += ",";
        out += json::quote(line);
        first = false;
    }
    out += "]";
    return out;
}

} // namespace

void App::poll_control() {
    if (!control_.running()) return;
    for (const ControlCommand& command : control_.take_commands()) {
        // 逐条记日志：把 agent 的整段操作与主机事件放在同一条时间线上
        log::info("control #" + std::to_string(command.id) + " " + command.name);
        execute_control(command);
    }
}

std::string App::control_state_json() const {
    std::ostringstream out;
    out << "\"frame\":" << frame_count_ << ",\"mode\":" << json::quote(mode_name())
        << ",\"playing\":" << (playing_ ? "true" : "false")
        << ",\"stepping\":" << (agent_.stepping ? "true" : "false")
        << ",\"pending_steps\":" << agent_.pending_steps
        << ",\"grid_w\":" << display_.screen.width()
        << ",\"grid_h\":" << display_.screen.height()
        << ",\"content_w\":" << kContentW << ",\"content_h\":" << kContentH
        << ",\"panel_w\":" << host_.panel_w << ",\"seed\":" << rng_seed_
        << ",\"host_time\":" << host_.time
        << ",\"skin\":" << json::quote(packs_.skin().id)
        << ",\"palette\":" << json::quote(active_palette_.id)
        << ",\"boot\":"
        << json::quote(packs_.boots.empty()
                           ? ""
                           : packs_.boots[static_cast<size_t>(packs_.boot_index)].id)
        << ",\"sound\":"
        << json::quote(packs_.sounds.empty()
                           ? ""
                           : packs_.sounds[static_cast<size_t>(packs_.sound_index)].id)
        << ",\"font\":" << json::quote(font_scheme_)
        << ",\"font_size\":" << font_px_  // 当前生效字号（像素高）
        // 本帧是否有输入框在"举手要中文"：卡带声明 ime=true 的框被 feed，或卡带架搜索在输入。
        // 主机据此开关系统输入法（仅 Windows 实际生效），也给测试一个可读的信号
        << ",\"ime\":" << (host_.ime_wanted ? "true" : "false")
        << ",\"language\":" << json::quote(lang_name(shell_.language()))
        << ",\"cursor\":" << (playing_ ? -1 : shell_.cursor())
        << ",\"shelf\":" << shelf_json()
        << ",\"crt_level\":" << config_.crt_level
        << ",\"fps\":" << config_.fps
        << ",\"render_fps\":" << host_.fps
        << ",\"merge_ms\":" << timing_.merge_ms
        << ",\"layers\":" << layers_json(host_.layers);

    // 卡带注册的可调参数（phos.debug.number）当前值；无卡带或未注册为空数组
    out << ",\"debug_params\":[";
    if (cart_) {
        const bool english = config_.language == "en";  // 名字按当前语言给，与人看到的篮子一致
        const size_t count = cart_->debug_param_count();
        for (size_t i = 0; i < count; ++i) {
            const Cartridge::DebugParamView view = cart_->debug_param(i);
            // 分组路径用 '/' 拼成串（json_lite 不解析数组）：同名参数（如每件武器的"伤害"）靠它区分
            std::string group;
            for (const Localized& seg : view.group) {
                if (!group.empty()) group += "/";
                group += seg.get(english);
            }
            const char* kind = view.kind == DebugKind::integer ? "integer"
                               : view.kind == DebugKind::boolean ? "boolean"
                                                                 : "number";
            out << (i ? "," : "") << "{\"name\":" << json::quote(view.name.get(english))
                << ",\"group\":" << json::quote(group) << ",\"kind\":" << json::quote(kind)
                << ",\"value\":" << view.value << "}";
        }
    }
    out << "]";

    out << ",\"video\":" << json::quote(headless_ ? "headless" : "window")
        << ",\"control_port\":" << control_port_
        << ",\"music_volume\":" << config_.music_volume
        << ",\"sfx_volume\":" << config_.sfx_volume
        << ",\"audio\":" << (audio_.active() ? "true" : "false")
        << ",\"voices\":" << audio_.active_voices() << ",\"dropped\":" << audio_.dropped_requests()
        << ",\"music\":{\"on\":" << (audio_.music_on() ? "true" : "false")
        << ",\"section\":" << json::quote(audio_.music_section())
        << ",\"index\":" << audio_.music_section_index()
        << ",\"count\":" << audio_.music_section_count() << "}";

    if (cart_) {
        const CartInfo& info = cart_->info();
        out << ",\"cart\":{\"id\":" << json::quote(info.id)
            << ",\"name\":" << json::quote(info.name.get(config_.language == "en"))
            << ",\"version\":" << json::quote(info.version)
            << ",\"author\":" << json::quote(info.author)
            << ",\"path\":" << json::quote(cart_path_)
            << ",\"sidebar_w\":" << info.sidebar_w
            << ",\"lua_mem_kb\":" << cart_->lua_memory_kb()
            << ",\"update_ms\":" << timing_.update_ms << ",\"draw_ms\":" << timing_.draw_ms
            << ",\"update_peak_ms\":" << timing_.update_peak_ms
            << ",\"draw_peak_ms\":" << timing_.draw_peak_ms << "}";
    } else {
        out << ",\"cart\":null";
    }
    // 恒定输出：无错误时给空串，agent 可以无条件读这个字段（缺键比空串更难处理）
    out << ",\"last_error\":" << json::quote(last_error_);

    // 内容包：**显示名**（屏幕上画的就是它，当前取包文件夹名）与**id**（稳定标识，
    // 与显示名逐位对应）。脚本要比对状态里的当前值、或记住某一项时必须用 id——
    // 显示名可能重名或随包改名，拿它去比 id 会假失败。字体方案没有独立显示名，只有 `font`
    auto pack_json = [](const auto& packs, auto id_of) {
        std::string out;
        for (const auto& pack : packs) {
            if (!out.empty()) out += ",";
            out += json::quote(id_of(pack));
        }
        return "[" + out + "]";
    };
    const auto by_name = [](const auto& pack) { return pack.name; };
    const auto by_id = [](const auto& pack) { return pack.id; };
    out << ",\"save\":{\"available\":" << (host_.save ? "true" : "false")
        << ",\"entries\":" << (host_.save ? host_.save->size() : 0) << "}";

    out << ",\"packs\":{\"skin\":" << pack_json(packs_.skins, by_name)
        << ",\"skin_ids\":" << pack_json(packs_.skins, by_id)
        << ",\"palette\":" << pack_json(packs_.palettes, by_name)
        << ",\"palette_ids\":" << pack_json(packs_.palettes, by_id)
        << ",\"boot\":" << pack_json(packs_.boots, by_name)
        << ",\"boot_ids\":" << pack_json(packs_.boots, by_id)
        << ",\"sound\":" << pack_json(packs_.sounds, by_name)
        << ",\"sound_ids\":" << pack_json(packs_.sounds, by_id)
        << ",\"font\":[";
    for (size_t i = 0; i < font_schemes_.size(); ++i)
        out << (i ? "," : "") << json::quote(font_schemes_[i]);
    out << "]}";

    std::string held;
    for (const auto& name : input_.names()) {
        if (!input_.down(name)) continue;
        if (!held.empty()) held += ",";
        held += json::quote(name);
    }
    out << ",\"held_keys\":[" << held << "]";
    return out.str();
}

std::string App::carts_json() const {
    // 字段集与 `--scan --json` 共用一份实现（agent/cart_json.hpp）
    // 这里刻意**重扫一次**目录而不是复用卡带架：控制通道是给工具用的，
    // 它要的是"磁盘上现在有什么"（含目录顺序），而不是玩家眼里的排序结果
    return "\"carts\":" + cart_list_json(scan_carts(kCartDir), config_.language == "en");
}

std::string App::shelf_json() const {
    // 架上的顺序（玩家眼里的：最近打开优先），与 carts.scan 的目录顺序不同。
    // 两者都暴露，是因为用途不同：扫描列表回答"磁盘上有什么"，
    // 这一份回答"数到第几张能插进去哪张"——cursor 就是它的下标
    std::string ids;
    for (const auto& cart : shell_.carts()) {
        if (!ids.empty()) ids += ",";
        ids += json::quote(cart.id);
    }
    return "[" + ids + "]";
}

void App::complete_step_request() {
    if (agent_.step_request_id < 0) return;
    control_.reply(agent_.step_request_id, control_state_json());
    agent_.step_request_id = -1;
}

void App::complete_frame_read(Renderer* renderer) {
    if (agent_.frame_read_id < 0) return;
    const int id = agent_.frame_read_id;
    const std::string path = agent_.frame_read_path;
    agent_.frame_read_id = -1;
    agent_.frame_read_path.clear();

    // 无窗口（或渲染器尚未画过帧）时没有帧缓冲可读：如实报错，不静默返回空画面
    int width = 0, height = 0;
    std::vector<unsigned char> rgba;
    if (!renderer || !renderer->read_frame(rgba, width, height)) {
        control_.reply_error(id, "no framebuffer readable (frame.read needs the window path)");
        return;
    }

    // 统计放在回包里："不是全黑"这类断言不必依赖 PNG 也能成立。
    // 亮度阈值取 16：CRT 后处理会压暗，但真正的字形笔画远高于它
    const size_t pixels = static_cast<size_t>(width) * static_cast<size_t>(height);
    size_t lit = 0;
    double luma_sum = 0.0;
    for (size_t i = 0; i < pixels; ++i) {
        const unsigned char* p = rgba.data() + i * 4;
        const double luma = 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2];
        luma_sum += luma;
        if (luma > 16.0) ++lit;
    }

    std::ostringstream out;
    out << "\"width\":" << width << ",\"height\":" << height
        << ",\"lit_ratio\":" << (pixels ? static_cast<double>(lit) / pixels : 0.0)
        << ",\"mean_luma\":" << (pixels ? luma_sum / pixels : 0.0);

    if (!path.empty()) {
        // 行序翻转：OpenGL 自下而上，PNG（以及 CPU 截图）自上而下 —— 翻过来才能与
        // screenshot 的像素逐格对照
        std::vector<unsigned char> flipped(pixels * 4);
        const size_t stride = static_cast<size_t>(width) * 4;
        for (int y = 0; y < height; ++y)
            std::memcpy(flipped.data() + static_cast<size_t>(y) * stride,
                        rgba.data() + static_cast<size_t>(height - 1 - y) * stride, stride);
        ScreenImage image;
        image.width = width;
        image.height = height;
        image.rgba = std::move(flipped);
        std::string error;
        if (!write_png(image, path, error)) {
            control_.reply_error(id, error);
            return;
        }
        out << ",\"path\":" << json::quote(path);
    }
    control_.reply(id, out.str());
}

void App::release_expired_inputs() {
    for (auto it = agent_.pending_releases.begin(); it != agent_.pending_releases.end();) {
        if (--it->second <= 0) {
            input_.set_key(it->first, false);
            it = agent_.pending_releases.erase(it);
        } else {
            ++it;
        }
    }
}

void App::execute_control(const ControlCommand& command) {
    const std::string& name = command.name;
    const json::Object& args = command.args;

    if (name == "ping") {
        control_.reply(command.id, "\"pong\":true");
        return;
    }

    if (name == "screen.read") {
        // 默认读**合并结果**（整屏，与既有语义一致）；带 layer 时读单份内容：
        // layer = "screen" 读的同样是合并后的整屏（层是就地合并进 display_.screen 的，没有
        // "合并前的那一层"可读），之所以收这个取值，只是让"我读的是整屏"能被显式写出来；
        // 其余按卡带注册的层名读那一层自己。层缓冲是内容区局部坐标，所以行数就是内容区高
        const std::string which = args.str("layer");
        const Screen* source = &display_.screen;
        std::string label = "merged";
        if (!which.empty() && which != "screen") {
            const Layer* layer = host_.layers.find(which);
            if (!layer) {
                control_.reply_error(command.id, "no such layer: " + which);
                return;
            }
            source = &layer->cells;
            label = which;
        } else if (which == "screen") {
            label = "screen";
        }
        std::ostringstream payload;
        payload << "\"layer\":" << json::quote(label) << ",\"width\":" << source->width()
                << ",\"height\":" << source->height() << ",\"frame\":" << frame_count_
                << ",\"lines\":" << screen_lines_json(*source);
        control_.reply(command.id, payload.str());
        return;
    }

    if (name == "screenshot") {
        const std::string path = args.str("path");
        if (path.empty()) {
            control_.reply_error(command.id, "missing 'path'");
            return;
        }
        int width = 0, height = 0;
        std::string error;
        if (!write_screenshot(path, width, height, error)) {
            control_.reply_error(command.id, error);
            return;
        }
        control_.reply(command.id, "\"path\":" + json::quote(path) + ",\"width\":" +
                                       std::to_string(width) + ",\"height\":" +
                                       std::to_string(height));
        return;
    }

    if (name == "frame.read") {
        // 读的是 GL 渲染出的真实帧（含着色器与逐层叠画），与 CPU 光栅化的 screenshot 互补。
        // 无头没有帧缓冲，直接报错；有窗口时只登记请求——读回必须落在"画完这一帧、swap
        // 之前"，那个时机只有渲染循环掌握（见 complete_frame_read）
        if (headless_) {
            control_.reply_error(command.id, "no framebuffer in headless mode (use screenshot)");
            return;
        }
        agent_.frame_read_path = args.str("path");
        agent_.frame_read_id = command.id;
        return;
    }

    if (name == "save.export") {
        if (!host_.save) {
            control_.reply_error(command.id, "loaded cart has no save store");
            return;
        }
        control_.reply(command.id, "\"code\":" + json::quote(host_.save->export_code()));
        return;
    }

    if (name == "save.import") {
        if (!host_.save) {
            control_.reply_error(command.id, "loaded cart has no save store");
            return;
        }
        const std::string code = args.str("code");
        if (code.empty()) {
            control_.reply_error(command.id, "missing 'code'");
            return;
        }
        if (!host_.save->import_code(code)) {
            control_.reply_error(command.id, "invalid tape code");
            return;
        }
        control_.reply(command.id,
                       "\"entries\":" + std::to_string(host_.save->size()));
        return;
    }

    if (name == "state.query") {
        std::string payload = control_state_json();

        // 深入卡带 Lua 状态：显式路径查询 + 卡带自报的 debug_state()
        if (args.has("path")) {
            const std::string path = args.str("path");
            const std::string value = cart_ ? cart_->global_json(path) : std::string();
            payload += ",\"path\":" + json::quote(path) +
                       ",\"value\":" + (value.empty() ? "null" : value);
        }
        if (cart_) {
            const std::string debug = cart_->debug_state_json();
            if (!debug.empty()) payload += ",\"debug\":" + debug;
        }

        control_.reply(command.id, payload);
        return;
    }

    if (name == "carts.scan") {
        control_.reply(command.id, carts_json());
        return;
    }

    if (name == "input.inject") {
        const std::string key_name = args.str("key");
        const auto action = input_action_from(key_name, args.flag("down", true));
        if (!action) {
            control_.reply_error(command.id, "unknown key: " + key_name);
            return;
        }

        // 主机保留键可能是"关机"：先回包再执行，避免回包与进程退出竞争。
        // frames 照传：卡带接管 Esc 时它已按普通键处理（要能按帧释放），其余主机键忽略它
        if (!action->host_key.empty()) {
            control_.reply(command.id, "\"host_key\":" + json::quote(action->host_key));
            apply_input_action(*action, args.integer("frames", 0));
            return;
        }

        apply_input_action(*action, args.integer("frames", 0));
        control_.reply(command.id, control_state_json());
        return;
    }

    // 注入文本：与玩家敲键盘等价（UTF-8，可含多字节字符）。文本只在下一逻辑帧可见
    if (name == "input.text") {
        input_.push_text(args.str("text"));
        control_.reply(command.id, control_state_json());
        return;
    }

    if (name == "input.clear") {
        input_.release_all();
        agent_.pending_releases.clear();
        control_.reply(command.id, "");
        return;
    }

    if (name == "time.step") {
        // 同一时刻只允许一条 time.step 在途：回包是"推进完毕"的同步点，两个请求共用
        // 一个回包 id 会让先到的那个永远等不到回包
        if (agent_.step_request_id >= 0) {
            control_.reply_error(command.id, "a time.step is already pending");
            return;
        }
        int frames = args.integer("frames", 1);
        if (frames < 1) frames = 1;
        if (frames > kMaxStepFrames) frames = kMaxStepFrames;
        agent_.stepping = true;
        agent_.pending_steps += frames;
        agent_.step_request_id = command.id;  // 全部推进完毕后再回包（确定性同步点）
        return;
    }

    if (name == "time.resume") {
        agent_.stepping = false;
        agent_.pending_steps = 0;
        agent_.step_request_id = -1;
        control_.reply(command.id, control_state_json());
        return;
    }

    if (name == "cart.load") {
        const std::string path = args.str("path");
        if (path.empty()) {
            control_.reply_error(command.id, "missing 'path'");
            return;
        }
        load_cart_path(path);
        if (!playing_) {
            control_.reply_error(command.id, last_error_.empty() ? "load failed" : last_error_);
            return;
        }
        control_.reply(command.id, control_state_json());
        return;
    }

    if (name == "cart.reload") {
        if (cart_path_.empty()) {
            control_.reply_error(command.id, "no cart loaded");
            return;
        }
        load_cart_path(cart_path_);
        if (!playing_) {
            control_.reply_error(command.id, last_error_.empty() ? "reload failed" : last_error_);
            return;
        }
        control_.reply(command.id, control_state_json());
        return;
    }

    if (name == "cart.eject") {
        eject_cart();
        control_.reply(command.id, "");
        return;
    }

    if (name == "debug.set") {
        // 与调试台同一处落地（debug_param_write）：agent 也能实时调卡带的可调参数
        if (!cart_) {
            control_.reply_error(command.id, "no cart loaded");
            return;
        }
        const std::string param = args.str("name");
        if (param.empty()) {
            control_.reply_error(command.id, "missing 'name'");
            return;
        }
        if (!args.has("value")) {
            control_.reply_error(command.id, "missing 'value'");
            return;
        }
        const double value = args.number("value", 0.0);
        if (!std::isfinite(value)) {
            control_.reply_error(command.id, "value must be a finite number");
            return;
        }
        bool written = false;
        const bool english = config_.language == "en";  // 按当前语言解析的名字匹配
        const std::string want_group = args.str("group");  // 可选：与 state.query 里的 group 一致（消歧）
        const auto group_of = [english](const Cartridge::DebugParamView& view) {
            std::string g;
            for (const Localized& seg : view.group) {
                if (!g.empty()) g += "/";
                g += seg.get(english);
            }
            return g;
        };
        int match = -1;
        int hits = 0;
        for (size_t i = 0; i < cart_->debug_param_count(); ++i) {
            const Cartridge::DebugParamView view = cart_->debug_param(i);
            if (view.name.get(english) != param) continue;
            if (!want_group.empty() && group_of(view) != want_group) continue;
            ++hits;
            if (match < 0) match = static_cast<int>(i);
        }
        if (hits == 0) {
            control_.reply_error(command.id, "no such param: " + param);
            return;
        }
        if (hits > 1) {  // 重名（如每件武器的"伤害"）：让调用方带上 group，别猜
            control_.reply_error(command.id, "ambiguous name; pass 'group': " + param);
            return;
        }
        written = cart_->debug_param_write(static_cast<size_t>(match), static_cast<float>(value));
        if (!written) {  // 卡带的 set 缺失或出错：如实回报，别假装写成功
            control_.reply_error(command.id, "cart rejected value for: " + param);
            return;
        }
        control_.reply(command.id,
                       "\"name\":" + json::quote(param) + ",\"value\":" + std::to_string(value));
        return;
    }

    if (name == "quit") {
        control_.reply(command.id, "");
        quit_ = true;
        return;
    }

    control_.reply_error(command.id, "unknown command: " + name);
}

} // namespace phos

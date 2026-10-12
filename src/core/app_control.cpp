#include "agent/cart_json.hpp"
#include "core/json_lite.hpp"
#include "cart/cart_scanner.hpp"
#include "core/app.hpp"
#include "core/log.hpp"
#include "render/renderer.hpp"
#include "render/screen_image.hpp"

#include <cstdio>
#include <cstring>
#include <sstream>

namespace phos {

namespace {

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
        << ",\"stepping\":" << (control_stepping_ ? "true" : "false")
        << ",\"pending_steps\":" << pending_steps_
        << ",\"grid_w\":" << screen_.width() << ",\"grid_h\":" << screen_.height()
        << ",\"content_w\":" << kContentW << ",\"content_h\":" << kContentH
        << ",\"panel_w\":" << host_.panel_w << ",\"seed\":" << rng_seed_
        << ",\"host_time\":" << host_.time
        << ",\"skin\":" << json::quote(skins_[skin_index_].id)
        << ",\"palette\":" << json::quote(active_palette_.id)
        << ",\"boot\":" << json::quote(boots_.empty() ? "" : boots_[boot_index_].id)
        << ",\"sound\":" << json::quote(sounds_.empty() ? "" : sounds_[sound_index_].id)
        << ",\"font\":" << json::quote(font_scheme_)
        << ",\"language\":" << json::quote(lang_name(shell_.language()))
        << ",\"cursor\":" << shell_.cursor()
        << ",\"shelf\":" << shelf_json()
        << ",\"crt_level\":" << config_.crt_level
        << ",\"fps\":" << config_.fps
        << ",\"render_fps\":" << host_.fps
        << ",\"merge_ms\":" << cart_merge_ms_
        << ",\"layers\":" << layers_json(host_.layers)
        << ",\"video\":" << json::quote(headless_ ? "headless" : "window")
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
            << ",\"name\":" << json::quote(info.name)
            << ",\"version\":" << json::quote(info.version)
            << ",\"author\":" << json::quote(info.author)
            << ",\"path\":" << json::quote(cart_path_)
            << ",\"sidebar_w\":" << info.sidebar_w
            << ",\"lua_mem_kb\":" << cart_->lua_memory_kb()
            << ",\"update_ms\":" << cart_update_ms_ << ",\"draw_ms\":" << cart_draw_ms_
            << ",\"update_peak_ms\":" << cart_update_peak_ms_
            << ",\"draw_peak_ms\":" << cart_draw_peak_ms_ << "}";
    } else {
        out << ",\"cart\":null";
    }
    if (!last_error_.empty()) out << ",\"last_error\":" << json::quote(last_error_);

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

    out << ",\"packs\":{\"skin\":" << pack_json(skins_, by_name)
        << ",\"skin_ids\":" << pack_json(skins_, by_id)
        << ",\"palette\":" << pack_json(palettes_, by_name)
        << ",\"palette_ids\":" << pack_json(palettes_, by_id)
        << ",\"boot\":" << pack_json(boots_, by_name)
        << ",\"boot_ids\":" << pack_json(boots_, by_id)
        << ",\"sound\":" << pack_json(sounds_, by_name)
        << ",\"sound_ids\":" << pack_json(sounds_, by_id)
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
    return "\"carts\":" + cart_list_json(scan_carts(kCartDir));
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
    if (step_request_id_ < 0) return;
    control_.reply(step_request_id_, control_state_json());
    step_request_id_ = -1;
}

void App::complete_frame_read(Renderer* renderer) {
    if (frame_read_id_ < 0) return;
    const int id = frame_read_id_;
    const std::string path = frame_read_path_;
    frame_read_id_ = -1;
    frame_read_path_.clear();

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
    for (auto it = pending_releases_.begin(); it != pending_releases_.end();) {
        if (--it->second <= 0) {
            input_.set_key(it->first, false);
            it = pending_releases_.erase(it);
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
        // layer = "screen" 读的同样是合并后的整屏（层是就地合并进 screen_ 的，没有
        // "合并前的那一层"可读），之所以收这个取值，只是让"我读的是整屏"能被显式写出来；
        // 其余按卡带注册的层名读那一层自己。层缓冲是内容区局部坐标，所以行数就是内容区高
        const std::string which = args.str("layer");
        const Screen* source = &screen_;
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
        frame_read_path_ = args.str("path");
        frame_read_id_ = command.id;
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
        pending_releases_.clear();
        control_.reply(command.id, "");
        return;
    }

    if (name == "time.step") {
        int frames = args.integer("frames", 1);
        if (frames < 1) frames = 1;
        control_stepping_ = true;
        pending_steps_ += frames;
        step_request_id_ = command.id;  // 全部推进完毕后再回包（确定性同步点）
        return;
    }

    if (name == "time.resume") {
        control_stepping_ = false;
        pending_steps_ = 0;
        step_request_id_ = -1;
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

    if (name == "quit") {
        control_.reply(command.id, "");
        quit_ = true;
        return;
    }

    control_.reply_error(command.id, "unknown command: " + name);
}

} // namespace phos

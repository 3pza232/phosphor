#include "app/agent_controller.hpp"

#include "agent/cart_json.hpp"
#include "agent/control_channel.hpp"
#include "api/host_api.hpp"
#include "cart/cart_scanner.hpp"
#include "cart/cartridge.hpp"
#include "cart/save_store.hpp"
#include "cart/scene.hpp"
#include "core/audio.hpp"
#include "core/defaults.hpp"
#include "core/input.hpp"
#include "core/json_lite.hpp"
#include "render/renderer.hpp"
#include "render/screen_image.hpp"
#include "shell/shell.hpp"

#include <cmath>
#include <cstddef>
#include <cstring>
#include <sstream>
#include <utility>
#include <string>
#include <vector>

namespace phos {

// ---------------------------------------------------------------- 单步会话胶水

bool AgentController::begin_step(AgentSession& session, int frames, int request_id,
                                 std::string& error) const {
    // 同一时刻只允许一条 time.step 在途：回包是"推进完毕"的同步点，两个请求共用
    // 一个回包 id 会让先到的那个永远等不到回包
    if (session.step_request_id >= 0) {
        error = "a time.step is already pending";
        return false;
    }
    if (frames < 1) frames = 1;
    if (frames > kMaxStepFrames) frames = kMaxStepFrames;
    session.stepping = true;
    session.pending_steps += frames;
    session.step_request_id = request_id;  // 全部推进完毕后再回包（确定性同步点）
    return true;
}

int AgentController::abandon_step(AgentSession& session) const {
    const int abandoned = session.step_request_id;  // 在途请求绝不能"消失"：调用方负责回错误
    session.stepping = false;
    session.pending_steps = 0;
    session.step_request_id = -1;
    return abandoned;
}

void AgentController::begin_frame_read(AgentSession& session, int request_id,
                                       const std::string& path) const {
    session.frame_read_path = path;
    session.frame_read_id = request_id;
}

void AgentController::clear_pending_inputs(AgentSession& session, Input& input) const {
    input.release_all();
    session.pending_releases.clear();
}

void AgentController::release_expired(AgentSession& session, Input& input) const {
    for (auto it = session.pending_releases.begin(); it != session.pending_releases.end();) {
        if (--it->second <= 0) {
            input.set_key(it->first, false);
            it = session.pending_releases.erase(it);
        } else {
            ++it;
        }
    }
}

void AgentController::complete_step(ControlChannel& channel, AgentSession& session,
                                    const std::function<std::string()>& state_json) const {
    if (session.step_request_id < 0) return;
    channel.reply(session.step_request_id, state_json());
    session.step_request_id = -1;
}

void AgentController::complete_frame_read(ControlChannel& channel, AgentSession& session,
                                          Renderer* renderer) const {
    if (session.frame_read_id < 0) return;
    const int id = session.frame_read_id;
    const std::string path = session.frame_read_path;
    session.frame_read_id = -1;
    session.frame_read_path.clear();

    // 无窗口（或渲染器尚未画过帧）时没有帧缓冲可读：如实报错，不静默返回空画面
    int width = 0, height = 0;
    std::vector<unsigned char> rgba;
    if (!renderer || !renderer->read_frame(rgba, width, height)) {
        channel.reply_error(id, "no framebuffer readable (frame.read needs the window path)");
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
            channel.reply_error(id, error);
            return;
        }
        out << ",\"path\":" << json::quote(path);
    }
    channel.reply(id, out.str());
}

// ---------------------------------------------------------------- 观察面

std::string AgentController::layers_json(const LayeredScreen& layers) {
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

std::string AgentController::scenes_json(const HostContext& host) {
    std::string out = "[";
    if (host.scenes != nullptr) {
        bool first = true;
        for (const SceneEntry& scene : host.scenes->entries()) {
            if (!first) out += ",";
            out += "{\"id\":" + json::quote(scene.id) +
                   ",\"modal\":" + (scene.modal ? "true" : "false") +
                   ",\"pause_world\":" + (scene.pause_world ? "true" : "false") +
                   ",\"audio_pause\":" + (scene.audio_pause ? "true" : "false") + "}";
            first = false;
        }
    }
    return out + "]";
}

std::string AgentController::screen_lines_json(const Screen& screen) {
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

std::string AgentController::carts_json(const std::string& cart_dir, bool english) const {
    // 字段集与 `--scan --json` 共用一份实现（agent/cart_json.hpp）
    // 这里刻意**重扫一次**目录而不是复用卡带架：控制通道是给工具用的，
    // 它要的是"磁盘上现在有什么"（含目录顺序），而不是玩家眼里的排序结果
    return "\"carts\":" + cart_list_json(scan_carts(cart_dir), english);
}

std::string AgentController::shelf_json(const Shell& shell) const {
    std::string ids;
    for (const auto& cart : shell.carts()) {
        if (!ids.empty()) ids += ",";
        ids += json::quote(cart.id);
    }
    return "[" + ids + "]";
}

std::string AgentController::state_json(const AgentState& state,
                                        const AgentSession& session) const {
    const HostContext& host = *state.host;
    const Screen& screen = *host.screen;
    std::ostringstream out;
    out << "\"frame\":" << state.frame << ",\"mode\":" << json::quote(state.mode)
        << ",\"playing\":" << (state.playing ? "true" : "false")
        << ",\"stepping\":" << (session.stepping ? "true" : "false")
        << ",\"pending_steps\":" << session.pending_steps
        << ",\"grid_w\":" << screen.width() << ",\"grid_h\":" << screen.height()
        << ",\"content_w\":" << kContentW << ",\"content_h\":" << kContentH
        << ",\"panel_w\":" << host.panel_w << ",\"seed\":" << state.seed
        << ",\"host_time\":" << host.time
        << ",\"skin\":" << json::quote(state.skin_id)
        << ",\"palette\":" << json::quote(state.palette_id)
        << ",\"boot\":" << json::quote(state.boot_id)
        << ",\"sound\":" << json::quote(state.sound_id)
        << ",\"font\":" << json::quote(state.font_name)
        << ",\"font_size\":" << state.font_px
        << ",\"font_size_max\":" << state.font_max_px
        << ",\"ime\":" << (host.ime_wanted ? "true" : "false")
        << ",\"language\":" << json::quote(state.language)
        << ",\"cursor\":" << state.cursor;
    std::string shelf;
    for (const std::string& id : state.shelf_ids) {
        if (!shelf.empty()) shelf += ",";
        shelf += json::quote(id);
    }
    out << ",\"shelf\":[" << shelf << "]"
        << ",\"crt_level\":" << state.crt_level << ",\"fps\":" << state.fps
        << ",\"render_fps\":" << host.fps << ",\"merge_ms\":" << state.merge_ms
        << ",\"layers\":" << layers_json(host.layers)
        << ",\"scenes\":" << scenes_json(host)
        << ",\"ui\":"
        << (state.playing && !host.cart_ui_json.empty() ? host.cart_ui_json : "null");

    out << ",\"debug_params\":[";
    for (size_t i = 0; i < state.debug_params.size(); ++i) {
        const AgentState::DebugParam& param = state.debug_params[i];
        out << (i ? "," : "") << "{\"name\":" << json::quote(param.name)
            << ",\"group\":" << json::quote(param.group)
            << ",\"kind\":" << json::quote(param.kind) << ",\"value\":" << param.value << "}";
    }
    out << "]";

    const Audio* audio = host.audio;
    out << ",\"video\":" << json::quote(state.headless ? "headless" : "window")
        << ",\"control_port\":" << state.control_port
        << ",\"music_volume\":" << state.music_volume
        << ",\"sfx_volume\":" << state.sfx_volume
        << ",\"audio\":" << (audio && audio->active() ? "true" : "false")
        << ",\"voices\":" << (audio ? audio->active_voices() : 0)
        << ",\"dropped\":" << (audio ? audio->dropped_requests() : 0)
        << ",\"music\":{\"on\":" << (audio && audio->music_on() ? "true" : "false")
        << ",\"section\":" << json::quote(audio ? audio->music_section() : std::string())
        << ",\"index\":" << (audio ? audio->music_section_index() : 0)
        << ",\"count\":" << (audio ? audio->music_section_count() : 0) << "}";

    if (state.has_cart) {
        out << ",\"cart\":{\"id\":" << json::quote(state.cart_id)
            << ",\"name\":" << json::quote(state.cart_name)
            << ",\"version\":" << json::quote(state.cart_version)
            << ",\"author\":" << json::quote(state.cart_author)
            << ",\"path\":" << json::quote(state.cart_path)
            << ",\"sidebar_w\":" << state.sidebar_w << ",\"lua_mem_kb\":" << state.lua_mem_kb
            << ",\"update_ms\":" << state.update_ms << ",\"draw_ms\":" << state.draw_ms
            << ",\"update_peak_ms\":" << state.update_peak_ms
            << ",\"draw_peak_ms\":" << state.draw_peak_ms << "}";
    } else {
        out << ",\"cart\":null";
    }
    out << ",\"last_error\":" << json::quote(state.last_error);

    const auto pack_json = [](const std::vector<AgentState::Pack>& packs, bool by_name) {
        std::string list;
        for (const AgentState::Pack& pack : packs) {
            if (!list.empty()) list += ",";
            list += json::quote(by_name ? pack.name : pack.id);
        }
        return "[" + list + "]";
    };
    out << ",\"save\":{\"available\":" << (state.save_available ? "true" : "false")
        << ",\"entries\":" << state.save_entries << "}"
        << ",\"packs\":{\"skin\":" << pack_json(state.skins, true)
        << ",\"skin_ids\":" << pack_json(state.skins, false)
        << ",\"palette\":" << pack_json(state.palettes, true)
        << ",\"palette_ids\":" << pack_json(state.palettes, false)
        << ",\"boot\":" << pack_json(state.boots, true)
        << ",\"boot_ids\":" << pack_json(state.boots, false)
        << ",\"sound\":" << pack_json(state.sounds, true)
        << ",\"sound_ids\":" << pack_json(state.sounds, false)
        << ",\"shelf\":" << pack_json(state.shelves, true)
        << ",\"shelf_ids\":" << pack_json(state.shelves, false)
        << ",\"font\":[";
    for (size_t i = 0; i < state.font_names.size(); ++i)
        out << (i ? "," : "") << json::quote(state.font_names[i]);
    out << "]}";

    std::string held;
    for (const std::string& name : state.held_keys) {
        if (!held.empty()) held += ",";
        held += json::quote(name);
    }
    out << ",\"held_keys\":[" << held << "]";
    return out.str();
}

void AgentController::execute(const ControlCommand& command, ControlChannel& channel,
                              AgentSession& session, const AgentServices& services) const {
    const std::string& name = command.name;
    const json::Object& args = command.args;

    if (name == "ping") {
        channel.reply(command.id, "\"pong\":true");
        return;
    }

    if (name == "screen.read") {
        // 默认读**合并结果**（整屏，与既有语义一致）；带 layer 时读单份内容：
        // layer = "screen" 读的同样是合并后的整屏（层是就地合并进屏幕缓冲的，没有
        // "合并前的那一层"可读），之所以收这个取值，只是让"我读的是整屏"能被显式写出来；
        // 其余按卡带注册的层名读那一层自己。层缓冲是内容区局部坐标，所以行数就是内容区高
        const std::string which = args.str("layer");
        const Screen* source = services.screen();
        std::string label = "merged";
        const LayeredScreen* layers = services.layers();
        if (!which.empty() && which != "screen") {
            const Layer* layer = layers->find(which);
            if (!layer) {
                channel.reply_error(command.id, "no such layer: " + which);
                return;
            }
            source = &layer->cells;
            label = which;
        } else if (which == "screen") {
            label = "screen";
        }
        std::ostringstream payload;
        payload << "\"layer\":" << json::quote(label) << ",\"width\":" << source->width()
                << ",\"height\":" << source->height() << ",\"frame\":" << services.frame()
                << ",\"lines\":" << screen_lines_json(*source);
        channel.reply(command.id, payload.str());
        return;
    }

    if (name == "screenshot") {
        const std::string path = args.str("path");
        if (path.empty()) {
            channel.reply_error(command.id, "missing 'path'");
            return;
        }
        int width = 0, height = 0;
        std::string error;
        if (!services.screenshot(path, width, height, error)) {
            channel.reply_error(command.id, error);
            return;
        }
        channel.reply(command.id, "\"path\":" + json::quote(path) + ",\"width\":" +
                                       std::to_string(width) + ",\"height\":" +
                                       std::to_string(height));
        return;
    }

    if (name == "frame.read") {
        // 读的是 GL 渲染出的真实帧（含着色器与逐层叠画），与 CPU 光栅化的 screenshot 互补。
        // 无头没有帧缓冲，直接报错；有窗口时只登记请求——读回必须落在"画完这一帧、swap
        // 之前"，那个时机只有渲染循环掌握（见 complete_frame_read）
        if (services.headless()) {
            channel.reply_error(command.id, "no framebuffer in headless mode (use screenshot)");
            return;
        }
        begin_frame_read(session, command.id, args.str("path"));
        return;
    }

    if (name == "save.export") {
        SaveStore* save = services.save();
        if (!save) {
            channel.reply_error(command.id, "loaded cart has no save store");
            return;
        }
        channel.reply(command.id, "\"code\":" + json::quote(save->export_code()));
        return;
    }

    if (name == "save.import") {
        SaveStore* save = services.save();
        if (!save) {
            channel.reply_error(command.id, "loaded cart has no save store");
            return;
        }
        const std::string code = args.str("code");
        if (code.empty()) {
            channel.reply_error(command.id, "missing 'code'");
            return;
        }
        if (!save->import_code(code)) {
            channel.reply_error(command.id, "invalid tape code");
            return;
        }
        channel.reply(command.id, "\"entries\":" + std::to_string(save->size()));
        return;
    }

    if (name == "state.query") {
        std::string payload = services.state_json();
        Cartridge* cart = services.cart();

        // 深入卡带 Lua 状态：显式路径查询 + 卡带自报的 debug_state()
        if (args.has("path")) {
            const std::string path = args.str("path");
            const std::string value = cart ? cart->global_json(path) : std::string();
            payload += ",\"path\":" + json::quote(path) +
                       ",\"value\":" + (value.empty() ? "null" : value);
        }
        if (cart) {
            const std::string debug = cart->debug_state_json();
            if (!debug.empty()) payload += ",\"debug\":" + debug;
        }

        channel.reply(command.id, payload);
        return;
    }

    if (name == "carts.scan") {
        // 与 --scan --json 共用 cart_json 实现；英文标志跟当前界面语言
        channel.reply(command.id, carts_json(services.cart_dir(), services.english()));
        return;
    }

    if (name == "input.inject") {
        const std::string key_name = args.str("key");
        InputAction action;
        if (!services.make_input_action(key_name, args.flag("down", true), action)) {
            channel.reply_error(command.id, "unknown key: " + key_name);
            return;
        }

        // 主机保留键可能是"关机"：先回包再执行，避免回包与进程退出竞争。
        // frames 照传：卡带接管 Esc 时它已按普通键处理（要能按帧释放），其余主机键忽略它
        if (!action.host_key.empty()) {
            channel.reply(command.id, "\"host_key\":" + json::quote(action.host_key));
            services.apply_input(action, args.integer("frames", 0));
            return;
        }

        services.apply_input(action, args.integer("frames", 0));
        channel.reply(command.id, services.state_json());
        return;
    }

    // 注入文本：与玩家敲键盘等价（UTF-8，可含多字节字符）。文本只在下一逻辑帧可见
    if (name == "input.text") {
        services.input()->push_text(args.str("text"));
        channel.reply(command.id, services.state_json());
        return;
    }

    if (name == "input.clear") {
        clear_pending_inputs(session, *services.input());
        channel.reply(command.id, "");
        return;
    }

    if (name == "time.step") {
        // 单步语义（在途判定/帧数钳制/登记回包 id）在本类，这里只转错误
        std::string error;
        if (!begin_step(session, args.integer("frames", 1), command.id, error)) {
            channel.reply_error(command.id, error);
            return;
        }
        return;
    }

    if (name == "time.resume") {
        // 在途的 time.step 绝不能"消失"：它的发起方正在等"推进完毕"这个同步点。
        // 恢复实时 = 放弃剩余帧数，必须立刻回一个明确的错误，否则 agent 永久挂起
        const int abandoned = abandon_step(session);
        if (abandoned >= 0)
            channel.reply_error(abandoned, "time.step abandoned by time.resume");
        channel.reply(command.id, services.state_json());
        return;
    }

    if (name == "cart.load") {
        const std::string path = args.str("path");
        if (path.empty()) {
            channel.reply_error(command.id, "missing 'path'");
            return;
        }
        services.load_cart(path);
        if (!services.playing()) {
            const std::string error = services.last_error();
            channel.reply_error(command.id, error.empty() ? "load failed" : error);
            return;
        }
        channel.reply(command.id, services.state_json());
        return;
    }

    if (name == "cart.reload") {
        const std::string path = services.cart_path();
        if (path.empty()) {
            channel.reply_error(command.id, "no cart loaded");
            return;
        }
        services.load_cart(path);
        if (!services.playing()) {
            const std::string error = services.last_error();
            channel.reply_error(command.id, error.empty() ? "reload failed" : error);
            return;
        }
        channel.reply(command.id, services.state_json());
        return;
    }

    if (name == "cart.eject") {
        services.eject_cart();
        channel.reply(command.id, "");
        return;
    }

    if (name == "debug.set") {
        // 与调试台同一处落地（debug_param_write）：agent 也能实时调卡带的可调参数
        Cartridge* cart = services.cart();
        if (!cart) {
            channel.reply_error(command.id, "no cart loaded");
            return;
        }
        const std::string param = args.str("name");
        if (param.empty()) {
            channel.reply_error(command.id, "missing 'name'");
            return;
        }
        if (!args.has("value")) {
            channel.reply_error(command.id, "missing 'value'");
            return;
        }
        const double value = args.number("value", 0.0);
        if (!std::isfinite(value)) {
            channel.reply_error(command.id, "value must be a finite number");
            return;
        }
        const bool english = services.english();  // 按当前语言解析的名字匹配
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
        for (size_t i = 0; i < cart->debug_param_count(); ++i) {
            const Cartridge::DebugParamView view = cart->debug_param(i);
            if (view.name.get(english) != param) continue;
            if (!want_group.empty() && group_of(view) != want_group) continue;
            ++hits;
            if (match < 0) match = static_cast<int>(i);
        }
        if (hits == 0) {
            channel.reply_error(command.id, "no such param: " + param);
            return;
        }
        if (hits > 1) {  // 重名（如每件武器的"伤害"）：让调用方带上 group，别猜
            channel.reply_error(command.id, "ambiguous name; pass 'group': " + param);
            return;
        }
        const bool written =
            cart->debug_param_write(static_cast<size_t>(match), static_cast<float>(value));
        if (!written) {  // 卡带的 set 缺失或出错：如实回报，别假装写成功
            channel.reply_error(command.id, "cart rejected value for: " + param);
            return;
        }
        channel.reply(command.id,
                      "\"name\":" + json::quote(param) + ",\"value\":" + std::to_string(value));
        return;
    }

    if (name == "ui.list") {
        const std::string ui_json = services.cart_ui_json();
        channel.reply(command.id, std::string("\"ui\":") + (ui_json.empty() ? "null" : ui_json));
        return;
    }

    if (name == "ui.focus" || name == "ui.activate") {
        const std::string id = args.str("id");
        if (id.empty()) {
            channel.reply_error(command.id, "missing 'id'");
            return;
        }
        if (!services.cart()) {
            channel.reply_error(command.id, "no cart loaded");
            return;
        }
        // 请求排队到下一帧的 render 生效（与玩家按键同一帧语义：下一逻辑帧可见结果）
        services.queue_ui(id, name == "ui.focus");
        channel.reply(command.id, "\"queued\":true");
        return;
    }

    if (name == "quit") {
        channel.reply(command.id, "");
        services.request_quit();
        return;
    }

    channel.reply_error(command.id, "unknown command: " + name);
}

} // namespace phos

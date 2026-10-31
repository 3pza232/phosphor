#include "app/app.hpp"

#include "core/json_lite.hpp"
#include "core/log.hpp"

#include <cmath>
#include <sstream>

namespace phos {

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
        << ",\"playing\":" << (playing() ? "true" : "false")
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
        << ",\"font\":" << json::quote(fonts_.current())
        << ",\"font_size\":" << font_px_  // 当前字号 = 单元格像素边长（整机缩放）
        << ",\"font_size_max\":" << fonts_.max_px()  // 可调上限（由字体方案声明，Mod 可抬高）
        // 本帧是否有输入框在"举手要中文"：卡带声明 ime=true 的框被 feed，或卡带架搜索在输入。
        // 主机据此开关系统输入法（仅 Windows 实际生效），也给测试一个可读的信号
        << ",\"ime\":" << (host_.ime_wanted ? "true" : "false")
        << ",\"language\":" << json::quote(lang_name(shell_.language()))
        << ",\"cursor\":" << (playing() ? -1 : shell_.cursor())
        << ",\"shelf\":" << agent_controller_.shelf_json(shell_)
        << ",\"crt_level\":" << config_.crt_level
        << ",\"fps\":" << config_.fps
        << ",\"render_fps\":" << host_.fps
        << ",\"merge_ms\":" << timing_.merge_ms
        << ",\"layers\":" << AgentController::layers_json(host_.layers)
        << ",\"scenes\":" << AgentController::scenes_json(host_)
        // 卡带声明式界面的控件树（id/role/label/state）：agent 用它定位控件，
        // 不必解析文本画面；没有界面时为 null
        << ",\"ui\":" << (playing() && !host_.cart_ui_json.empty() ? host_.cart_ui_json : "null");

    // 卡带注册的可调参数（phos.debug.number）当前值；无卡带或未注册为空数组
    out << ",\"debug_params\":[";
    if (cart()) {
        const bool english = config_.language == "en";  // 名字按当前语言给，与人看到的篮子一致
        const size_t count = cart()->debug_param_count();
        for (size_t i = 0; i < count; ++i) {
            const Cartridge::DebugParamView view = cart()->debug_param(i);
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

    if (cart()) {
        const CartInfo& info = cart()->info();
        out << ",\"cart\":{\"id\":" << json::quote(info.id)
            << ",\"name\":" << json::quote(info.name.get(config_.language == "en"))
            << ",\"version\":" << json::quote(info.version)
            << ",\"author\":" << json::quote(info.author)
            << ",\"path\":" << json::quote(cart_path_)
            << ",\"sidebar_w\":" << info.sidebar_w
            << ",\"lua_mem_kb\":" << cart()->lua_memory_kb()
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
        // 卡带架样式包：与其它内容包同一份清单（显示名 + 稳定 id），当前选中项见 config.shelf_style
        << ",\"shelf\":" << pack_json(packs_.shelves, by_name)
        << ",\"shelf_ids\":" << pack_json(packs_.shelves, by_id)
        << ",\"font\":[";
    for (size_t i = 0; i < fonts_.names().size(); ++i)
        out << (i ? "," : "") << json::quote(fonts_.names()[i]);
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

void App::complete_step_request() {
    agent_controller_.complete_step(control_, agent_, [this] { return control_state_json(); });
}

void App::complete_frame_read(Renderer* renderer) {
    agent_controller_.complete_frame_read(control_, agent_, renderer);
}

void App::release_expired_inputs() {
    agent_controller_.release_expired(agent_, input_);
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
                << ",\"lines\":" << AgentController::screen_lines_json(*source);
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
        agent_controller_.begin_frame_read(agent_, command.id, args.str("path"));
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
            const std::string value = cart() ? cart()->global_json(path) : std::string();
            payload += ",\"path\":" + json::quote(path) +
                       ",\"value\":" + (value.empty() ? "null" : value);
        }
        if (cart()) {
            const std::string debug = cart()->debug_state_json();
            if (!debug.empty()) payload += ",\"debug\":" + debug;
        }

        control_.reply(command.id, payload);
        return;
    }

    if (name == "carts.scan") {
        // 与 --scan --json 共用 cart_json 实现；英文标志跟当前界面语言
        control_.reply(command.id,
                       agent_controller_.carts_json(kCartDir, config_.language == "en"));
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
        agent_controller_.clear_pending_inputs(agent_, input_);
        control_.reply(command.id, "");
        return;
    }

    if (name == "time.step") {
        // 单步语义（在途判定/帧数钳制/登记回包 id）在 AgentController，这里只转错误
        std::string error;
        if (!agent_controller_.begin_step(agent_, args.integer("frames", 1), command.id, error)) {
            control_.reply_error(command.id, error);
            return;
        }
        return;
    }

    if (name == "time.resume") {
        // 在途的 time.step 绝不能"消失"：它的发起方正在等"推进完毕"这个同步点。
        // 恢复实时 = 放弃剩余帧数，必须立刻回一个明确的错误，否则 agent 永久挂起
        const int abandoned = agent_controller_.abandon_step(agent_);
        if (abandoned >= 0)
            control_.reply_error(abandoned, "time.step abandoned by time.resume");
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
        if (!playing()) {
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
        if (!playing()) {
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
        if (!cart()) {
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
        for (size_t i = 0; i < cart()->debug_param_count(); ++i) {
            const Cartridge::DebugParamView view = cart()->debug_param(i);
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
        written = cart()->debug_param_write(static_cast<size_t>(match), static_cast<float>(value));
        if (!written) {  // 卡带的 set 缺失或出错：如实回报，别假装写成功
            control_.reply_error(command.id, "cart rejected value for: " + param);
            return;
        }
        control_.reply(command.id,
                       "\"name\":" + json::quote(param) + ",\"value\":" + std::to_string(value));
        return;
    }

    if (name == "ui.list") {
        control_.reply(command.id, std::string("\"ui\":") +
                                       (host_.cart_ui_json.empty() ? "null" : host_.cart_ui_json));
        return;
    }

    if (name == "ui.focus" || name == "ui.activate") {
        const std::string id = args.str("id");
        if (id.empty()) {
            control_.reply_error(command.id, "missing 'id'");
            return;
        }
        if (!cart()) {
            control_.reply_error(command.id, "no cart loaded");
            return;
        }
        // 请求排队到下一帧的 render 生效（与玩家按键同一帧语义：下一逻辑帧可见结果）
        if (name == "ui.focus")
            host_.pending_ui_focus = id;
        else
            host_.pending_ui_activate = id;
        control_.reply(command.id, "\"queued\":true");
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
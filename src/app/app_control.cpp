#include "app/app.hpp"

#include "core/log.hpp"
#include "shell/messages.hpp"

#include <cstddef>
#include <optional>
#include <string>

namespace phos {

void App::init_agent_services() {
    agent_services_.state_json = [this] { return control_state_json(); };
    agent_services_.screen = [this] { return host_.screen; };
    agent_services_.layers = [this] { return &host_.layers; };
    agent_services_.frame = [this] { return frame_count_; };
    agent_services_.headless = [this] { return headless_; };
    agent_services_.screenshot = [this](const std::string& path, int& width, int& height,
                                        std::string& error) {
        return write_screenshot(path, width, height, error);
    };
    agent_services_.save = [this] { return host_.save; };
    agent_services_.cart = [this] { return cart(); };
    agent_services_.cart_path = [this] { return cart_path_; };
    agent_services_.cart_dir = [] { return std::string(kCartDir); };
    agent_services_.load_cart = [this](const std::string& path) { load_cart_path(path); };
    agent_services_.eject_cart = [this] { eject_cart(); };
    agent_services_.playing = [this] { return playing(); };
    agent_services_.last_error = [this] { return last_error_; };
    agent_services_.english = [this] { return config_.language == "en"; };
    agent_services_.input = [this] { return &input_; };
    agent_services_.make_input_action = [](const std::string& key, bool down, InputAction& action) {
        const std::optional<InputAction> made = input_action_from(key, down);
        if (!made) return false;
        action = *made;
        return true;
    };
    agent_services_.apply_input = [this](const InputAction& action, int hold_frames) {
        apply_input_action(action, hold_frames);
    };
    agent_services_.request_quit = [this] { quit_ = true; };
    agent_services_.cart_ui_json = [this] { return host_.cart_ui_json; };
    agent_services_.queue_ui = [this](const std::string& id, bool focus) {
        if (focus)
            host_.pending_ui_focus = id;
        else
            host_.pending_ui_activate = id;
    };
}

AgentState App::capture_agent_state() const {
    AgentState state;
    state.host = &host_;
    state.frame = frame_count_;
    state.mode = mode_name();
    state.playing = playing();
    state.headless = headless_;
    state.control_port = control_port_;
    state.seed = rng_seed_;
    state.cart_path = cart_path_;
    state.last_error = last_error_;
    state.crt_level = config_.crt_level;
    state.fps = config_.fps;
    state.music_volume = config_.music_volume;
    state.sfx_volume = config_.sfx_volume;
    state.skin_id = packs_.skin().id;
    state.palette_id = active_palette_.id;
    if (!packs_.boots.empty())
        state.boot_id = packs_.boots[static_cast<size_t>(packs_.boot_index)].id;
    if (!packs_.sounds.empty())
        state.sound_id = packs_.sounds[static_cast<size_t>(packs_.sound_index)].id;
    state.font_name = fonts_.current();
    state.font_px = font_px_;
    state.font_max_px = fonts_.max_px();
    state.language = lang_name(shell_.language());
    state.cursor = playing() ? -1 : shell_.cursor();
    for (const CartInfo& cart_info : shell_.carts()) state.shelf_ids.push_back(cart_info.id);
    for (const std::string& key : input_.names())
        if (input_.down(key)) state.held_keys.push_back(key);
    for (const std::string& font : fonts_.names()) state.font_names.push_back(font);

    const auto append_packs = [](auto& out, const auto& packs) {
        out.reserve(packs.size());
        for (const auto& pack : packs) out.push_back(AgentState::Pack{pack.name, pack.id});
    };
    append_packs(state.skins, packs_.skins);
    append_packs(state.palettes, packs_.palettes);
    append_packs(state.boots, packs_.boots);
    append_packs(state.sounds, packs_.sounds);
    append_packs(state.shelves, packs_.shelves);

    const bool english = config_.language == "en";
    if (cart()) {
        state.has_cart = true;
        const CartInfo& info = cart()->info();
        state.cart_id = info.id;
        state.cart_name = info.name.get(english);
        state.cart_version = info.version;
        state.cart_author = info.author;
        state.sidebar_w = info.sidebar_w;
        state.lua_mem_kb = cart()->lua_memory_kb();
        for (size_t i = 0; i < cart()->debug_param_count(); ++i) {
            const Cartridge::DebugParamView view = cart()->debug_param(i);
            // 分组路径用 '/' 拼成串（json_lite 不解析数组）：同名参数靠它区分
            std::string group;
            for (const Localized& segment : view.group) {
                if (!group.empty()) group += "/";
                group += segment.get(english);
            }
            const char* kind = view.kind == DebugKind::integer ? "integer"
                               : view.kind == DebugKind::boolean ? "boolean"
                                                                 : "number";
            state.debug_params.push_back(
                AgentState::DebugParam{view.name.get(english), group, kind, view.value});
        }
    }
    state.merge_ms = timing_.merge_ms;
    state.update_ms = timing_.update_ms;
    state.draw_ms = timing_.draw_ms;
    state.update_peak_ms = timing_.update_peak_ms;
    state.draw_peak_ms = timing_.draw_peak_ms;
    if (host_.save) {
        state.save_available = true;
        state.save_entries = host_.save->size();
    }
    return state;
}

void App::poll_control() {
    if (!control_.running()) return;
    for (const ControlCommand& command : control_.take_commands()) {
        // 逐条记日志：把 agent 的整段操作与主机事件放在同一条时间线上
        log::info("control #" + std::to_string(command.id) + " " + command.name);
        execute_control(command);
    }
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

std::string App::control_state_json() const {
    return agent_controller_.state_json(capture_agent_state(), agent_);
}

void App::execute_control(const ControlCommand& command) {
    // 命令语义全部在 AgentController；App 只提供动作与状态快照
    agent_controller_.execute(command, control_, agent_, agent_services_);
}

} // namespace phos

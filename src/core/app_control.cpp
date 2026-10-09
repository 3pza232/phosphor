#include "agent/cart_json.hpp"
#include "agent/json_lite.hpp"
#include "cart/cart_scanner.hpp"
#include "core/app.hpp"
#include "core/log.hpp"

#include <cstdio>
#include <sstream>

namespace phos {

namespace {

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
        << ",\"pending_steps\":" << pending_steps_ << ",\"fps\":" << fps_
        << ",\"grid_w\":" << screen_.width() << ",\"grid_h\":" << screen_.height()
        << ",\"content_w\":" << kContentW << ",\"content_h\":" << kContentH
        << ",\"panel_w\":" << host_.panel_w << ",\"seed\":" << rng_seed_
        << ",\"host_time\":" << host_.time
        << ",\"skin\":" << json::quote(skins_[skin_index_].id)
        << ",\"filter\":" << json::quote(active_filter_.id)
        << ",\"boot\":" << json::quote(boots_.empty() ? "" : boots_[boot_index_].id)
        << ",\"sound\":" << json::quote(sounds_.empty() ? "" : sounds_[sound_index_].id)
        << ",\"font\":" << json::quote(font_scheme_)
        << ",\"language\":" << json::quote(lang_name(shell_.language()))
        << ",\"cursor\":" << shell_.cursor()
        << ",\"crt_level\":" << config_.crt_level
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

    // 内容包列表：名称即文件夹名，列表长度应与 theme/<类型>/ 下的文件夹数一致
    auto names_json = [](const auto& packs) {
        std::string out;
        for (const auto& pack : packs) {
            if (!out.empty()) out += ",";
            out += json::quote(pack.name);
        }
        return "[" + out + "]";
    };
    out << ",\"save\":{\"available\":" << (host_.save ? "true" : "false")
        << ",\"entries\":" << (host_.save ? host_.save->size() : 0) << "}";

    out << ",\"packs\":{\"skin\":" << names_json(skins_) << ",\"filter\":" << names_json(filters_)
        << ",\"boot\":" << names_json(boots_) << ",\"sound\":" << names_json(sounds_)
        << ",\"font\":[";
    for (size_t i = 0; i < font_schemes_.size(); ++i)
        out << (i ? "," : "") << json::quote(font_schemes_[i]);
    out << "]}";

    std::string held;
    for (const auto& [key, name] : kAllKeys) {
        if (!input_.down(key)) continue;
        if (!held.empty()) held += ",";
        held += json::quote(name);
    }
    out << ",\"held_keys\":[" << held << "]";
    return out.str();
}

std::string App::carts_json() const {
    // 字段集与 `--scan --json` 共用一份实现（agent/cart_json.hpp）
    return "\"carts\":" + cart_list_json(scan_carts(kCartDir));
}

void App::complete_step_request() {
    if (step_request_id_ < 0) return;
    control_.reply(step_request_id_, control_state_json());
    step_request_id_ = -1;
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
        std::ostringstream payload;
        payload << "\"width\":" << screen_.width() << ",\"height\":" << screen_.height()
                << ",\"frame\":" << frame_count_ << ",\"lines\":" << screen_lines_json(screen_);
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

        // 主机保留键可能是"关机"：先回包再执行，避免回包与进程退出竞争
        if (!action->host_key.empty()) {
            control_.reply(command.id, "\"host_key\":" + json::quote(action->host_key));
            apply_input_action(*action);
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

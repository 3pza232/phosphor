#include "app/agent_controller.hpp"

#include "agent/cart_json.hpp"
#include "agent/control_channel.hpp"
#include "api/host_api.hpp"
#include "cart/cart_scanner.hpp"
#include "cart/scene.hpp"
#include "core/input.hpp"
#include "core/json_lite.hpp"
#include "render/renderer.hpp"
#include "render/screen_image.hpp"
#include "shell/shell.hpp"

#include <cmath>
#include <cstddef>
#include <cstring>
#include <sstream>
#include <vector>

namespace phos {

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
    // 架上的顺序（玩家眼里的：最近打开优先），与 carts.scan 的目录顺序不同。
    // 两者都暴露，是因为用途不同：扫描列表回答"磁盘上有什么"，
    // 这一份回答"数到第几张能插进去哪张"——cursor 就是它的下标
    std::string ids;
    for (const auto& cart : shell.carts()) {
        if (!ids.empty()) ids += ",";
        ids += json::quote(cart.id);
    }
    return "[" + ids + "]";
}

} // namespace phos

#include "agent/debug_console.hpp"

#include <imgui.h>
#include <backends/imgui_impl_glfw.h>
#include <backends/imgui_impl_opengl3.h>

namespace phos {

bool DebugConsole::init(GLFWwindow* window, const std::vector<std::string>& font_files,
                        std::string& err) {
    IMGUI_CHECKVERSION();
    ImGui::CreateContext();
    ImGui::StyleColorsDark();

    // 仪表盘布局不需要跨会话记忆，关掉 ImGui 的 imgui.ini：
    // 程序包目录只应出现主机自己的文件（config.json / saves/），
    // 不该因为"开了一次调试面板"就多出一个 ini
    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr;

    // 面板会显示卡带注册的**中文**参数名，而 ImGui 默认字体没有 CJK 字形（会显示成 ????）。
    // 用引擎字体链合并出一份面板字体：主字体给 ASCII 观感、回退字体（font-cn）补 CJK。
    // ImGui 1.92 的字形是**按需加载**（glyph ranges 已是 legacy，传不传都一样）：合并源里
    // 谁能画出某码点就用谁，故 ranges 传 nullptr 即可。加载失败退回默认字体（中文会显示成 ?）
    if (!font_files.empty()) {
        if (io.Fonts->AddFontFromFileTTF(font_files[0].c_str(), 16.0f, nullptr, nullptr)) {
            for (size_t i = 1; i < font_files.size(); ++i) {
                ImFontConfig merge_cfg;
                merge_cfg.MergeMode = true;
                io.Fonts->AddFontFromFileTTF(font_files[i].c_str(), 16.0f, &merge_cfg, nullptr);
            }
        }
    }

    // install_callbacks=true 时，ImGui 回调链在主机已注册的键盘回调之后
    if (!ImGui_ImplGlfw_InitForOpenGL(window, true)) {
        err = "ImGui GLFW 后端初始化失败";
        return false;
    }
    if (!ImGui_ImplOpenGL3_Init("#version 330")) {
        err = "ImGui OpenGL3 后端初始化失败";
        return false;
    }
    initialized_ = true;
    return true;
}

void DebugConsole::shutdown() {
    if (!initialized_) return;
    ImGui_ImplOpenGL3_Shutdown();
    ImGui_ImplGlfw_Shutdown();
    ImGui::DestroyContext();
    initialized_ = false;
}

void DebugConsole::render(const DebugInfo& info) {
    if (!open || !initialized_) {
        wants_input_ = false;
        return;
    }

    ImGui_ImplOpenGL3_NewFrame();
    ImGui_ImplGlfw_NewFrame();
    ImGui::NewFrame();

    ImGui::SetNextWindowPos(ImVec2(10, 10), ImGuiCond_FirstUseEver);
    ImGui::SetNextWindowSize(ImVec2(430, 620), ImGuiCond_FirstUseEver);
    ImGui::Begin("PHOSPHOR INSTRUMENTS", &open);

    if (ImGui::CollapsingHeader("PERFORMANCE", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Text("fps            %.1f  (%.2f ms/frame)", info.fps, info.frame_ms);
        ImGui::Text("render frame   %ld", info.frame);
        ImGui::Text("logic rate     %d Hz (fixed step)", info.logic_hz);
        ImGui::Text("host time      %.2f s", info.host_time);
    }

    if (ImGui::CollapsingHeader("HOST", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Text("mode           %s%s", info.mode.c_str(), info.playing ? "  (cart running)" : "");
        ImGui::Text("grid           %d x %d chars", info.grid_w, info.grid_h);
        ImGui::Text("content        %d x %d", info.content_w, info.content_h);
        ImGui::Text("sidebar panel  %d cols", info.panel_w);
        ImGui::Text("rng seed       %u", info.rng_seed);
    }

    if (ImGui::CollapsingHeader("CARTRIDGE", ImGuiTreeNodeFlags_DefaultOpen)) {
        if (info.cart_id.empty()) {
            ImGui::TextUnformatted("(no cart inserted)");
        } else {
            ImGui::Text("id             %s", info.cart_id.c_str());
            ImGui::Text("name           %s", info.cart_name.c_str());
            ImGui::Text("version        %s", info.cart_version.c_str());
            ImGui::Text("author         %s", info.cart_author.c_str());
            ImGui::Text("update / draw  %.3f ms / %.3f ms", info.update_ms, info.draw_ms);
            ImGui::Text("lua heap       %d KB", info.lua_mem_kb);
            if (!info.cart_error.empty())
                ImGui::TextColored(ImVec4(1, 0.4f, 0.4f, 1), "error: %s", info.cart_error.c_str());
        }
    }

    if (ImGui::CollapsingHeader("CART PARAMS", ImGuiTreeNodeFlags_DefaultOpen)) {
        if (!info.params || info.params->empty()) {
            ImGui::TextUnformatted("(cart exposes no params via phos.debug.number)");
        } else {
            for (auto& p : *info.params) {
                if (!p.readable) {
                    ImGui::TextDisabled("%s  (unreadable)", p.name.c_str());
                    continue;
                }
                if (ImGui::SliderFloat(p.name.c_str(), &p.value, p.min, p.max, "%.3f"))
                    p.changed = true;
            }
            ImGui::TextDisabled("edits apply next frame");
        }
    }

    if (ImGui::CollapsingHeader("CONTENT & SHELL", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::Text("console theme  %s", info.skin_name.c_str());
        ImGui::Text("boot animation %s", info.boot_name.c_str());
        ImGui::Text("shelf view     %s", info.shelf_style.c_str());
        ImGui::Text("crt level      %s", info.crt_level_name.c_str());
        ImGui::Text("volume         music %d%%  sfx %d%%", info.music_volume, info.sfx_volume);

        if (info.crt) {
            ImGui::SliderFloat("scanline", &info.crt->scanline, 0.0f, 1.0f, "%.2f");
            ImGui::SliderFloat("aperture mask", &info.crt->mask, 0.0f, 1.0f, "%.2f");
            ImGui::SliderFloat("glow", &info.crt->glow, 0.0f, 1.0f, "%.2f");
            float rgb[3] = {info.crt->tint.r / 255.0f, info.crt->tint.g / 255.0f,
                            info.crt->tint.b / 255.0f};
            if (ImGui::ColorEdit3("tube tint", rgb)) {
                auto to8 = [](float v) {
                    return static_cast<uint8_t>(v < 0.0f ? 0.0f : (v > 1.0f ? 255.0f : v * 255.0f));
                };
                info.crt->tint.r = to8(rgb[0]);
                info.crt->tint.g = to8(rgb[1]);
                info.crt->tint.b = to8(rgb[2]);
            }
        }
    }

    if (ImGui::CollapsingHeader("INPUT (live)", ImGuiTreeNodeFlags_DefaultOpen)) {
        ImGui::TextDisabled("` toggle  |  Esc closes panel  |  keys pass through unless editing");
        auto join = [](const std::vector<std::string>& v) {
            std::string out;
            for (size_t i = 0; i < v.size(); ++i) out += (i ? " " : "") + v[i];
            return out.empty() ? std::string("-") : out;
        };
        ImGui::Text("held           %s", join(info.held_keys).c_str());
        ImGui::Text("edges          %s", join(info.edge_keys).c_str());
    }

    ImGui::End();

    // 仅在真正操作控件（拖动滑块/取色/输入）时占用键盘与鼠标
    wants_input_ = ImGui::IsAnyItemActive();

    ImGui::Render();
    ImGui_ImplOpenGL3_RenderDrawData(ImGui::GetDrawData());
}

} // namespace phos

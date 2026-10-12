#include "api/ui_api.hpp"

#include "api/draw_region.hpp"
#include "api/host_api.hpp"
#include "api/lua_value.hpp"
#include "core/log.hpp"
#include "core/ui.hpp"

#include <sol/sol.hpp>

#include <map>
#include <vector>

namespace phos {

ui::Style cart_style(const HostContext& host) {
    return host.palette ? ui::style_from_palette(*host.palette) : ui::Style{};
}

namespace {

std::map<char, Color> color_map(const sol::object& obj) {
    return api::read_char_color_map(obj);
}

} // namespace

void register_ui_api(sol::state& lua, HostContext& host) {
    sol::table phos = lua["phos"];
    sol::table ui = phos.create_named("ui");

    // 坐标一律为内容区局部坐标；内部偏移到网格坐标
    auto rect_at = [&host](int x, int y, int w, int h) {
        return ui::Rect{host.content_x + x, host.content_y + y, w, h};
    };

    ui["frame"] = [&host, rect_at](int x, int y, int w, int h, sol::object title) {
        ui::Style style = cart_style(host);
        std::string text = title.is<std::string>() ? title.as<std::string>() : std::string();
        ui::frame(*host.screen, rect_at(x, y, w, h), text, style);
    };

    // 居中浮窗：返回局部坐标布局表 {x, y, w, h}，内容由卡带自己画
    ui["modal"] = [&host, &lua](int w, int h, sol::object title) -> sol::table {
        ui::Style style = cart_style(host);
        ui::Rect area{host.content_x, host.content_y, host.content_w, host.content_h};
        ui::Rect box = ui::Rect::centered(area, w, h);
        std::string text = title.is<std::string>() ? title.as<std::string>() : std::string();
        ui::frame(*host.screen, box, text, style);

        sol::table result = lua.create_table();
        result["x"] = box.x - host.content_x;
        result["y"] = box.y - host.content_y;
        result["w"] = box.w;
        result["h"] = box.h;
        return result;
    };

    ui["divider"] = [&host, rect_at](int x, int y, int w) {
        ui::Style style = cart_style(host);
        ui::Rect r = rect_at(x, y, w, 1);
        ui::divider(*host.screen, r.x, r.y, r.w, style.dim, style.bg);
    };

    // h 可省略：缺省按条目数（与 region:menu 同一语义；省略时行数由内容决定）
    ui["menu"] = [&host, rect_at](int x, int y, int w, sol::table items, int selected,
                                  sol::optional<int> h) {
        ui::Style style = cart_style(host);
        std::vector<std::string> list;
        for (size_t i = 1; i <= items.size(); ++i) {
            sol::object v = items[i];
            list.push_back(v.is<std::string>() ? v.as<std::string>() : std::string());
        }
        const int height = (h && *h > 0) ? *h : static_cast<int>(list.size());
        ui::menu(*host.screen, rect_at(x, y, w, height), list, selected, style);
    };

    ui["bar"] = [&host, rect_at](int x, int y, int w, float ratio) {
        ui::Style style = cart_style(host);
        ui::Rect r = rect_at(x, y, w, 1);
        ui::bar(*host.screen, r.x, r.y, r.w, ratio, style);
    };

    // max_lines 可省略：缺省 1 行（与 region:body 同一语义）
    ui["text"] = [&host, rect_at](int x, int y, int w, const std::string& body,
                                  sol::optional<int> max_lines) {
        ui::Style style = cart_style(host);
        ui::Rect r = rect_at(x, y, w, 1);
        const int lines = max_lines.value_or(0);
        ui::text_block(*host.screen, r.x, r.y, r.w, body, lines > 0 ? lines : 1, style);
    };

    ui["center_text"] = [&host](int y, const std::string& text) {
        ui::Style style = cart_style(host);
        ui::print_centered(*host.screen, host.content_y + y, text, style.accent, style.bg,
                           host.content_x, host.content_w);
    };

    /// 像素精灵：rows 为字符画，colors 是 字符→颜色 映射（键必须是**单字节**字符，
    /// 用 '█' 这类多字节字符查不到表、会退化成风格色），step 为缩放步长（可省略，缺省 1）。
    /// 只有 '.' 与空格透明，其余字符都算实心像素。
    ui["sprite"] = [&host, rect_at](int x, int y, sol::object rows, sol::object colors,
                                    sol::optional<int> step) {
        ui::Style style = cart_style(host);
        std::vector<std::string> art = api::read_rows(rows);
        std::map<char, Color> palette = color_map(colors);
        int h = static_cast<int>(art.size());
        int w = 0;
        for (const auto& row : art)
            w = w > static_cast<int>(row.size()) ? w : static_cast<int>(row.size());
        ui::Rect r = rect_at(x, y, w, h);
        const int scale = step.value_or(1);
        // 以左上角定位：icon 语义为居中，此处用中心点换算
        ui::icon(*host.screen, art, palette, r.x + w / 2, r.y + h / 2,
                 scale < 1 ? 1 : scale, 1.0f, style.accent);
    };

    /// 列表导航：返回 (新下标, 动作)，动作为 "none" / "confirm" / "cancel"
    ui["nav"] = [&host](int count, int current) -> std::tuple<int, std::string> {
        ui::NavAction action = ui::NavAction::none;
        int index = ui::navigate(*host.input, count, current, action);
        const char* name = action == ui::NavAction::confirm ? "confirm"
                          : action == ui::NavAction::cancel  ? "cancel"
                                                             : "none";
        return {index, name};
    };

    // --- phos.ui.region：带裁剪的绘制区域（非浮动分区与浮动窗口同源） ---
    lua.new_usertype<DrawRegion>(
        "phos.Region", sol::no_constructor, "x", sol::property(&DrawRegion::x), "y",
        sol::property(&DrawRegion::y), "w", sol::property(&DrawRegion::w), "h",
        sol::property(&DrawRegion::h), "surface", sol::property(&DrawRegion::anchor),
        "clear",
        [&host](DrawRegion& r, sol::object fg, sol::object bg) {
            r.clear(api::read_color(fg, api::default_fg(host)), api::read_background(bg));
        },
        // 区域里的 put / print / fill / blit / clear 都默认**保留背景**（省略 bg → keep）：
        // 覆盖层压在游戏画面上时，字缝里透出的是底图而不是黑块
        "put",
        [&host](DrawRegion& r, int x, int y, sol::object ch, sol::object fg, sol::object bg) {
            r.put(x, y, api::read_char(ch, U' '), api::read_color(fg, api::default_fg(host)),
                  api::read_background(bg));
        },
        "print",
        [&host](DrawRegion& r, int x, int y, const std::string& text, sol::object fg, sol::object bg) {
            r.print(x, y, text, api::read_color(fg, api::default_fg(host)), api::read_background(bg));
        },
        "fill",
        [&host](DrawRegion& r, int x, int y, int w, int h, sol::object ch, sol::object fg,
                sol::object bg) {
            r.fill(x, y, w, h, api::read_char(ch, U' '), api::read_color(fg, api::default_fg(host)),
                   api::read_background(bg));
        },
        "blit",
        [&host](DrawRegion& r, int x, int y, sol::object rows, sol::object fg, sol::object bg) {
            r.blit(x, y, api::read_rows(rows), api::read_color(fg, api::default_fg(host)),
                   api::read_background(bg));
        },
        // 区域里的 blend / back / back_rect / plot 与 put 同组（**保留底色**）：
        // 覆盖层压在游戏画面上时，字缝里透出的是底图而不是黑块
        "blend",
        [&host](DrawRegion& r, int x, int y, sol::object ch, sol::object fg) {
            return r.blend(x, y, api::read_char(ch, U' '), api::read_color(fg, api::default_fg(host)));
        },
        "back",
        [](DrawRegion& r, int x, int y, sol::object bg) {
            r.back(x, y, api::read_background(bg));
        },
        "back_rect",
        [](DrawRegion& r, int x, int y, int w, int h, sol::object bg) {
            r.back_rect(x, y, w, h, api::read_background(bg));
        },
        "plot",
        [&host](DrawRegion& r, int x, int y, sol::object fg) {
            r.plot(x, y, api::read_color(fg, api::default_fg(host)));
        },
        "frame",
        [](DrawRegion& r, sol::object title) {
            r.frame(title.is<std::string>() ? title.as<std::string>() : std::string());
        },
        "divider", &DrawRegion::divider, "bar", &DrawRegion::bar,
        "menu",
        [](DrawRegion& r, int x, int y, int w, sol::object items, int selected,
           sol::optional<int> h) { r.menu(x, y, w, api::read_rows(items), selected, h.value_or(0)); },
        "body",
        [](DrawRegion& r, int x, int y, int w, const std::string& text,
           sol::optional<int> max_lines) { r.body(x, y, w, text, max_lines.value_or(0)); },
        "sprite",
        [](DrawRegion& r, int x, int y, sol::object rows, sol::object colors,
           sol::optional<int> step) {
            r.sprite(x, y, api::read_rows(rows), color_map(colors), step.value_or(1));
        });

    ui["region"] = [&host](int x, int y, int w, int h, sol::optional<sol::table> opts) {
        std::string anchor = "screen";
        std::string layer;
        if (opts) {
            sol::object requested = (*opts)["surface"];
            if (requested.is<std::string>()) anchor = requested.as<std::string>();
            sol::object on_layer = (*opts)["layer"];
            if (on_layer.is<std::string>()) layer = on_layer.as<std::string>();
        }
        // 名字写错时不能静默按内容区处理：卡带会以为自己在画侧栏，整块却落在游戏画面上，
        // 而且没有任何报错可查
        if (anchor != "screen" && anchor != "panel") {
            log::warn("phos.ui.region：surface 取值未知 \"" + anchor + "\"，按 screen 处理");
            anchor = "screen";
        }
        // 层锚定在内容区之上：region 的坐标原点始终是内容区左上角，
        // 所以与 surface = "panel" 同时给出是矛盾的，这里以 layer 为准并留痕
        if (!layer.empty() && anchor == "panel") {
            log::warn("phos.ui.region: layer 与 surface=\"panel\" 同时给出，按 layer 处理");
            anchor = "screen";
        }
        return DrawRegion(host, anchor, layer, x, y, w, h);
    };
}

} // namespace phos

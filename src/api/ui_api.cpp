#include "api/ui_api.hpp"

#include "api/draw_region.hpp"
#include "api/host_api.hpp"
#include "api/lua_value.hpp"
#include "core/text.hpp"
#include "core/ui.hpp"

#include <sol/sol.hpp>

#include <map>
#include <vector>

namespace phos {

ui::Style cart_style(const HostContext& host) {
    return host.palette ? ui::style_from_palette(*host.palette) : ui::Style{};
}

namespace {

/// 界面的取色入口：允许直接传 Color usertype，其余交给共享的 Lua 值读取
Color color_from(const sol::object& obj, Color fallback) {
    if (obj.is<Color>()) return obj.as<Color>();
    return api::read_color(obj, fallback);
}

std::vector<std::string> row_list(const sol::object& obj) {
    std::vector<std::string> rows;
    if (!obj.is<sol::table>()) return rows;
    sol::table t = obj.as<sol::table>();
    for (size_t i = 1; i <= t.size(); ++i) {
        sol::object v = t[i];
        if (v.is<std::string>()) rows.push_back(v.as<std::string>());
    }
    return rows;
}

std::map<char, Color> color_map(const sol::object& obj) {
    std::map<char, Color> colors;
    if (!obj.is<sol::table>()) return colors;
    sol::table t = obj.as<sol::table>();
    for (auto& kv : t) {
        if (!kv.first.is<std::string>()) continue;
        std::string key = kv.first.as<std::string>();
        if (key.empty()) continue;
        colors[key[0]] = color_from(kv.second, Color::white);
    }
    return colors;
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

    ui["menu"] = [&host, rect_at](int x, int y, int w, sol::table items, int selected, int h) {
        ui::Style style = cart_style(host);
        std::vector<std::string> list;
        for (size_t i = 1; i <= items.size(); ++i) {
            sol::object v = items[i];
            list.push_back(v.is<std::string>() ? v.as<std::string>() : std::string());
        }
        if (h <= 0) h = static_cast<int>(list.size());
        ui::menu(*host.screen, rect_at(x, y, w, h), list, selected, style);
    };

    ui["bar"] = [&host, rect_at](int x, int y, int w, float ratio) {
        ui::Style style = cart_style(host);
        ui::Rect r = rect_at(x, y, w, 1);
        ui::bar(*host.screen, r.x, r.y, r.w, ratio, style);
    };

    ui["text"] = [&host, rect_at](int x, int y, int w, const std::string& body, int max_lines) {
        ui::Style style = cart_style(host);
        ui::Rect r = rect_at(x, y, w, 1);
        ui::text_block(*host.screen, r.x, r.y, r.w, body, max_lines > 0 ? max_lines : 1, style);
    };

    ui["center_text"] = [&host](int y, const std::string& text) {
        ui::Style style = cart_style(host);
        ui::print_centered(*host.screen, host.content_y + y, text, style.accent, style.bg,
                           host.content_x, host.content_w);
    };

    /// 像素精灵：rows 为字符画，colors 为 字符→颜色 映射（只有 '.' 透明，
    /// 其余字符一律算实心像素——空格也算，所以字符画里要用 '.' 留空），step 为缩放步长。
    /// 注意映射的键是**单字节**字符：用 '█' 这类多字节字符查不到表，会退化成风格色，
    /// 于是"跑者"和障碍物同色——所以字符画请用 '#'、'o' 之类的 ASCII 符号
    /// （外观由剪影决定，画什么字符不影响形状）
    ui["sprite"] = [&host, rect_at](int x, int y, sol::object rows, sol::object colors, int step) {
        ui::Style style = cart_style(host);
        std::vector<std::string> art = row_list(rows);
        std::map<char, Color> palette = color_map(colors);
        int h = static_cast<int>(art.size());
        int w = 0;
        for (const auto& row : art)
            w = w > static_cast<int>(row.size()) ? w : static_cast<int>(row.size());
        ui::Rect r = rect_at(x, y, w, h);
        // 以左上角定位：icon 语义为居中，此处用中心点换算
        ui::icon(*host.screen, art, palette, r.x + w / 2, r.y + h / 2,
                 step < 1 ? 1 : step, 1.0f, style.accent);
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
        sol::property(&DrawRegion::h), "surface", sol::property(&DrawRegion::surface),
        "clear",
        [](DrawRegion& r, sol::object fg, sol::object bg) {
            r.clear(color_from(fg, Color::white), color_from(bg, Color::black));
        },
        "put",
        [](DrawRegion& r, int x, int y, sol::object ch, sol::object fg, sol::object bg) {
            r.put(x, y, api::read_char(ch, U' '), color_from(fg, Color::white),
                  color_from(bg, Color::black));
        },
        "print",
        [](DrawRegion& r, int x, int y, const std::string& text, sol::object fg, sol::object bg) {
            r.print(x, y, text, color_from(fg, Color::white), color_from(bg, Color::black));
        },
        "fill",
        [](DrawRegion& r, int x, int y, int w, int h, sol::object ch, sol::object fg,
           sol::object bg) {
            r.fill(x, y, w, h, api::read_char(ch, U' '), color_from(fg, Color::white),
                   color_from(bg, Color::black));
        },
        "blit",
        [](DrawRegion& r, int x, int y, sol::object rows, sol::object fg, sol::object bg) {
            r.blit(x, y, row_list(rows), color_from(fg, Color::white),
                   color_from(bg, Color::black));
        },
        "frame",
        [](DrawRegion& r, sol::object title) {
            r.frame(title.is<std::string>() ? title.as<std::string>() : std::string());
        },
        "divider", &DrawRegion::divider, "bar", &DrawRegion::bar,
        "menu",
        [](DrawRegion& r, int x, int y, int w, sol::object items, int selected,
           sol::optional<int> h) { r.menu(x, y, w, row_list(items), selected, h.value_or(0)); },
        "body",
        [](DrawRegion& r, int x, int y, int w, const std::string& text,
           sol::optional<int> max_lines) { r.body(x, y, w, text, max_lines.value_or(0)); },
        "sprite",
        [](DrawRegion& r, int x, int y, sol::object rows, sol::object colors,
           sol::optional<int> step) {
            r.sprite(x, y, row_list(rows), color_map(colors), step.value_or(1));
        });

    ui["region"] = [&host](int x, int y, int w, int h, sol::optional<sol::table> opts) {
        std::string surface = "screen";
        if (opts) {
            sol::object requested = (*opts)["surface"];
            if (requested.is<std::string>()) surface = requested.as<std::string>();
        }
        return DrawRegion(host, surface, x, y, w, h);
    };
}

} // namespace phos

#include "api/ui_render.hpp"

#include "api/host_api.hpp"
#include "api/lua_value.hpp"
#include "api/ui_options.hpp"
#include "core/json_lite.hpp"
#include "core/log.hpp"
#include "ui/element.hpp"
#include "ui/frame.hpp"
#include "ui/layout.hpp"
#include "ui/theme.hpp"

#include <sol/sol.hpp>

#include <algorithm>
#include <string>
#include <vector>

namespace phos {

namespace {

constexpr int kMaxDepth = 8;  // 元素树深度上限：坏输入不该把栈撑爆

std::string str_field(const sol::table& t, const char* key, const std::string& fallback = {}) {
    sol::object value = t[key];
    return value.is<std::string>() ? value.as<std::string>() : fallback;
}

bool bool_field(const sol::table& t, const char* key, bool fallback = false) {
    sol::object value = t[key];
    return value.is<bool>() ? value.as<bool>() : fallback;
}

bool has_field(const sol::table& t, const char* key) {
    sol::object value = t[key];
    return value.valid() && value.get_type() != sol::type::nil;
}

int int_field(const sol::table& t, const char* key, int fallback = 0) {
    sol::object value = t[key];
    if (value.is<int>()) return value.as<int>();
    if (value.is<double>()) return static_cast<int>(value.as<double>());
    return fallback;
}

float float_field(const sol::table& t, const char* key, float fallback = 0.0f) {
    sol::object value = t[key];
    if (value.is<double>()) return static_cast<float>(value.as<double>());
    if (value.is<int>()) return static_cast<float>(value.as<int>());
    return fallback;
}

/// 内边距/外边距：数字 = 四边同值；表 = {l,t,r,b} 或 {x,y}
ui::Insets insets_field(const sol::table& t, const char* key) {
    ui::Insets out;
    sol::object value = t[key];
    if (value.is<int>()) {
        const int all = value.as<int>();
        out = ui::Insets{all, all, all, all};
    } else if (value.is<double>()) {
        const int all = static_cast<int>(value.as<double>());
        out = ui::Insets{all, all, all, all};
    } else if (value.is<sol::table>()) {
        sol::table map = value.as<sol::table>();
        if (has_field(map, "x") || has_field(map, "y")) {
            const int x = int_field(map, "x"), y = int_field(map, "y");
            out = ui::Insets{x, y, x, y};
        } else {
            out = ui::Insets{int_field(map, "l"), int_field(map, "t"), int_field(map, "r"),
                             int_field(map, "b")};
        }
    }
    return out;
}

ui::Align align_field(const sol::table& t, const char* key, ui::Align fallback) {
    const std::string name = str_field(t, key);
    if (name == "start") return ui::Align::start;
    if (name == "center") return ui::Align::center;
    if (name == "end") return ui::Align::end;
    if (name == "stretch") return ui::Align::stretch;
    return fallback;
}

ui::Kind kind_from_name(const std::string& name) {
    if (name == "row") return ui::Kind::row;
    if (name == "box") return ui::Kind::box;
    if (name == "text") return ui::Kind::text;
    if (name == "divider") return ui::Kind::divider;
    if (name == "spacer") return ui::Kind::spacer;
    if (name == "list") return ui::Kind::list;
    if (name == "stat") return ui::Kind::stat;
    if (name == "option") return ui::Kind::option;
    if (name == "checkbox") return ui::Kind::checkbox;
    if (name == "field") return ui::Kind::field;
    if (name == "bar") return ui::Kind::bar;
    if (name == "button") return ui::Kind::button;
    if (name == "hint") return ui::Kind::hint;
    if (name == "table") return ui::Kind::table;
    if (name == "grid") return ui::Kind::grid;
    if (name == "scroll") return ui::Kind::scroll;
    return ui::Kind::column;
}

ui::Overflow overflow_from_name(const std::string& name) {
    if (name == "clip") return ui::Overflow::clip;
    if (name == "wrap") return ui::Overflow::wrap;
    return ui::Overflow::ellipsis;
}

ui::Border border_from_name(const std::string& name) {
    if (name == "single") return ui::Border::single;
    if (name == "double") return ui::Border::double_line;
    return ui::Border::none;
}

ui::FieldFilter filter_from_name(const std::string& name) {
    if (name == "ascii") return ui::FieldFilter::ascii;
    if (name == "digits") return ui::FieldFilter::digits;
    if (name == "hex") return ui::FieldFilter::hex;
    if (name == "letters") return ui::FieldFilter::letters;
    if (name == "any") return ui::FieldFilter::any;
    return ui::FieldFilter::printable;
}

std::vector<std::string> strings_field(const sol::table& t, const char* key) {
    sol::object value = t[key];
    if (!value.is<sol::table>()) return {};
    return api::read_rows(value);
}

std::string cell_string(const sol::object& value) {
    if (value.is<std::string>()) return value.as<std::string>();
    if (value.is<int>()) return std::to_string(value.as<int>());
    if (value.is<bool>()) return value.as<bool>() ? "true" : "false";
    if (value.is<double>()) {
        const double number = value.as<double>();
        if (number == static_cast<long long>(number)) return std::to_string(static_cast<long long>(number));
        char buffer[32];
        std::snprintf(buffer, sizeof(buffer), "%.2f", number);
        return std::string(buffer);
    }
    return {};
}

/// rows = {{"a","b"},{"c","d"}}：每行一张表，单元格按字符串/数字转文本
std::vector<std::vector<std::string>> rows_field(const sol::table& t, const char* key) {
    std::vector<std::vector<std::string>> rows;
    sol::object value = t[key];
    if (!value.is<sol::table>()) return rows;
    sol::table list = value.as<sol::table>();
    for (size_t i = 1; i <= list.size(); ++i) {
        sol::object row = list[i];
        if (!row.is<sol::table>()) continue;
        sol::table cells = row.as<sol::table>();
        std::vector<std::string> line;
        for (size_t j = 1; j <= cells.size(); ++j) {
            sol::object cell = cells[j];
            line.push_back(cell_string(cell));
        }
        rows.push_back(std::move(line));
    }
    return rows;
}

std::vector<int> ints_field(const sol::table& t, const char* key) {
    std::vector<int> out;
    sol::object value = t[key];
    if (!value.is<sol::table>()) return out;
    sol::table list = value.as<sol::table>();
    for (size_t i = 1; i <= list.size(); ++i) {
        sol::object item = list[i];
        if (item.is<int>()) out.push_back(item.as<int>());
        else if (item.is<double>()) out.push_back(static_cast<int>(item.as<double>()));
        else out.push_back(0);
    }
    return out;
}

std::vector<ui::Align> aligns_field(const sol::table& t, const char* key) {
    std::vector<ui::Align> out;
    sol::object value = t[key];
    if (!value.is<sol::table>()) return out;
    sol::table list = value.as<sol::table>();
    for (size_t i = 1; i <= list.size(); ++i) {
        sol::object item = list[i];
        const std::string name = item.is<std::string>() ? item.as<std::string>() : "left";
        if (name == "center") out.push_back(ui::Align::center);
        else if (name == "right" || name == "end") out.push_back(ui::Align::end);
        else out.push_back(ui::Align::start);
    }
    return out;
}

/// items + disabled：disabled 可写成下标数组 {2,5} 或等长布尔数组
void apply_disabled(const sol::table& t, const std::vector<std::string>& items, ui::Props& out) {
    sol::object value = t["disabled"];
    if (!value.is<sol::table>()) return;
    sol::table list = value.as<sol::table>();
    out.disabled.assign(items.size(), false);
    for (size_t i = 1; i <= list.size(); ++i) {
        sol::object item = list[i];
        if (item.is<bool>()) {
            if (i - 1 < out.disabled.size() && item.as<bool>()) out.disabled[i - 1] = true;
        } else if (item.is<int>() || item.is<double>()) {
            const int index = static_cast<int>(item.as<double>());
            if (index >= 0 && index < static_cast<int>(out.disabled.size()))
                out.disabled[static_cast<size_t>(index)] = true;
        }
    }
}

ui::Node* find_by_id(ui::Node& root, const std::string& id) {
    if (root.id == id) return &root;
    for (ui::Node& child : root.children)
        if (ui::Node* found = find_by_id(child, id)) return found;
    return nullptr;
}

const ui::WidgetState* widget_of(const ui::State& state, const std::string& screen,
                                const std::string& id) {
    const auto it = state.screens.find(screen);
    if (it == state.screens.end()) return nullptr;
    const auto widget = it->second.widgets.find(id);
    return widget == it->second.widgets.end() ? nullptr : &widget->second;
}

/// 控件树的可观测快照：只暴露"能交互的控件"与它们的值。
/// 扁平表（id/role/label/state）让 agent 不必解析画面或数按键。
std::string ui_snapshot(const ui::Node& root, const ui::State& state, const std::string& screen,
                        const std::string& focus) {
    std::string out = "{\"screen\":" + json::quote(screen) + ",\"focus\":" + json::quote(focus) +
                      ",\"widgets\":[";
    int emitted = 0;
    bool truncated = false;
    std::function<void(const ui::Node&)> walk = [&](const ui::Node& node) {
        if (emitted >= 64) {
            truncated = true;
            return;
        }
        if (ui::focusable_kind(node.kind)) {
            const ui::WidgetState* widget = widget_of(state, screen, node.id);
            std::string label = node.props.text;
            std::string state_json;
            switch (node.kind) {
                case ui::Kind::list: {
                    const int cursor = widget ? widget->cursor : 0;
                    state_json = "{\"selected\":" + std::to_string(cursor + 1) +
                                 ",\"count\":" + std::to_string(node.props.items.size()) + "}";
                    if (cursor >= 0 && cursor < static_cast<int>(node.props.items.size()))
                        label = node.props.items[static_cast<size_t>(cursor)];
                    break;
                }
                case ui::Kind::checkbox:
                    state_json = std::string("{\"checked\":") +
                                 ((widget && widget->checked) ? "true" : "false") + "}";
                    break;
                case ui::Kind::field: {
                    const std::string value =
                        widget && widget->input ? widget->input->value() : std::string();
                    state_json = "{\"text\":" + json::quote(value) + "}";
                    break;
                }
                case ui::Kind::option:
                case ui::Kind::button: state_json = "{}"; break;
                default: state_json = "{}"; break;
            }
            out += (emitted ? "," : "");
            out += "{\"id\":" + json::quote(node.id) + ",\"role\":" +
                   json::quote(node.kind == ui::Kind::list        ? "list"
                               : node.kind == ui::Kind::checkbox  ? "checkbox"
                               : node.kind == ui::Kind::field     ? "field"
                               : node.kind == ui::Kind::option    ? "option"
                               : node.kind == ui::Kind::button    ? "button"
                                                                  : "widget") +
                   ",\"label\":" + json::quote(label) + ",\"state\":" + state_json + "}";
            ++emitted;
        }
        for (const ui::Node& child : node.children) walk(child);
    };
    walk(root);
    out += "]";
    if (truncated) out += ",\"truncated\":true";
    out += "}";
    return out;
}

/// agent 请求的"激活某个控件"：与玩家按确认等价的语义，事件交给卡带处理
void synthesize_activation(ui::Node& root, ui::State& state, const std::string& screen,
                           const std::string& id, std::vector<ui::Event>& events) {
    ui::Node* node = find_by_id(root, id);
    if (!node || !ui::focusable_kind(node->kind) || !node->props.enabled) return;
    ui::ScreenState& screen_state = state.screen(screen);
    screen_state.focus = node->id;
    ui::WidgetState& widget = screen_state.widgets[node->id];
    ui::Event event;
    event.id = node->id;
    switch (node->kind) {
        case ui::Kind::list: {
            const int count = static_cast<int>(node->props.items.size());
            if (count <= 0) return;
            event.kind = ui::EventKind::activated;
            event.index = std::clamp(widget.cursor, 0, count - 1);
            break;
        }
        case ui::Kind::checkbox:
            widget.checked = !widget.checked;
            event.kind = ui::EventKind::changed;
            event.flag = widget.checked;
            break;
        case ui::Kind::field:
            event.kind = ui::EventKind::submitted;
            event.text = widget.input ? widget.input->value() : std::string();
            break;
        case ui::Kind::option:
            event.kind = ui::EventKind::changed;
            event.delta = 1;
            event.confirm = true;
            break;
        default: event.kind = ui::EventKind::activated; break;
    }
    events.push_back(std::move(event));
}

struct Builder {
    HostContext& host;

    void props_from_table(const sol::table& t, ui::Props& out) {
        out.width = int_field(t, "width");
        out.height = int_field(t, "height");
        out.min_w = int_field(t, "min_w");
        out.min_h = int_field(t, "min_h");
        out.max_w = int_field(t, "max_w");
        out.max_h = int_field(t, "max_h");
        out.grow = int_field(t, "grow");
        out.gap = int_field(t, "gap", out.gap);
        out.cols = int_field(t, "cols", out.cols);
        out.scroll = std::max(0, int_field(t, "scroll", out.scroll));
        out.scroll_x = std::max(0, int_field(t, "scroll_x", out.scroll_x));
        out.scrollbar = bool_field(t, "scrollbar", out.scrollbar);
        out.margin = insets_field(t, "margin");
        out.padding = insets_field(t, "padding");
        out.align_h = align_field(t, "align_h", out.align_h);
        out.align_v = align_field(t, "align_v", out.align_v);
        out.opaque = bool_field(t, "opaque", out.opaque);
        if (has_field(t, "bg")) {
            out.has_bg = true;
            out.bg = api::parse_color(t["bg"], out.bg, host.palette);
        }
        if (has_field(t, "fg")) {
            out.has_fg = true;
            out.fg = api::parse_color(t["fg"], out.fg, host.palette);
        }
        out.border = border_from_name(str_field(t, "border"));
        out.title = str_field(t, "title");
        out.dim = bool_field(t, "dim", out.dim);
        out.accent = bool_field(t, "accent", out.accent);
        out.danger = bool_field(t, "danger", out.danger);
        out.scale = int_field(t, "scale", out.scale);
        out.overflow = overflow_from_name(str_field(t, "overflow", "ellipsis"));
        out.lines = int_field(t, "lines", out.lines);
        out.enabled = bool_field(t, "enabled", out.enabled);
        out.indent = int_field(t, "indent", out.indent);
        out.text_gap = int_field(t, "text_gap", out.text_gap);
        out.label_w = int_field(t, "label_w", out.label_w);
        out.filter = filter_from_name(str_field(t, "filter"));
        out.max_chars = int_field(t, "max_chars", out.max_chars);
        out.text = str_field(t, "text");
        out.value = str_field(t, "value");
        out.items = strings_field(t, "items");
        out.columns = strings_field(t, "columns");
        out.rows = rows_field(t, "rows");
        out.widths = ints_field(t, "widths");
        out.col_align = aligns_field(t, "col_align");
        out.ratio = float_field(t, "ratio");
        out.absolute = bool_field(t, "absolute", out.absolute);
        out.x = int_field(t, "x");
        out.y = int_field(t, "y");
        apply_disabled(t, out.items, out);
    }

    ui::Node build(const sol::table& t, const std::string& parent_id, int index, int depth) {
        ui::Node node;
        node.kind = kind_from_name(str_field(t, "kind", "column"));
        node.id = str_field(t, "id", parent_id + "/" + std::to_string(index));
        props_from_table(t, node.props);

        // 勾选/文本域初值：只在控件还没有状态时写入（之后归控件维护）
        if (node.kind == ui::Kind::checkbox && has_field(t, "checked")) ok_checked.emplace_back(
            node.id, bool_field(t, "checked"));
        if (node.kind == ui::Kind::field && has_field(t, "value"))
            ok_field.emplace_back(node.id, node.props.value);

        if (depth < kMaxDepth) {
            sol::object children = t["children"];
            if (children.is<sol::table>()) {
                sol::table list = children.as<sol::table>();
                for (size_t i = 1; i <= list.size(); ++i) {
                    sol::object child = list[i];
                    if (child.is<sol::table>())
                        node.children.push_back(build(child.as<sol::table>(), node.id,
                                                      static_cast<int>(i), depth + 1));
                }
            }
        }
        return node;
    }

    // 初值收集：build 是纯函数化的，副作用只在调用方 run 之前统一应用
    std::vector<std::pair<std::string, bool>> ok_checked;
    std::vector<std::pair<std::string, std::string>> ok_field;
};

ui::Rect area_for(const HostContext& host, const std::string& surface, const sol::table& spec) {
    ui::Rect area{host.content_x, host.content_y, host.content_w, host.content_h};
    if (surface == "panel") {
        area = ui::Rect{host.panel_origin_x(), host.content_y, host.panel_w, host.content_h};
    } else if (surface == "playfield") {
        const int divider = host.panel_w > 0 ? 1 : 0;
        area.w = host.content_w - host.panel_w - divider;
    }
    sol::object rect = spec["rect"];
    if (rect.is<sol::table>()) {
        sol::table r = rect.as<sol::table>();
        area = ui::Rect{area.x + int_field(r, "x"), area.y + int_field(r, "y"),
                        int_field(r, "w", area.w), int_field(r, "h", area.h)};
    }
    return area;
}

sol::table events_to_table(sol::state& lua, const std::vector<ui::Event>& events) {
    sol::table out = lua.create_table();
    int index = 1;
    for (const ui::Event& event : events) {
        sol::table item = lua.create_table();
        switch (event.kind) {
            case ui::EventKind::activated: item["kind"] = "activated"; break;
            case ui::EventKind::changed: item["kind"] = "changed"; break;
            case ui::EventKind::submitted: item["kind"] = "submitted"; break;
            case ui::EventKind::cancelled: item["kind"] = "cancelled"; break;
        }
        item["id"] = event.id;
        // Lua 侧下标统一 1 基（与 items 表一致）：C++ 内部 0 基，只在绑定处 +1
        if (event.index >= 0) item["index"] = event.index + 1;
        if (event.delta != 0) item["delta"] = event.delta;
        if (event.confirm) item["confirm"] = true;
        if (event.kind == ui::EventKind::changed) item["checked"] = event.flag;
        if (!event.text.empty()) item["text"] = event.text;
        out[index++] = item;
    }
    return out;
}

} // namespace

void register_cart_ui_api(sol::state& lua, HostContext& host) {
    sol::table ui = lua["phos"]["ui"];

    /// 声明并绘制一帧界面；返回本帧事件数组。
    /// 必须在 draw() 里调用：它直接写当前帧的屏幕，并消费本帧输入。
    ui["render"] = [&lua, &host](sol::table spec) -> sol::table {
        if (!host.screen || !host.input) return lua.create_table();

        const std::string surface = str_field(spec, "surface", "content");
        if (surface == "panel" && host.panel_w <= 0) return lua.create_table();  // 无侧栏
        const std::string screen_id = str_field(spec, "screen", "cart");

        Builder builder{host};
        ui::Node root;
        sol::object kind = spec["kind"];
        if (kind.is<std::string>()) {
            root = builder.build(spec, screen_id, 1, 0);
        } else {
            root = ui::make_root(screen_id);
            for (size_t i = 1; i <= spec.size(); ++i) {
                sol::object child = spec[i];
                if (child.is<sol::table>())
                    root.children.push_back(builder.build(child.as<sol::table>(), screen_id,
                                                          static_cast<int>(i), 1));
            }
        }

        const ui::Theme theme = host.palette ? ui::theme_from_palette(*host.palette) : ui::Theme{};
        // 一帧只让"负责输入"的那次 render 消费按键：同一帧多次 render（世界 UI + 侧栏 +
        // 浮窗）时，后面的用 input=false 只画，否则同一次按键会被多个界面各处理一遍
        const bool consume_input = bool_field(spec, "input", true);
        ui::Frame frame(screen_id, host.cart_ui, theme, area_for(host, surface, spec),
                        consume_input ? host.input : nullptr, ui::Keys::pad());
        frame.root() = std::move(root);
        for (const auto& [id, value] : builder.ok_checked) frame.ensure_checked(id, value);
        for (const auto& [id, value] : builder.ok_field) frame.ensure_field_text(id, value);

        // agent 请求只落在"负责输入"的那一屏：否则同帧的显示型界面会把请求吃掉
        if (consume_input && !host.pending_ui_focus.empty()) {
            host.cart_ui.screen(screen_id).focus = host.pending_ui_focus;
            host.pending_ui_focus.clear();
        }

        std::vector<ui::Event> events = frame.run();
        if (consume_input && !host.pending_ui_activate.empty()) {
            synthesize_activation(frame.root(), host.cart_ui, screen_id, host.pending_ui_activate,
                                  events);
            host.pending_ui_activate.clear();
        }
        if (consume_input) {
            // 文本域要收中文：界面层举手，主机据此开系统输入法（与 phos.input.field 同一信号）
            if (frame.ime_requested()) host.ime_wanted = true;
            // 查询接口以"负责输入的那一屏"为准：同一帧还有只画的界面时，焦点不跟着它走
            host.last_ui_focus = frame.focused_id();
            host.last_ui_screen = screen_id;
            host.cart_ui_json = ui_snapshot(frame.root(), host.cart_ui, screen_id,
                                            host.last_ui_focus);
        }
        frame.paint(*host.screen);
        return events_to_table(lua, events);
    };

    /// 当前焦点控件的 id（agent 与自测读界面状态用；无控件时为空串）
    ui["focus"] = [&host]() -> std::string { return host.last_ui_focus; };

    /// 勾选态读（与 render 的 checked 初值互补：宿主每帧传初值时用这个）
    ui["checked"] = [&host](const std::string& id, sol::optional<std::string> screen_id) {
        const auto screen =
            host.cart_ui.screens.find(screen_id.value_or(host.last_ui_screen));
        if (screen == host.cart_ui.screens.end()) return false;
        const auto widget = screen->second.widgets.find(id);
        return widget != screen->second.widgets.end() && widget->second.checked;
    };
    ui["set_checked"] = [&host](const std::string& id, bool value,
                                sol::optional<std::string> screen_id) {
        host.cart_ui.screen(screen_id.value_or(host.last_ui_screen)).widgets[id].checked = value;
    };
    /// 文本域当前内容（控件由 render 创建后才有值）
    ui["field_text"] = [&host](const std::string& id,
                               sol::optional<std::string> screen_id) -> std::string {
        const auto screen =
            host.cart_ui.screens.find(screen_id.value_or(host.last_ui_screen));
        if (screen == host.cart_ui.screens.end()) return {};
        const auto widget = screen->second.widgets.find(id);
        if (widget == screen->second.widgets.end() || !widget->second.input) return {};
        return widget->second.input->value();
    };
    /// 清空全部界面状态（换屏/换场景时调用，避免旧焦点/滚动串到新界面）
    ui["reset"] = [&host]() {
        host.cart_ui.screens.clear();
        host.last_ui_focus.clear();
    };
}

} // namespace phos
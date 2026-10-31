#include "ui/frame.hpp"

#include "core/screen.hpp"
#include "core/surface.hpp"
#include "core/text.hpp"
#include "ui/layout.hpp"

#include <algorithm>
#include <cmath>

namespace phos::ui {

namespace {

// 方向键按住重复：先等约 300ms（18 帧）再以每 3 帧一格的节奏连发。
// 按帧而不是秒：Frame 没有 dt，按帧实现也让单测可复现
constexpr int kRepeatDelayFrames = 18;
constexpr int kRepeatEveryFrames = 3;

Color resolve_fg(const Node& node, const Theme& theme) {
    if (node.props.has_fg) return node.props.fg;
    if (node.props.danger) return theme.danger;
    if (node.props.accent) return theme.accent;
    if (node.props.dim) return theme.text_dim;
    return theme.text;
}

Color resolve_bg(const Node& node, const Theme& theme) {
    if (node.props.has_bg) return node.props.bg;
    return theme.surface;
}

/// 单行按宽度裁剪：省略号优先，绝不切出半个宽字
std::string fit_line(std::string_view value, int width, Overflow mode) {
    if (width <= 0) return {};
    if (text::display_width(value) <= width) return std::string(value);
    if (mode != Overflow::ellipsis || width < 2) return text::truncate(value, width);
    return text::truncate(value, width - 1) + "\xE2\x80\xA6";
}

int line_width(std::string_view value, int scale) { return text::display_width(value) * scale; }

text::TextInput::Filter filter_for(FieldFilter filter) {
    switch (filter) {
        case FieldFilter::ascii: return text::TextInput::accept_ascii;
        case FieldFilter::digits: return text::TextInput::accept_digits;
        case FieldFilter::hex: return text::TextInput::accept_hex;
        case FieldFilter::letters: return text::TextInput::accept_letters;
        case FieldFilter::any: return text::TextInput::accept_any;
        case FieldFilter::printable:
        default: return text::TextInput::accept_printable;
    }
}

int aligned_x(const Node& node, int width) {
    switch (node.props.align_h) {
        case Align::center: return node.inner.x + std::max(0, (node.inner.w - width) / 2);
        case Align::end: return node.inner.x + std::max(0, node.inner.w - width);
        default: return node.inner.x;
    }
}

int aligned_y(const Node& node, int height) {
    if (node.props.align_v != Align::center) return node.inner.y;
    return node.inner.y + std::max(0, (node.inner.h - height) / 2);
}

} // namespace

Keys Keys::host() {
    Keys keys;
    keys.confirm = {"start"};
    keys.cancel = {"escape"};
    return keys;
}

Keys Keys::pad() {
    Keys keys;
    keys.confirm = {"a"};
    keys.cancel = {"b"};
    return keys;
}

Frame::Frame(std::string screen_id, State& state, const Theme& theme, Rect area,
             const Input* input, Keys keys)
    : screen_id_(std::move(screen_id)),
      state_(state),
      theme_(theme),
      area_(area),
      input_(input),
      keys_(std::move(keys)) {
    root_ = make_root(screen_id_);
    root_.props.gap = 0;
}

WidgetState& Frame::widget(std::string_view id) {
    return state_.screen(screen_id_).widgets[std::string(id)];
}

const WidgetState* Frame::find_widget(std::string_view id) const {
    const auto screen = state_.screens.find(screen_id_);
    if (screen == state_.screens.end()) return nullptr;
    const auto it = screen->second.widgets.find(std::string(id));
    return it == screen->second.widgets.end() ? nullptr : &it->second;
}

bool Frame::checked(std::string_view id) const {
    const WidgetState* state = find_widget(id);
    return state && state->checked;
}

void Frame::set_checked(std::string_view id, bool value) { widget(id).checked = value; }

void Frame::ensure_checked(std::string_view id, bool value) {
    if (find_widget(id)) return;
    widget(id).checked = value;
}

void Frame::ensure_field_text(std::string_view id, std::string value) {
    if (find_widget(id) && find_widget(id)->input) return;
    set_field_text(id, std::move(value));
}

const std::string& Frame::field_text(std::string_view id) const {
    const WidgetState* state = find_widget(id);
    if (!state || !state->input) return scratch_text_;
    return state->input->value();
}

void Frame::set_field_text(std::string_view id, std::string value) {
    WidgetState& state = widget(id);
    if (!state.input) state.input = std::make_unique<text::TextInput>();
    state.input->clear();
    state.input->apply(value);
}

namespace {

void ensure_visible(WidgetState& state, int count, int visible) {
    if (count <= 0) {
        state.cursor = 0;
        state.scroll = 0;
        return;
    }
    state.cursor = std::clamp(state.cursor, 0, count - 1);
    if (visible < 1) visible = 1;
    if (state.cursor < state.scroll) state.scroll = state.cursor;
    if (state.cursor >= state.scroll + visible) state.scroll = state.cursor - visible + 1;
    state.scroll = std::clamp(state.scroll, 0, std::max(0, count - visible));
}

/// 列表/选项/勾选等可聚焦项的下标：找不到返回 -1
int index_of(const std::vector<Node*>& nodes, const std::string& id) {
    for (size_t i = 0; i < nodes.size(); ++i)
        if (nodes[i]->id == id) return static_cast<int>(i);
    return -1;
}

bool any_pressed(const Input& input, const std::vector<std::string>& names) {
    for (const std::string& name : names)
        if (input.pressed(name)) return true;
    return false;
}

} // namespace

namespace {

/// scroll：把状态里的偏移写回节点（首次用声明值初始化）；布局只认节点字段
void sync_scroll_nodes(Node& node, State& state, const std::string& screen_id) {
    if (node.kind == Kind::scroll) {
        WidgetState& widget_state = state.screen(screen_id).widgets[node.id];
        if (!widget_state.scroll_ready) {
            widget_state.scroll = std::max(0, node.props.scroll);
            widget_state.scroll_x = std::max(0, node.props.scroll_x);
            widget_state.scroll_ready = true;
        }
        node.props.scroll = widget_state.scroll;
        node.props.scroll_x = widget_state.scroll_x;
    }
    for (Node& child : node.children) sync_scroll_nodes(child, state, screen_id);
}

Node* find_descendant(Node& node, const std::string& id) {
    if (node.id == id) return &node;
    for (Node& child : node.children)
        if (Node* found = find_descendant(child, id)) return found;
    return nullptr;
}

/// 焦点进入 scroll 视口外时把它滚进来；返回是否发生变化（需要重新布局）
bool follow_focus_scroll(Node& node, const std::string& focus, State& state,
                         const std::string& screen_id) {
    bool changed = false;
    if (node.kind == Kind::scroll) {
        Node* focused = find_descendant(node, focus);
        if (focused && (node.inner.h > 0 || node.inner.w > 0)) {
            WidgetState& widget_state = state.screen(screen_id).widgets[node.id];
            const int top = node.inner.y;
            const int bottom = node.inner.y + node.inner.h;
            int desired = widget_state.scroll;
            if (focused->rect.y < top) {
                desired -= top - focused->rect.y;
            } else if (focused->rect.y + focused->rect.h > bottom) {
                desired += focused->rect.y + focused->rect.h - bottom;
            }
            desired = std::max(0, desired);
            if (!node.children.empty()) {
                const Node& last = node.children.back();
                const int content_bottom =
                    last.rect.y + last.rect.h - (node.inner.y - widget_state.scroll);
                desired = std::min(desired, std::max(0, content_bottom - node.inner.h));
            }
            if (desired != widget_state.scroll) {
                widget_state.scroll = desired;
                node.props.scroll = desired;
                changed = true;
            }

            // 横向同一套规则：焦点左右出视口时刚好滚进来，右界按内容右边缘钳制
            const int left = node.inner.x;
            const int right = node.inner.x + node.inner.w;
            int desired_x = widget_state.scroll_x;
            if (focused->rect.x < left) {
                desired_x -= left - focused->rect.x;
            } else if (focused->rect.x + focused->rect.w > right) {
                desired_x += focused->rect.x + focused->rect.w - right;
            }
            desired_x = std::max(0, desired_x);
            if (!node.children.empty()) {
                const Node& last = node.children.back();
                const int content_right =
                    last.rect.x + last.rect.w - (node.inner.x - widget_state.scroll_x);
                desired_x = std::min(desired_x, std::max(0, content_right - node.inner.w));
            }
            if (desired_x != widget_state.scroll_x) {
                widget_state.scroll_x = desired_x;
                node.props.scroll_x = desired_x;
                changed = true;
            }
        }
    }
    for (Node& child : node.children)
        if (follow_focus_scroll(child, focus, state, screen_id)) changed = true;
    return changed;
}

} // namespace

std::vector<Event> Frame::run() {
    ScreenState& screen = state_.screen(screen_id_);
    sync_scroll_nodes(root_, state_, screen_id_);
    measure(root_, area_.w, theme_);
    arrange(root_, area_, theme_);
    std::vector<Node*> focusables;
    collect_focusables(root_, focusables);

    focused_id_.clear();
    int focus_index = 0;
    if (!focusables.empty()) {
        focus_index = index_of(focusables, screen.focus);
        if (focus_index < 0) focus_index = 0;
        screen.focus = focusables[static_cast<size_t>(focus_index)]->id;
        focused_id_ = screen.focus;
    }
    ime_requested_ = false;
    if (!input_) return {};

    // 文本只喂给聚焦的输入框（其余控件不消费）
    Node* focused = focusables.empty() ? nullptr : focusables[static_cast<size_t>(focus_index)];
    if (focused && focused->kind == Kind::field) {
        WidgetState& state = widget(focused->id);
        if (!state.input)
            state.input = std::make_unique<text::TextInput>(filter_for(focused->props.filter),
                                                            static_cast<size_t>(
                                                                std::max(0, focused->props.max_chars)));
        state.input->apply(input_->text());
        ime_requested_ = true;
    }

    std::vector<Event> events;
    // 方向键：点按立即生效；按住超过延迟后按固定帧间隔重复（列表翻长页时不必连点）
    const auto nav = [&screen, this](const std::string& key, bool pressed) {
        if (pressed) {
            screen.repeat_key = key;
            screen.repeat_frames = 0;
            return true;
        }
        if (!input_->down(key)) {
            if (screen.repeat_key == key) {
                screen.repeat_key.clear();
                screen.repeat_frames = 0;
            }
            return false;
        }
        if (screen.repeat_key != key) {
            screen.repeat_key = key;
            screen.repeat_frames = 0;
            return false;
        }
        ++screen.repeat_frames;
        if (screen.repeat_frames < kRepeatDelayFrames) return false;
        return (screen.repeat_frames - kRepeatDelayFrames) % kRepeatEveryFrames == 0;
    };
    const bool up = nav(keys_.up, input_->pressed(keys_.up));
    const bool down = nav(keys_.down, input_->pressed(keys_.down));
    const bool next_focus = input_->pressed(keys_.next_focus);
    const bool prev_focus = input_->pressed(keys_.prev_focus);
    const bool left = nav(keys_.left, input_->pressed(keys_.left));
    const bool right = nav(keys_.right, input_->pressed(keys_.right));
    const bool confirm = any_pressed(*input_, keys_.confirm);
    const bool cancel = any_pressed(*input_, keys_.cancel);

    if (cancel) {
        Event event;
        event.kind = EventKind::cancelled;
        event.id = focused_id_;
        events.push_back(std::move(event));
    }

    handle_focus_nav(focusables, events, up, down, left, right, confirm, next_focus, prev_focus);
    // 焦点若被滚出视口，把滚动偏移追上去并重新布局一次（只有真正变化才重排）
    if (follow_focus_scroll(root_, focused_id_, state_, screen_id_)) {
        measure(root_, area_.w, theme_);
        arrange(root_, area_, theme_);
    }
    return events;
}

void Frame::handle_focus_nav(std::vector<Node*>& focusables, std::vector<Event>& events, bool up,
                             bool down, bool left, bool right, bool confirm, bool next_focus,
                             bool prev_focus) {
    if (focusables.empty()) return;

    ScreenState& screen = state_.screen(screen_id_);
    int focus_index = index_of(focusables, focused_id_);
    if (focus_index < 0) focus_index = 0;

    // Tab / Shift(Tab) 显式换焦点：列表用上下移动光标，靠它才能离开列表去表单控件
    if (next_focus || prev_focus) {
        const int count = static_cast<int>(focusables.size());
        const int step = next_focus ? 1 : -1;
        focus_index = ((focus_index + step) % count + count) % count;
        screen.focus = focusables[static_cast<size_t>(focus_index)]->id;
        focused_id_ = screen.focus;
        return;
    }

    // 方向键落入列表内部：列表自己移动光标（焦点留在列表上），这是"一个列表就是一屏"的形态
    if (focusables[static_cast<size_t>(focus_index)]->kind == Kind::list) {
        Node& list = *focusables[static_cast<size_t>(focus_index)];
        WidgetState& state = widget(list.id);
        const int count = static_cast<int>(list.props.items.size());
        const int step = (up ? -1 : 0) + (down ? 1 : 0);
        if (step != 0 && count > 0) {
            int next = state.cursor;
            for (int guard = 0; guard < count; ++guard) {
                next = (next + step + count) % count;
                const bool disabled = static_cast<size_t>(next) < list.props.disabled.size() &&
                                      list.props.disabled[static_cast<size_t>(next)];
                if (!disabled) break;
            }
            state.cursor = next;
            ensure_visible(state, count, list.inner.h);
        }
        if (confirm && count > 0) {
            const int cursor = std::clamp(state.cursor, 0, count - 1);
            const bool disabled = static_cast<size_t>(cursor) < list.props.disabled.size() &&
                                  list.props.disabled[static_cast<size_t>(cursor)];
            if (!disabled) {
                Event event;
                event.kind = EventKind::activated;
                event.id = list.id;
                event.index = cursor;
                events.push_back(std::move(event));
            }
        }
        return;
    }

    // 表单形态：上下换焦点，左右改值，确认激活
    if (up || down) {
        const int count = static_cast<int>(focusables.size());
        focus_index = (focus_index + (down ? 1 : -1) + count) % count;
        screen.focus = focusables[static_cast<size_t>(focus_index)]->id;
        focused_id_ = screen.focus;
    }

    Node& focused = *focusables[static_cast<size_t>(focus_index)];
    WidgetState& state = widget(focused.id);

    if (focused.kind == Kind::option) {
        int delta = 0;
        if (left && !right) delta = -1;
        else if (right && !left) delta = 1;
        else if (confirm && !left && !right) delta = 1;
        if (delta != 0) {
            Event event;
            event.kind = EventKind::changed;
            event.id = focused.id;
            event.delta = delta;
            event.confirm = confirm && !left && !right;
            events.push_back(std::move(event));
        }
        return;
    }
    if (focused.kind == Kind::checkbox) {
        if (confirm) {
            state.checked = !state.checked;
            Event event;
            event.kind = EventKind::changed;
            event.id = focused.id;
            event.flag = state.checked;
            events.push_back(std::move(event));
        }
        return;
    }
    if (focused.kind == Kind::button) {
        if (confirm) {
            Event event;
            event.kind = EventKind::activated;
            event.id = focused.id;
            events.push_back(std::move(event));
        }
        return;
    }
    if (focused.kind == Kind::field) {
        ensure_visible(state, 1, 1);
        if (confirm) {
            Event event;
            event.kind = EventKind::submitted;
            event.id = focused.id;
            event.text = state.input ? state.input->value() : std::string();
            events.push_back(std::move(event));
        }
    }
}

// ---------------------------------------------------------------- 绘制

namespace {

void paint_node(Screen& screen, Node& node, const Theme& theme, const State& state,
                const std::string& screen_id, const std::string& focus);

/// 整棵子树平移（scroll 绘制时把子项移到临时视口坐标系，画完再移回）
void shift_subtree(Node& node, int dx, int dy) {
    node.rect.x += dx;
    node.rect.y += dy;
    node.inner.x += dx;
    node.inner.y += dy;
    for (Node& child : node.children) shift_subtree(child, dx, dy);
}

void paint_border(Screen& screen, const Node& node, const Theme& theme, bool focused) {
    const Rect rect = node.rect;
    if (rect.w < 2 || rect.h < 2) return;
    const Glyphs& g = theme.glyphs;
    const Color color = focused ? theme.border_focus : theme.border;
    const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
    Surface surface(screen, rect.x, rect.y, rect.w, rect.h);
    for (int x = 1; x < rect.w - 1; ++x) {
        surface.put(x, 0, g.h, color, bg);
        surface.put(x, rect.h - 1, g.h, color, bg);
    }
    for (int y = 1; y < rect.h - 1; ++y) {
        surface.put(0, y, g.v, color, bg);
        surface.put(rect.w - 1, y, g.v, color, bg);
    }
    surface.put(0, 0, g.tl, color, bg);
    surface.put(rect.w - 1, 0, g.tr, color, bg);
    surface.put(0, rect.h - 1, g.bl, color, bg);
    surface.put(rect.w - 1, rect.h - 1, g.br, color, bg);
    if (!node.props.title.empty() && rect.w >= 6) {
        const std::string title = " " + text::truncate(node.props.title, rect.w - 5) + " ";
        surface.print(2, 0, title, color, bg);
    }
}

void paint_text(Screen& screen, const Node& node, const Theme& theme) {
    const int scale = node.props.scale > 0 ? node.props.scale : 1;
    const int width = node.inner.w;
    if (width <= 0 || node.props.text.empty()) return;
    Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
    const Color fg = resolve_fg(node, theme);
    const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;

    std::vector<std::string> lines;
    if (node.props.overflow == Overflow::wrap && width / scale >= 1) {
        const size_t cap = node.props.lines > 0 ? static_cast<size_t>(node.props.lines) : 1024;
        lines = text::wrap(node.props.text, static_cast<size_t>(std::max(1, width / scale)), cap);
    } else {
        lines.push_back(fit_line(node.props.text, std::max(1, width / scale),
                                 node.props.overflow));
    }
    int y = aligned_y(node, static_cast<int>(lines.size()) * scale);
    for (const std::string& line : lines) {
        const int x = aligned_x(node, line_width(line, scale));
        surface.print(x - node.inner.x, y - node.inner.y, line, fg, bg,
                      static_cast<uint8_t>(scale));
        y += scale;
    }
}

void paint_list(Screen& screen, const Node& node, const Theme& theme, const State& state,
                const std::string& screen_id, const std::string& focus) {
    const auto screen_it = state.screens.find(screen_id);
    const WidgetState* widget = nullptr;
    if (screen_it != state.screens.end()) {
        const auto it = screen_it->second.widgets.find(node.id);
        if (it != screen_it->second.widgets.end()) widget = &it->second;
    }
    const int cursor = widget ? widget->cursor : 0;
    const int scroll = widget ? widget->scroll : 0;
    const int visible = std::max(1, node.inner.h);
    Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
    const bool focused = node.id == focus;
    const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
    for (int row = 0; row < visible; ++row) {
        const int index = scroll + row;
        if (index >= static_cast<int>(node.props.items.size())) break;
        const bool selected = index == cursor;
        const bool disabled = static_cast<size_t>(index) < node.props.disabled.size() &&
                              node.props.disabled[static_cast<size_t>(index)];
        const Color fg = disabled ? theme.disabled
                                  : (selected && focused ? theme.selection_fg : resolve_fg(node, theme));
        surface.put(node.props.indent, row,
                    selected ? theme.glyphs.cursor : U' ', focused ? theme.accent : fg, bg);
        const std::string& item = node.props.items[static_cast<size_t>(index)];
        const int text_x = node.props.indent + node.props.text_gap;
        const int width = std::max(0, node.inner.w - text_x);
        surface.print(text_x, row, fit_line(item, width, Overflow::ellipsis), fg, bg);
    }
}

void paint_node(Screen& screen, Node& node, const Theme& theme, const State& state,
                const std::string& screen_id, const std::string& focus) {
    const bool focused = !node.id.empty() && node.id == focus;

    if (node.props.opaque) {
        Surface surface(screen, node.rect.x, node.rect.y, node.rect.w, node.rect.h);
        surface.fill(0, 0, node.rect.w, node.rect.h, U' ', resolve_fg(node, theme),
                     resolve_bg(node, theme));
    }
    if (node.props.border != Border::none) paint_border(screen, node, theme, focused);

    switch (node.kind) {
        case Kind::scroll: {
            // 视口裁剪：子项先画进"视口大小的临时屏"，再把非空格搬回主屏。
            // 这样任意子项（含嵌套容器/宽字/缩放块）都被天然裁在视口内，
            // 不需要给每个绘制函数都加一个 clip 参数
            if (node.inner.w <= 0 || node.inner.h <= 0) break;
            Screen viewport(node.inner.w, node.inner.h);
            viewport.clear_transparent();
            const int dx = -node.inner.x;
            const int dy = -node.inner.y;
            for (Node& child : node.children) {
                shift_subtree(child, dx, dy);
                paint_node(viewport, child, theme, state, screen_id, focus);
                shift_subtree(child, -dx, -dy);
            }
            for (int y = 0; y < viewport.height(); ++y) {
                for (int x = 0; x < viewport.width(); ++x) {
                    const Cell& cell = viewport.at(x, y);
                    if (cell.ch != U' ' || cell.alpha != 0)
                        screen.set(node.inner.x + x, node.inner.y + y, cell);
                }
            }
            break;
        }
        case Kind::text: paint_text(screen, node, theme); break;
        case Kind::divider: {
            if (node.inner.w <= 0) break;
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            const Color color = node.props.has_fg ? node.props.fg : theme.border;
            const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
            surface.put(0, 0, theme.glyphs.h, color, bg);
            surface.print(1, 0, std::string(static_cast<size_t>(std::max(0, node.inner.w - 1)),
                                            theme.glyphs.h),
                          color, bg);
            break;
        }
        case Kind::spacer: break;
        case Kind::list:
            paint_list(screen, node, theme, state, screen_id, focus);
            break;
        case Kind::option:
        case Kind::button: {
            if (node.inner.w <= 0) break;
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            const Color fg = node.props.enabled ? (focused ? theme.selection_fg : resolve_fg(node, theme))
                                                : theme.disabled;
            const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
            if (focused)
                surface.put(node.props.indent, 0, theme.glyphs.cursor, theme.accent, bg);
            const int text_x = node.props.indent + node.props.text_gap;
            surface.print(text_x, 0,
                          fit_line(node.props.text, std::max(0, node.inner.w - text_x),
                                   Overflow::ellipsis),
                          fg, bg);
            break;
        }
        case Kind::table: {
            if (node.inner.w <= 0 || node.inner.h <= 0) break;
            const auto widths = table_column_widths(node.props, node.inner.w);
            if (widths.empty()) break;
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
            const Color row_fg = node.props.has_fg ? node.props.fg : theme.text;
            const int columns = static_cast<int>(widths.size());
            const auto column_x = [&](int index) {
                int x = 0;
                for (int i = 0; i < index; ++i) x += widths[static_cast<size_t>(i)] + 2;
                return x;
            };
            int y = 0;
            const auto paint_row = [&](const std::vector<std::string>& cells, Color fg) {
                for (int i = 0; i < columns; ++i) {
                    const int width = widths[static_cast<size_t>(i)];
                    if (width <= 0) continue;
                    const std::string cell =
                        i < static_cast<int>(cells.size()) ? cells[static_cast<size_t>(i)]
                                                          : std::string();
                    const Align align = i < static_cast<int>(node.props.col_align.size())
                                            ? node.props.col_align[static_cast<size_t>(i)]
                                            : Align::start;
                    const std::string shown = fit_line(cell, width, node.props.overflow);
                    const int gap = std::max(0, width - text::display_width(shown));
                    int left = 0;
                    if (align == Align::center) left = gap / 2;
                    else if (align == Align::end) left = gap;
                    surface.print(column_x(i) + left, y, shown, fg, bg);
                }
                ++y;
            };
            if (!node.props.columns.empty()) {
                paint_row(node.props.columns, theme.text_dim);
                for (int x = 0; x < node.inner.w; ++x)
                    surface.put(x, y, U'\u2500', theme.border, bg);
                ++y;
            }
            for (const auto& row : node.props.rows) paint_row(row, row_fg);
            break;
        }
        case Kind::stat: {
            if (node.inner.w <= 0) break;
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
            const int label_w = node.props.label_w > 0 ? node.props.label_w : theme.metrics.label_w;
            surface.print(0, 0,
                          fit_line(node.props.text, std::max(0, node.inner.w - label_w - 1),
                                   Overflow::ellipsis),
                          theme.text_dim, bg);
            const int value_w = text::display_width(node.props.value);
            surface.print(std::max(0, node.inner.w - value_w - 1), 0,
                          fit_line(node.props.value, node.inner.w, Overflow::ellipsis),
                          node.props.accent ? theme.accent : resolve_fg(node, theme), bg);
            break;
        }
        case Kind::checkbox: {
            if (node.inner.w <= 0) break;
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            const auto it = state.screens.find(screen_id);
            bool checked_value = false;
            if (it != state.screens.end()) {
                const auto widget = it->second.widgets.find(node.id);
                if (widget != it->second.widgets.end()) checked_value = widget->second.checked;
            }
            const Color fg = node.props.enabled ? (focused ? theme.selection_fg : resolve_fg(node, theme))
                                                : theme.disabled;
            const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
            if (focused)
                surface.put(node.props.indent, 0, theme.glyphs.cursor, theme.accent, bg);
            const int box_x = node.props.indent + node.props.text_gap;
            surface.print(box_x, 0, checked_value ? "[x]" : "[ ]", focused ? theme.accent : fg, bg);
            surface.print(box_x + 4, 0,
                          fit_line(node.props.text, std::max(0, node.inner.w - box_x - 4),
                                   Overflow::ellipsis),
                          fg, bg);
            break;
        }
        case Kind::field: {
            if (node.inner.w <= 0) break;
            const auto it = state.screens.find(screen_id);
            std::string value = node.props.text;
            if (it != state.screens.end()) {
                const auto widget = it->second.widgets.find(node.id);
                if (widget != it->second.widgets.end() && widget->second.input)
                    value = widget->second.input->value();
            }
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
            const bool empty = value.empty();
            const std::string shown = empty ? node.props.text : value;
            const Color fg = empty ? theme.text_dim : resolve_fg(node, theme);
            surface.put(node.props.indent, 0, U'>', focused ? theme.accent : theme.text_dim, bg);
            surface.print(node.props.indent + 2, 0,
                          fit_line(shown, std::max(0, node.inner.w - node.props.indent - 2),
                                   Overflow::ellipsis),
                          fg, bg);
            if (focused && !empty) {
                const int caret = node.props.indent + 2 + text::display_width(value);
                if (caret < node.inner.w) surface.put(caret, 0, U'_', theme.accent, bg);
            }
            break;
        }
        case Kind::bar: {
            if (node.inner.w < 2) break;
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            const Color bg = node.props.opaque ? resolve_bg(node, theme) : kKeepBg;
            // ratio 来自调用方/脚本：非有限（NaN/inf）不得进入 int 转换（UB），一律按 0；其余钳到 0..1
            const float ratio = std::isfinite(node.props.ratio)
                                    ? std::clamp(node.props.ratio, 0.0f, 1.0f)
                                    : 0.0f;
            const int span = node.inner.w - 2;
            const int filled = static_cast<int>(ratio * static_cast<float>(span) + 0.5f);
            // 填充色可由 fg 覆盖：血条/油条/经验条需要不同颜色，但形状仍是同一个组件
            const Color fill = node.props.has_fg ? node.props.fg : theme.accent;
            surface.put(0, 0, U'[', theme.border, bg);
            surface.put(node.inner.w - 1, 0, U']', theme.border, bg);
            for (int i = 0; i < span; ++i) {
                const bool on = i < filled;
                surface.put(1 + i, 0, on ? U'#' : U'-', on ? fill : theme.disabled, bg);
            }
            break;
        }
        case Kind::hint: {
            if (node.inner.w <= 0 || node.props.items.empty()) break;
            std::string line;
            for (size_t i = 0; i < node.props.items.size(); i += 2) {
                if (i > 0) line += "  ";
                line += "[" + node.props.items[i] + "]";
                if (i + 1 < node.props.items.size()) line += " " + node.props.items[i + 1];
            }
            Surface surface(screen, node.inner.x, node.inner.y, node.inner.w, node.inner.h);
            surface.print(0, 0, fit_line(line, node.inner.w, Overflow::ellipsis), theme.text_dim,
                          node.props.opaque ? resolve_bg(node, theme) : kKeepBg);
            break;
        }
        default: break;
    }

    if (node.kind != Kind::scroll)
        for (Node& child : node.children)
            paint_node(screen, child, theme, state, screen_id, focus);
}

} // namespace

void Frame::paint(Screen& screen) {
    paint_node(screen, root_, theme_, state_, screen_id_, focused_id_);
}

} // namespace phos::ui
#include "api/host_api.hpp"

#include "api/text_field.hpp"

#include "api/assets_api.hpp"
#include "api/audio_api.hpp"
#include "api/layer_api.hpp"
#include "api/lua_sandbox.hpp"
#include "api/lua_value.hpp"
#include "api/net_api.hpp"
#include "api/score_api.hpp"
#include "api/scene_api.hpp"
#include "api/ui_api.hpp"
#include "api/ui_options.hpp"
#include "cart/cartridge.hpp"
#include "core/defaults.hpp"
#include "core/format.hpp"
#include "core/log.hpp"
#include "core/surface.hpp"
#include "core/text.hpp"
#include "core/version.hpp"

#include <sol/sol.hpp>

#include <cmath>
#include <cstdio>
#include <set>
#include <utility>

namespace phos {

namespace {

/// 内容区那一块面。每次现取：皮肤几何与面板宽度都能在运行时改，
/// 缓存下来就会拿旧几何去画
Surface content_surface(HostContext& host) {
    return Surface(*host.screen, host.content_x, host.content_y, host.content_w, host.content_h);
}

/// 侧栏面板那一块面（面板坐标局部于面板区）
Surface panel_surface(HostContext& host) {
    return Surface(*host.screen, host.panel_origin_x(), host.content_y, host.panel_w,
                   host.content_h);
}

/// screen / panel 两张面的唯一选择点：绑定里只差 is_panel 一处
Surface surface_for(HostContext& host, bool is_panel) {
    return is_panel ? panel_surface(host) : content_surface(host);
}

// 默认取色 helper 在 lua_value 里（区域绑定也用同一份），这里只是引入名字
using api::default_bg;
using api::default_fg;

/// 篮子文案 → Localized：字符串（中英同文）或 `{ zh = …, en = … }` 表。
/// 控制台按当前界面语言取一份，于是切换语言时篮子文案跟着变
Localized read_label(const sol::object& object) {
    const lua_sandbox::Localized read = lua_sandbox::read_localized(object);
    Localized out;
    out.zh = read.zh;
    out.en = read.en;
    return out;
}

/// 折叠分组路径：`"武器"` / `{ zh =, en = }` = 单层；数组 = 多层（每项又是一个标签）。
/// 缺省/空 = 顶层直接显示
std::vector<Localized> read_group_path(const sol::object& object) {
    std::vector<Localized> path;
    if (object.is<std::string>()) {
        path.push_back(read_label(object));
    } else if (object.is<sol::table>()) {
        const sol::table t = object.as<sol::table>();
        if (t["zh"].is<std::string>() || t["en"].is<std::string>()) {
            path.push_back(read_label(object));  // 单层本地化标签
        } else {
            for (size_t i = 1; i <= t.size(); ++i) path.push_back(read_label(t[i]));
        }
    }
    return path;
}

/// 给 `phos.screen` / `phos.panel` 绑定**同一套**绘制方法（put/print/fill/clear/blit/blend/
/// back/back_rect/plot）。两组只差两件事：画到哪块 `Surface`、写底色的默认值——
/// 都由 `is_panel` 一处决定。抽到一处后，"省略底色的规则"只有一份实现。
/// 绑定只捕获 `HostContext&` 与 `bool`：**不捕获 std::function/lambda**，否则 sol2
/// 在关闭 Lua 时析构这些闭包会崩（闭包按值存非平凡对象时的 GC 析构问题）。
void bind_surface_api(sol::table& t, HostContext& host, bool is_panel) {
    t["put"] = [&host, is_panel](int x, int y, const sol::object& ch, sol::object fg,
                                 sol::object bg, sol::optional<int> scale) {
        Surface s = surface_for(host, is_panel);
        s.put(x, y, api::parse_ch(ch, U' '), api::parse_fg(fg, default_fg(host)),
              api::parse_bg(bg, default_bg(host), true), api::read_scale(scale));
    };
    t["print"] = [&host, is_panel](int x, int y, const std::string& text, sol::object fg,
                                   sol::object bg, sol::optional<int> scale) {
        Surface s = surface_for(host, is_panel);
        s.print(x, y, text, api::parse_fg(fg, default_fg(host)),
                api::parse_bg(bg, default_bg(host), true), api::read_scale(scale));
    };
    // fill / clear：省略底色 = 本面的默认底色（screen=色板 black；panel=主题面板色）。
    // 清屏若按"保留背景"来就变成什么都不做
    t["fill"] = [&host, is_panel](int x, int y, int w, int h, const sol::object& ch,
                                  sol::object fg, sol::object bg) {
        // 默认底色必须**调用时**取：panel_bg 跟着主题热更新，注册时缓存会画错色
        const Color fallback_bg = is_panel ? host.panel_bg : default_bg(host);
        surface_for(host, is_panel)
            .fill(x, y, w, h, api::parse_ch(ch, U' '), api::parse_fg(fg, default_fg(host)),
                  api::parse_bg(bg, fallback_bg, false));
    };
    t["clear"] = [&host, is_panel](sol::object fg, sol::object bg) {
        const Color fallback_bg = is_panel ? host.panel_bg : default_bg(host);
        surface_for(host, is_panel)
            .clear(api::parse_fg(fg, default_fg(host)), api::parse_bg(bg, fallback_bg, false));
    };
    // blit / back / back_rect：省略底色 = 激活色板的 black（与 screen 同组，不随面板色）——
    // 这族是"整块搬运 / 只改一块底色"，默认与内容区一致
    t["blit"] = [&host, is_panel](int x, int y, sol::object rows, sol::object fg, sol::object bg) {
        surface_for(host, is_panel)
            .blit(x, y, api::read_rows(rows), api::parse_fg(fg, default_fg(host)),
                  api::parse_bg(bg, default_bg(host), false));
    };
    // 叠一笔 / 只改底色 / 落半格：前两件与 put 同组（底色省略 = 保留），第三件没有底色参数
    t["blend"] = [&host, is_panel](int x, int y, sol::object ch, sol::object fg) {
        return surface_for(host, is_panel)
            .blend(x, y, api::parse_ch(ch, U' '), api::parse_fg(fg, default_fg(host)));
    };
    t["back"] = [&host, is_panel](int x, int y, sol::object bg) {
        surface_for(host, is_panel).back(x, y, api::parse_bg(bg, default_bg(host), false));
    };
    t["back_rect"] = [&host, is_panel](int x, int y, int w, int h, sol::object bg) {
        surface_for(host, is_panel)
            .back_rect(x, y, w, h, api::parse_bg(bg, default_bg(host), false));
    };
    t["plot"] = [&host, is_panel](int x, int y, sol::object fg) {
        surface_for(host, is_panel).plot(x, y, api::parse_fg(fg, default_fg(host)));
    };
}

/// 存档表值的嵌套上限：卡带写的表最多 8 层（与文档一致），再深写入失败
constexpr int kMaxSaveDepth = 8;

/// Lua 表的键 → 字符串：文本原样、数字/布尔转文本；表/函数/userdata 键拒绝
bool save_key_from_lua(const sol::object& key, std::string& out) {
    if (key.is<std::string>()) {
        out = key.as<std::string>();
        return true;
    }
    if (key.is<long long>()) {
        out = std::to_string(key.as<long long>());
        return true;
    }
    if (key.is<double>()) {
        const double number = key.as<double>();
        if (!std::isfinite(number)) return false;
        char buffer[32];
        std::snprintf(buffer, sizeof(buffer), "%g", number);
        out = buffer;
        return true;
    }
    if (key.is<bool>()) {
        out = key.as<bool>() ? "true" : "false";
        return true;
    }
    return false;
}

/// Lua 值 → 存档值：连续 1..n 整数键的表是数组，其余表是对象。
/// 函数/userdata/thread、环引用、超过深度的表一律拒绝——写入失败好过存下半份。
/// 遇到第一个非法值就返回 false，调用方据此向卡带回报失败。
bool save_value_from_lua(const sol::object& value, json::Value& out, int depth,
                         std::set<const void*>& path) {
    switch (value.get_type()) {
        case sol::type::boolean: out = json::Value::of_boolean(value.as<bool>()); return true;
        case sol::type::number: {
            const double number = value.as<double>();
            if (!std::isfinite(number)) return false;  // NaN/inf 写进 JSON 会得到非法文档
            out = json::Value::of_number(number);
            return true;
        }
        case sol::type::string: out = json::Value::of_text(value.as<std::string>()); return true;
        case sol::type::table: break;
        default: return false;
    }
    if (depth <= 0) return false;  // 超深：存档只收 8 层以内的表

    const sol::table table = value.as<sol::table>();
    const void* identity = table.pointer();
    if (identity && !path.insert(identity).second) return false;  // 环引用
    struct PopPath {
        std::set<const void*>& path;
        const void* identity;
        ~PopPath() {
            if (identity) path.erase(identity);
        }
    } pop{path, identity};

    // 连续 1..n 整数键 = 数组（空表按对象处理：{} 与 [] 对读的人来说一样）
    size_t count = 0;
    long long max_key = 0;
    bool sequence = true;
    for (const auto& entry : table) {
        if (!entry.first.is<long long>()) {
            sequence = false;
            break;
        }
        const long long key = entry.first.as<long long>();
        if (key < 1) {
            sequence = false;
            break;
        }
        ++count;
        if (key > max_key) max_key = key;
    }
    if (sequence && count > 0 && static_cast<size_t>(max_key) == count) {
        out = json::Value::of_array();
        out.items.reserve(count);
        for (long long i = 1; i <= max_key; ++i) {
            json::Value item;
            if (!save_value_from_lua(table[i], item, depth - 1, path)) return false;
            out.items.push_back(std::move(item));
        }
        return true;
    }

    out = json::Value::of_object();
    for (const auto& entry : table) {
        std::string key;
        if (!save_key_from_lua(entry.first, key)) return false;
        json::Value item;
        if (!save_value_from_lua(entry.second, item, depth - 1, path)) return false;
        // 键转字符串后撞车（如 [1] 与 ["1"]）会静默丢一个：拒绝比丢数据诚实
        if (!out.members.emplace(std::move(key), std::move(item)).second) return false;
    }
    return true;
}

/// 存档值 → Lua 值：read 返回与写入时同构的表（数组 1..n、对象字符串键）
sol::object save_value_to_lua(lua_State* state, const json::Value& value) {
    switch (value.kind) {
        case json::Value::Kind::text: return sol::make_object(state, value.text);
        case json::Value::Kind::number: return sol::make_object(state, value.number);
        case json::Value::Kind::boolean: return sol::make_object(state, value.boolean);
        case json::Value::Kind::array: {
            sol::table table = sol::state_view(state).create_table();
            for (size_t i = 0; i < value.items.size(); ++i)
                table[static_cast<int>(i) + 1] = save_value_to_lua(state, value.items[i]);
            return table;
        }
        case json::Value::Kind::object: {
            sol::table table = sol::state_view(state).create_table();
            for (const auto& [key, child] : value.members)
                table[key] = save_value_to_lua(state, child);
            return table;
        }
        default: return sol::nil;
    }
}

/// 动作表查询：未注册返回 nullptr（调用方据此走"默认映射同名虚拟键"）
const std::vector<std::string>* action_keys_for(const HostContext& host, const std::string& name) {
    const auto it = host.input_actions.find(name);
    return it == host.input_actions.end() ? nullptr : &it->second;
}

/// 动作名/绑定键名的最小合法性：可见 ASCII、非空、长度受限（虚拟键名本来就长这样）
bool valid_input_name(const std::string& name) {
    if (name.empty() || name.size() > 64) return false;
    for (unsigned char c : name) {
        if (c < 33 || c > 126) return false;
    }
    return true;
}

} // namespace

void apply_palette_to(sol::state& lua, const Palette& palette) {
    sol::table color = lua["phos"]["color"];
    for (size_t i = 0; i < kPaletteSlots; ++i)
        color[palette_slot_name(static_cast<PaletteSlot>(i))] = palette.slots[i];
}

void register_host_api(sol::state& lua, HostContext& host) {
    // --- Color 类型 ---
    lua.new_usertype<Color>("Color",
        sol::constructors<Color()>(),
        "r", &Color::r, "g", &Color::g, "b", &Color::b);

    sol::table phos = lua.create_named_table("phos");

    // --- phos.color（常量取自激活色板，热切换时由 apply_palette_to 更新） ---
    sol::table color = phos.create_named("color");
    // 参数走 sol::object：Lua 数字可能是浮点/NaN/超大，先按 double 校验再钳位
    // （直接收 int，坏值会在 sol2 转换处就是 UB）。钳位统一在 core/color.hpp 的 rgb_clamped
    color["rgb"] = [](sol::object r, sol::object g, sol::object b) {
        return rgb_clamped(api::read_channel(r), api::read_channel(g), api::read_channel(b));
    };
    if (host.palette) apply_palette_to(lua, *host.palette);

    // --- phos.screen（局部坐标：内容区左上角为 (0,0)） ---
    sol::table screen = phos.create_named("screen");
    screen["size"] = [&host]() { return std::make_tuple(host.content_w, host.content_h); };
    // 内容区尺寸是常量（与主题无关，见 docs/api-reference.md），直接给字段更顺手
    screen["width"] = host.content_w;
    screen["height"] = host.content_h;
    // 可玩区：内容区扣掉侧栏以后的那一块（x, y, w, h）。画"游戏画面"应该用它——
    // 用 size() 会把侧栏覆盖的部分一起算进来，从 0 画到 w 就有几列藏在侧栏后面，
    // 玩家只会看到"东西突然冒出来"。扣的还有面板左侧那 1 列主机分隔线
    // （见 app.cpp：分隔线画在 panel_origin_x()-1），它不属于卡带可画范围。
    // 面板宽度可在运行时改（phos.panel.resize），所以这里是**函数**而非字段：每次按当前宽度算
    screen["playfield"] = [&host]() {
        const int w = host.content_w - host.panel_w - (host.panel_w > 0 ? 1 : 0);
        return std::make_tuple(0, 0, w < 0 ? 0 : w, host.content_h);
    };
    // 绘制方法统一绑定（与 panel 同一套实现）：screen 的默认底色 = 激活色板的 black
    bind_surface_api(screen, host, /*is_panel=*/false);
    // 位掩码 → 象限字形。"这一格的四个子位里哪几个有内容"由卡带自己算（那是它的数据），
    // 但**位序**与字形表归引擎 —— 副本一旦有两份，迟早有一份把左上和右上写反，
    // 画出来的东西与判定就对不上
    screen["quadrant"] = [](int bits) {
        std::string glyph;
        text::append_utf8(glyph, Screen::quadrant_glyph(static_cast<uint8_t>(bits)));
        return glyph;
    };
    // 子格坐标 → 格 + 子位：卡带的相机、降水、光柱共用这一份换算。
    // 各处自己写 floor(u/2) 会长出两套网格，差半格就是"看着陷进墙里"
    screen["cell_of"] = [](int x2, int y2) {
        const Screen::SubCell at = Screen::cell_of(x2, y2);
        return std::make_tuple(at.x, at.y, static_cast<int>(at.bit));
    };
    screen["get"] = [&host](int x, int y) {
        const Surface surface = content_surface(host);
        const Cell& c = surface.at(x, y);
        std::string out;
        // 取字规则与屏幕文本导出（--dump-screen / screen.read）是同一份判断
        // （Screen::glyph_at）：续格报头格字符、控制字符不算内容。
        // 两处若各写一套，agent 读到的画面就会与 dump 出来的文本对不上
        if (const char32_t ch = surface.glyph_at(x, y)) text::append_utf8(out, ch);
        return std::make_tuple(out, c.fg, c.bg);
    };

    // --- phos.panel（侧栏面板：坐标局部于面板区，主机统一画分隔线） ---
    // 面板内容完全由卡带决定：分数记录、地图、图鉴……
    sol::table panel = phos.create_named("panel");
    panel["size"] = [&host]() { return std::make_tuple(host.panel_w, host.content_h); };
    // 运行时改面板宽度（0 = 收起）：宽度是与主机共享的布局量，分隔线、面板局部坐标
    // 都跟着变，所以只留 host.panel_w 一个真源。返回钳制后的实际宽度
    panel["resize"] = [&host](int w) {
        host.panel_w = clamp_panel_w(w);
        return host.panel_w;
    };
    // 绘制方法与 screen 同一套；panel 的默认底色 = 主题面板色（skin.panel，由 App 写入）：
    // 右栏不属于游戏画面，底色随主题，而不是透出游戏、也不是砸一块写死的黑
    bind_surface_api(panel, host, /*is_panel=*/true);

    // --- phos.debug（把卡带的可调参数交给 `~` 调试台做实时微调） ---
    // 三个注册入口：number（浮点滑条）/ integer（整数滑条）/ toggle（复选框）。
    // 参数形状相同：name（可 {zh,en}）+ get + set + opts（min / max / step / group）。
    // 注册随卡带生命周期；未挂卡带（无卡 / 宿主动画脚本）时安全无效
    sol::table debug = phos.create_named("debug");
    auto bind_debug = [&host](sol::table& t, const char* key, DebugKind kind) {
        t[key] = [&host, kind](sol::object name, sol::protected_function get,
                               sol::protected_function set, sol::optional<sol::table> opts) {
            if (!host.cart) return;
            float min = 0.0f, max = 1.0f, step = 0.01f;
            std::vector<Localized> group;
            if (opts) {
                const sol::table ot = *opts;
                min = static_cast<float>(api::read_number(ot, "min", min));
                max = static_cast<float>(api::read_number(ot, "max", max));
                step = static_cast<float>(api::read_number(ot, "step", step));
                group = read_group_path(ot["group"]);
            }
            host.cart->debug_register(read_label(name), std::move(group), kind, std::move(get),
                                      std::move(set), min, max, step);
        };
    };
    bind_debug(debug, "number", DebugKind::number);
    bind_debug(debug, "integer", DebugKind::integer);
    bind_debug(debug, "toggle", DebugKind::boolean);

    // --- phos.text（文本度量） ---
    // 中文一个字占两格，卡带要自己排版（居中、对齐、定宽字段）就得先问宽度，
    // 而不是拿 #str 当列数——那是字节数，中文会被算成 3 格
    sol::table text_api = phos.create_named("text");
    text_api["width"] = [](const std::string& s) { return text::display_width(s); };
    text_api["truncate"] = [](const std::string& s, int cols) { return text::truncate(s, cols); };
    // 定宽位置（侧栏、状态条）的文案要"看得出被裁"：裁掉了就补省略号。
    // 主机在右侧是硬切，会留下"[↑/A] 跳：按住更"这种半句话，玩家只能靠猜。
    // 宽度按显示宽度算，全角字符不会被切成半个。
    text_api["fit"] = [](const std::string& s, int cols) -> std::string {
        if (cols <= 0) return std::string();
        if (text::display_width(s) <= cols) return s;
        return text::truncate(s, cols - 1) + "…";
    };
    // 定宽排版的对齐：按**显示宽度**补空格。不要用 string.format 的 %-Ns —— 那个按
    // 字节数补，"队友交给 AI" 这类中英混排会整列歪掉（汉字 3 字节、字母 1 字节）
    text_api["pad"] = [](const std::string& s, int cols) {
        const int w = text::display_width(s);
        if (cols > kMaxPadCols) cols = kMaxPadCols;  // 坏值不该让我们分配几个 GB
        return w >= cols ? s : s + std::string(static_cast<size_t>(cols - w), ' ');
    };
    text_api["pad_left"] = [](const std::string& s, int cols) {
        const int w = text::display_width(s);
        if (cols > kMaxPadCols) cols = kMaxPadCols;
        return w >= cols ? s : std::string(static_cast<size_t>(cols - w), ' ') + s;
    };
    // 字形在格内的墨迹框（xoff, width, approx）：比例字体的墨迹比一整格窄，
    // "底板/装饰按字身算宽度"要靠它。拿不到字体度量时给整格宽并注明 approx
    text_api["ink_box"] = [&host](const sol::object& ch) {
        const char32_t cp = api::read_char(ch, U' ');
        const GlyphBox box = host.glyph_metrics ? host.glyph_metrics(cp) : GlyphBox{0, host.cell_px, true};
        return std::make_tuple(box.xoff, box.width, box.approx);
    };

    // 数值读成 long long：卡带可能传浮点（计时/比例），坏值按 0 处理而不是 UB
    const auto read_integer = [](const sol::object& value) -> long long {
        if (value.is<int>()) return value.as<int>();
        if (value.is<double>()) {
            const double number = value.as<double>();
            if (!std::isfinite(number)) return 0;
            return static_cast<long long>(number < 0 ? number - 0.5 : number + 0.5);
        }
        return 0;
    };
    const auto read_ratio = [](const sol::object& value) -> double {
        if (value.is<double>()) return value.as<double>();
        if (value.is<int>()) return static_cast<double>(value.as<int>());
        return 0.0;
    };

    // 展示格式化：分数千分位、计时 mm:ss、百分比。卡带与主机展示共用 core/format，
    // 各写一份迟早会在"四位数怎么断"上不一致
    text_api["score"] = [read_integer](const sol::object& value) {
        return format::score(read_integer(value));
    };
    text_api["clock"] = [read_integer](const sol::object& value) {
        return format::clock(read_integer(value));
    };
    text_api["percent"] = [read_ratio, read_integer](const sol::object& value,
                                                     sol::optional<int> digits) {
        return format::percent(read_ratio(value), digits.value_or(1));
    };

    // --- phos.input ---
    sol::table input = phos.create_named("input");
    // 键就是名字：主机不做白名单，任何名字都能查（没见过 = 一直是松开）。
    // 卡带因此可以要多少键就多少键，也能读存档里的绑定名直接查状态
    input["down"] = [&host](const std::string& key) { return host.input->down(key); };
    input["pressed"] = [&host](const std::string& key) { return host.input->pressed(key); };
    input["released"] = [&host](const std::string& key) { return host.input->released(key); };

    // 动作映射：把"跳跃/确认/左"绑到一组虚拟键，查询时任一键满足即为真。
    // keys 省略或 nil = 只查询；未注册的动作默认映射同名虚拟键（action_down("left")==down("left")）。
    // 动作表按脚本会话存在（HostContext::input_actions，HostCartBinding 清理），不写盘、不跨卡带。
    input["action"] = [&host, &lua](const std::string& name,
                                    sol::optional<sol::object> keys) -> sol::object {
        if (!valid_input_name(name)) {
            log::warn("phos.input.action: invalid action name");
            return sol::nil;
        }
        if (keys && keys->get_type() != sol::type::nil) {
            std::vector<std::string> list;
            const sol::object value = *keys;
            if (value.is<std::string>()) {
                list.push_back(value.as<std::string>());
            } else if (value.is<sol::table>()) {
                const sol::table table = value.as<sol::table>();
                // 只接受数组形态：带字符串键的表不是"键列表"，按非法处理
                for (const auto& entry : table) {
                    if (!entry.first.is<long long>()) {
                        log::warn("phos.input.action: keys must be an array of strings");
                        return sol::nil;
                    }
                }
                for (std::size_t i = 1; i <= table.size(); ++i) {
                    const sol::object item = table[static_cast<int>(i)];
                    if (!item.is<std::string>()) {
                        log::warn("phos.input.action: keys must be an array of strings");
                        return sol::nil;
                    }
                    list.push_back(item.as<std::string>());
                }
            } else {
                log::warn("phos.input.action: keys must be a string or an array of strings");
                return sol::nil;
            }
            if (list.size() > 16) {
                log::warn("phos.input.action: too many keys (max 16)");
                return sol::nil;
            }
            for (const std::string& key : list) {
                if (!valid_input_name(key)) {
                    log::warn("phos.input.action: invalid key name");
                    return sol::nil;
                }
            }
            host.input_actions[name] = std::move(list);
        }
        // 返回当前键列表；未注册时返回 { name }，与默认映射一致
        sol::table out = lua.create_table();
        if (const std::vector<std::string>* current = action_keys_for(host, name)) {
            for (std::size_t i = 0; i < current->size(); ++i)
                out[static_cast<int>(i) + 1] = (*current)[i];
        } else {
            out[1] = name;
        }
        return sol::make_object(lua, out);
    };
    input["action_down"] = [&host](const std::string& name) {
        return host.input && action_state(*host.input, name, action_keys_for(host, name),
                                          ActionState::down);
    };
    input["action_pressed"] = [&host](const std::string& name) {
        return host.input && action_state(*host.input, name, action_keys_for(host, name),
                                          ActionState::pressed);
    };
    input["action_released"] = [&host](const std::string& name) {
        return host.input && action_state(*host.input, name, action_keys_for(host, name),
                                          ActionState::released);
    };
    // 操作提示写虚拟键在键盘上的主键名（手柄/键盘共用同一套虚拟键）
    input["key_name"] = [](const std::string& key) { return key_display_name(key); };
    // 本帧输入的文本（UTF-8；可含多字节字符与退格 '\b'）
    input["text"] = [&host]() { return host.input->text(); };
    // 已按住的秒数：长按类手感（"按住越走越快"）不必由卡带自己攒计时
    input["duration"] = [&host](const std::string& key) { return host.input->duration(key); };
    // 主机见过的所有键名（内置十颗排在最前）：写"按任意键改绑定"这类界面时遍历它
    input["keys"] = [&host, &lua]() {
        sol::table out = lua.create_table();
        int index = 1;
        for (const std::string& name : host.input->names()) out[index++] = name;
        return out;
    };

    // 本帧新按下的键（任意一个），返回虚拟键名或 nil。
    // 给"让玩家按一个键来完成绑定"用：拿到名字可以存进存档，
    // 再用 phos.input.key_name() 显示成键盘上真实的键。
    // 主机保留键（Esc / F2）不在其中——它们永远属于主机。
    input["any_pressed"] = [&host, &lua]() -> sol::object {
        const std::string name = host.input->any_pressed();
        if (name.empty()) return sol::nil;
        return sol::make_object(lua, name);
    };

    // --- phos.input.field：文本输入框缓冲 ---
    // 过滤、按码点退格、限长都交给主机的 TextInput（与磁带码输入同一套实现），
    // 卡带只管 feed() 与读 value()——"删掉一个中文字"因此不会变成半个字符。
    lua.new_usertype<CartTextField>(
        "phos.TextField", sol::no_constructor,
        "feed",
        [&host](CartTextField& self) {
            self.feed(host.time, host.input->text());
            // 声明"要收中文"的框被喂的**这一帧**，举手告诉主机打开系统输入法（见 HostContext::ime_wanted）
            if (self.ime()) host.ime_wanted = true;
        },
        "clear", &CartTextField::clear, "value", sol::property(&CartTextField::value),
        "count", sol::property(&CartTextField::count));

    input["field"] = [&lua](sol::optional<sol::table> cfg) -> CartTextField {
        std::string preset = "any";
        std::size_t max_chars = 0;
        bool ime = false;
        bool has_custom = false;
        sol::protected_function custom;
        if (cfg) {
            sol::object filter = (*cfg)["filter"];
            if (filter.is<std::string>()) {
                preset = filter.as<std::string>();
            } else if (filter.is<sol::function>()) {
                custom = filter.as<sol::protected_function>();
                has_custom = true;
            }
            sol::object limit = (*cfg)["max"];
            if (limit.is<double>() || limit.is<int>()) {
                const int requested = limit.as<int>();
                max_chars = requested > 0 ? static_cast<std::size_t>(requested) : 0;
            }
            sol::object ime_flag = (*cfg)["ime"];
            if (ime_flag.is<bool>()) ime = ime_flag.as<bool>();
        }

        text::TextInput::Filter accept = text::TextInput::accept_any;
        if (has_custom) {
            // 卡带自己给的过滤器：回调出错按"不接受"处理，绝不把输入通道带崩
            accept = [custom](char32_t cp) mutable {
                const auto result = custom(static_cast<lua_Integer>(cp));
                return result.valid() && result.get<bool>();
            };
        } else if (preset == "printable") {
            accept = text::TextInput::accept_printable;
        } else if (preset == "ascii") {
            accept = text::TextInput::accept_ascii;
        } else if (preset == "digits") {
            accept = text::TextInput::accept_digits;
        } else if (preset == "hex") {
            accept = text::TextInput::accept_hex;
        } else if (preset == "letters") {
            accept = text::TextInput::accept_letters;
        } else if (preset != "any") {
            // 写错预设名不该静默变成"全收"，那会让卡带以为过滤生效了
            log::warn("phos.input.field: unknown filter '" + preset + "', using 'any'");
        }
        return CartTextField(std::move(accept), max_chars, ime);
    };

    // --- phos.save（需 manifest 声明 save = true） ---
    sol::table save = phos.create_named("save");
    save["available"] = [&host]() { return host.save != nullptr; };
    // 值可以是文本/数字/布尔，也可以是表：连续 1..n 整数键 = 数组，其余 = 对象
    // （键转字符串），嵌套深度 ≤ 8。函数/userdata/环等存不下的值返回 false——
    // 卡带据此降级，而不是以为"已经存下了"
    save["write"] = [&host](const std::string& key, const sol::object& value) -> bool {
        if (!host.save) return false;
        json::Value stored;
        std::set<const void*> path;
        if (!save_value_from_lua(value, stored, kMaxSaveDepth, path)) return false;
        return host.save->set(key, stored);  // 落盘失败也要如实回报，卡带才好降级
    };
    // read 返回同构值：标量原类型，表按写入时的结构还原（数组 1..n、对象字符串键）
    save["read"] = [&host, &lua](const std::string& key) -> sol::object {
        if (!host.save) return sol::nil;
        auto value = host.save->get_value(key);
        if (!value) return sol::nil;
        return save_value_to_lua(lua.lua_state(), *value);
    };
    // 存档槽：0 = 默认档，1..9 = 独立槽位（同一卡带的多份进度/多存档）
    save["slot"] = [&host](int slot) -> bool {
        return host.cart && host.cart->open_save_slot(slot);
    };
    save["slot_index"] = [&host]() -> int {
        return host.cart ? host.cart->save_slot() : 0;
    };
    save["erase"] = [&host](const std::string& key) -> bool {
        return host.save && host.save->erase(key);
    };
    save["export"] = [&host]() -> std::string {
        return host.save ? host.save->export_code() : std::string();
    };
    save["import"] = [&host](const std::string& code) -> bool {
        return host.save && host.save->import_code(code);
    };

    // --- phos.sys ---
    sol::table sys = phos.create_named("sys");
    sys["time"] = [&host]() { return host.time; };
    sys["fps"] = [&host]() { return host.fps; };
    // 当前逻辑帧号："每 N 帧做一次"不必自己数（与 state.query 的 frame 同源）
    sys["frame"] = [&host]() { return host.frame; };
    sys["random"] = [&host](int lo, int hi) {
        if (lo > hi) std::swap(lo, hi);
        return std::uniform_int_distribution<int>(lo, hi)(host.rng);
    };
    sys["seed"] = [&host](unsigned n) { host.rng.seed(n); };
    // 卡带文案属于卡带内容，主机只告诉它"现在是什么语言"，怎么翻译由卡带自己决定
    sys["language"] = [&host]() { return host.language; };
    sys["log"] = [](const std::string& msg) {
        std::printf("[cart] %s\n", msg.c_str());
        log::info("[cart] " + msg);  // 卡带日志同样落盘，便于与实际帧号对齐
    };
    sys["version"] = []() { return kVersion; };
    sys["product"] = []() { return kProductName; };
    // 卡带接管 Esc：true 时主机不再把 Esc 当暂停/返回，而是作为普通键交给卡带
    // （phos.input.pressed("escape")）。默认 false（Esc 仍是主机保留键）。
    // 用途：卡带需要在某些状态下自定义 Esc 行为（例如打开自己的菜单），而非触发主机暂停
    sys["capture_escape"] = [&host](bool on) {
        if (host.capture_escape) *host.capture_escape = on;
        return on;
    };

    // --- phos.lang（多语言取值） ---
    // 文案属于卡带内容：主机不替卡带翻译，只把"取当前语言那一条"收成机制 ——
    // 否则每张卡带都要把同一套查表写法（`x[lang] or x.zh`）抄一遍。
    // 缺项一律**回落中文**（与 manifest 的 desc 同一规则），卡带不必为漏翻写防御代码
    sol::table lang = phos.create_named("lang");

    // 单条：phos.lang.pick{ zh = "普通炮弹", en = "SHELL" }
    lang["pick"] = [&host](const sol::table& fields) -> std::string {
        const char* cur = (host.language == "en") ? "en" : "zh";
        sol::object v = fields[cur];
        if (!v.is<std::string>()) v = fields["zh"];
        if (!v.is<std::string>()) v = fields["en"];
        return v.is<std::string>() ? v.as<std::string>() : std::string();
    };

    // 整张表：local Text = { zh = {...}, en = {...} }，用时 `local t = phos.lang.dict(Text)`。
    // 返回的是原表里的那一张（引用，不拷贝），所以**每帧取一次**就能跟着设置里的
    // 语言切换即时变，卡带不必自己缓存或刷新
    lang["dict"] = [&host, &lua](sol::table fields) -> sol::table {
        const char* cur = (host.language == "en") ? "en" : "zh";
        sol::table dict = fields[cur];
        if (!dict.valid()) dict = fields["zh"];
        if (!dict.valid()) dict = fields["en"];
        return dict.valid() ? dict : lua.create_table();  // 两列都没写：给空表，别让卡带崩
    };

    // 共享词表：SCORE / BEST / PAUSED 这类每张卡带都会用到的词，取当前语言那一列。
    // 卡带可在 init 里拷一份再覆盖自己的词；每帧重取会产生垃圾表，文档建议按需刷新
    lang["shared"] = [&host, &lua]() {
        const bool en = host.language == "en";
        sol::table out = lua.create_table();
        const auto put = [&](const char* key, const char* zh, const char* en_word) {
            out[key] = en ? en_word : zh;
        };
        put("score", "得分", "SCORE");
        put("best", "最高", "BEST");
        put("level", "关卡", "LEVEL");
        put("lives", "生命", "LIVES");
        put("time", "时间", "TIME");
        put("paused", "暂停", "PAUSED");
        put("resume", "继续", "RESUME");
        put("restart", "重来", "RESTART");
        put("quit", "退出", "QUIT");
        put("start", "开始", "START");
        put("back", "返回", "BACK");
        put("help", "帮助", "HELP");
        put("confirm", "确认", "CONFIRM");
        put("cancel", "取消", "CANCEL");
        put("on", "开", "ON");
        put("off", "关", "OFF");
        put("keys", "操作", "KEYS");
        put("select", "选择", "SELECT");
        return out;
    };

    // --- phos.observe：给 agent 的声明式观测表 ---
    // 每个字段可以是值，也可以是函数（每次 state.query 时求值）；比手写 debug_state
    // 少一份"快照会过期"的维护。老写法 debug_state() 仍优先，两者可共存一个迁移周期
    phos["observe"] = [&host](sol::table spec) {
        if (host.cart) host.cart->set_observe(spec);
    };

    // --- phos.cart：卡带自己的身份（来自 manifest.lua） ---
    // 有了它，卡带不必把标题之类的身份再抄一份到 Lua 里：作者在 manifest.lua 改
    // `name`，标题画面与关于页立刻跟着变。取一次存起来即可，别每帧调用
    sol::table cart = phos.create_named("cart");
    cart["info"] = [&host, &lua]() {
        sol::table out = lua.create_table();
        const CartInfo* info = host.cart_info;  // 未插卡（主机脚本）时为空
        out["id"] = info ? info->id : std::string();
        out["name"] = info ? info->name.get(host.language == "en") : std::string();
        out["version"] = info ? info->version : std::string();
        out["author"] = info ? info->author : std::string();
        // 简介是身份里唯一需要本地化的字段：按当前界面语言取（英文缺失时回落中文）
        out["desc"] = info ? info->desc.get(host.language == "en") : std::string();
        return out;
    };

    // 组件层（边框/浮窗/菜单/进度条/正文/精灵/导航/绘制区域）
    register_scene_api(lua, host);
    register_score_api(lua, host);
    register_ui_api(lua, host);
    // 音频层（合成音/音符/打击乐/音序器音乐/采样）
    register_audio_api(lua, host);
    // 资源层（包内文本/按行/存在性/大小/列表）
    register_assets_api(lua, host);
    // 图层（可选的新能力：不建层的卡带完全不受影响）
    register_layer_api(lua, host);
    // 局域网联机（默认休眠：卡带不调 host/join 就完全不占端口、不起线程）
    register_net_api(lua, host);
}

HostCartBinding::HostCartBinding(HostContext& host, std::unique_ptr<Cartridge> cart,
                                 std::function<void()> on_release)
    : host_(host), cart_(std::move(cart)), on_release_(std::move(on_release)) {
    host_.input_actions.clear();  // 动作表属于脚本会话：新会话从空表开始
    install_host_entries();
}

HostCartBinding::~HostCartBinding() {
    // 顺序是有意的：先清 HostContext，再销毁卡带。卡带析构（Lua state / 场景栈 / UI 态）
    // 期间不会再有人从 HostContext 拿到它
    if (on_release_) on_release_();
    host_.input_actions.clear();  // 动作表属于脚本会话，随会话结束清空
    cart_.reset();
}

void HostCartBinding::install_host_entries() {
    if (!cart_) return;
    // cart_files 只在 Cartridge::assemble 里装（那时才打开包）；这里装不依赖 Lua 装配的入口
    host_.cart = cart_.get();
    host_.cart_info = &cart_->info();
    host_.save = cart_->save();
    host_.scenes = &cart_->scenes();
}

void HostCartBinding::detach_host_entries() {
    host_.cart = nullptr;
    host_.cart_info = nullptr;
    host_.cart_files = nullptr;
    host_.save = nullptr;
    host_.scenes = nullptr;
}

void HostCartBinding::replace_cart(std::unique_ptr<Cartridge> cart) {
    detach_host_entries();     // HostContext 先不再指向旧脚本
    host_.input_actions.clear();  // 旧脚本的动作表不能跨重载/换卡存活
    cart_ = std::move(cart);   // 旧脚本在此销毁
    install_host_entries();    // 新脚本就位（assemble 还会写 cart_files 等）
}

} // namespace phos
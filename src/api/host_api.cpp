#include "api/host_api.hpp"

#include "api/text_field.hpp"

#include "api/assets_api.hpp"
#include "api/audio_api.hpp"
#include "api/layer_api.hpp"
#include "api/lua_value.hpp"
#include "api/net_api.hpp"
#include "api/ui_api.hpp"
#include "cart/cartridge.hpp"
#include "core/log.hpp"
#include "core/surface.hpp"
#include "core/text.hpp"
#include "core/version.hpp"

#include <sol/sol.hpp>

#include <cstdio>

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

// 默认取色 helper 在 lua_value 里（区域绑定也用同一份），这里只是引入名字
using api::default_bg;
using api::default_fg;

/// 篮子文案 → Localized：字符串（中英同文）或 `{ zh = …, en = … }` 表。
/// 控制台按当前界面语言取一份，于是切换语言时篮子文案跟着变
Localized read_label(const sol::object& object) {
    Localized out;
    if (object.is<std::string>()) {
        out.zh = out.en = object.as<std::string>();
    } else if (object.is<sol::table>()) {
        const sol::table t = object.as<sol::table>();
        const sol::object zh = t["zh"];
        const sol::object en = t["en"];
        if (zh.is<std::string>()) out.zh = zh.as<std::string>();
        if (en.is<std::string>()) out.en = en.as<std::string>();
        if (out.zh.empty()) out.zh = out.en;  // 只写一种也不至于空着
        if (out.en.empty()) out.en = out.zh;
    }
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
                                 sol::object bg) {
        Surface s = is_panel ? panel_surface(host) : content_surface(host);
        s.put(x, y, api::read_char(ch, U' '), api::read_color(fg, default_fg(host)),
              api::read_background(bg));
    };
    t["print"] = [&host, is_panel](int x, int y, const std::string& text, sol::object fg,
                                   sol::object bg) {
        Surface s = is_panel ? panel_surface(host) : content_surface(host);
        s.print(x, y, text, api::read_color(fg, default_fg(host)), api::read_background(bg));
    };
    // fill / clear：省略底色 = 本面的默认底色（screen=色板 black；panel=主题面板色）。
    // 清屏若按"保留背景"来就变成什么都不做
    t["fill"] = [&host, is_panel](int x, int y, int w, int h, const sol::object& ch, sol::object fg,
                                  sol::object bg) {
        Surface s = is_panel ? panel_surface(host) : content_surface(host);
        s.fill(x, y, w, h, api::read_char(ch, U' '), api::read_color(fg, default_fg(host)),
               api::read_color(bg, is_panel ? host.panel_bg : default_bg(host)));
    };
    t["clear"] = [&host, is_panel](sol::object fg, sol::object bg) {
        (is_panel ? panel_surface(host) : content_surface(host))
            .clear(api::read_color(fg, default_fg(host)),
                   api::read_color(bg, is_panel ? host.panel_bg : default_bg(host)));
    };
    // blit / back / back_rect：省略底色 = 激活色板的 black（与 screen 同组，不随面板色）——
    // 这族是"整块搬运 / 只改一块底色"，默认与内容区一致
    t["blit"] = [&host, is_panel](int x, int y, sol::object rows, sol::object fg, sol::object bg) {
        (is_panel ? panel_surface(host) : content_surface(host))
            .blit(x, y, api::read_rows(rows), api::read_color(fg, default_fg(host)),
                  api::read_color(bg, default_bg(host)));
    };
    // 叠一笔 / 只改底色 / 落半格：前两件与 put 同组（底色省略 = 保留），第三件没有底色参数
    t["blend"] = [&host, is_panel](int x, int y, sol::object ch, sol::object fg) {
        return (is_panel ? panel_surface(host) : content_surface(host))
            .blend(x, y, api::read_char(ch, U' '), api::read_color(fg, default_fg(host)));
    };
    t["back"] = [&host, is_panel](int x, int y, sol::object bg) {
        (is_panel ? panel_surface(host) : content_surface(host))
            .back(x, y, api::read_color(bg, default_bg(host)));
    };
    t["back_rect"] = [&host, is_panel](int x, int y, int w, int h, sol::object bg) {
        (is_panel ? panel_surface(host) : content_surface(host))
            .back_rect(x, y, w, h, api::read_color(bg, default_bg(host)));
    };
    t["plot"] = [&host, is_panel](int x, int y, sol::object fg) {
        (is_panel ? panel_surface(host) : content_surface(host))
            .plot(x, y, api::read_color(fg, default_fg(host)));
    };
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
    // 卡带注册"一个数值 + 怎么读 get + 怎么写 set + 范围"，调试台据此画滑条。
    // 注册随卡带生命周期；未挂卡带（无卡 / 宿主动画脚本）时安全无效
    sol::table debug = phos.create_named("debug");
    debug["number"] = [&host](sol::object name, sol::protected_function get,
                              sol::protected_function set, sol::optional<sol::table> opts) {
        if (!host.cart) return;
        float min = 0.0f, max = 1.0f, step = 0.01f;
        std::vector<Localized> group;
        if (opts) {
            const sol::table t = *opts;
            min = static_cast<float>(api::read_number(t, "min", min));
            max = static_cast<float>(api::read_number(t, "max", max));
            step = static_cast<float>(api::read_number(t, "step", step));
            group = read_group_path(t["group"]);
        }
        host.cart->debug_register(read_label(name), std::move(group), std::move(get),
                                  std::move(set), min, max, step);
    };

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
        const GlyphBox box = host.glyph_metrics ? host.glyph_metrics(cp) : GlyphBox{0, kCellPx, true};
        return std::make_tuple(box.xoff, box.width, box.approx);
    };

    // --- phos.input ---
    sol::table input = phos.create_named("input");
    // 键就是名字：主机不做白名单，任何名字都能查（没见过 = 一直是松开）。
    // 卡带因此可以要多少键就多少键，也能读存档里的绑定名直接查状态
    input["down"] = [&host](const std::string& key) { return host.input->down(key); };
    input["pressed"] = [&host](const std::string& key) { return host.input->pressed(key); };
    input["released"] = [&host](const std::string& key) { return host.input->released(key); };
    // 操作提示应该写键盘上的键，而不是手柄按钮名——主机没有手柄
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
        "feed", [&host](CartTextField& self) { self.feed(host.time, host.input->text()); },
        "clear", &CartTextField::clear, "value", sol::property(&CartTextField::value),
        "count", sol::property(&CartTextField::count));

    input["field"] = [&lua](sol::optional<sol::table> cfg) -> CartTextField {
        std::string preset = "any";
        std::size_t max_chars = 0;
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
        return CartTextField(std::move(accept), max_chars);
    };

    // --- phos.save（需 manifest 声明 save = true） ---
    sol::table save = phos.create_named("save");
    save["available"] = [&host]() { return host.save != nullptr; };
    save["write"] = [&host](const std::string& key, const std::string& value) -> bool {
        if (!host.save) return false;
        return host.save->set(key, value);  // 落盘失败也要如实回报，卡带才好降级
    };
    save["read"] = [&host, &lua](const std::string& key) -> sol::object {
        if (!host.save) return sol::nil;
        auto v = host.save->get(key);
        if (!v) return sol::nil;
        return sol::make_object(lua.lua_state(), *v);
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

    // --- phos.cart：卡带自己的身份（来自 manifest.lua） ---
    // 有了它，卡带不必把标题之类的身份再抄一份到 Lua 里：作者在 manifest.lua 改
    // `name`，标题画面与关于页立刻跟着变。取一次存起来即可，别每帧调用
    sol::table cart = phos.create_named("cart");
    cart["info"] = [&host, &lua]() {
        sol::table out = lua.create_table();
        const CartInfo* info = host.cart_info;  // 未插卡（主机脚本）时为空
        out["id"] = info ? info->id : std::string();
        out["name"] = info ? info->name : std::string();
        out["version"] = info ? info->version : std::string();
        out["author"] = info ? info->author : std::string();
        // 简介是身份里唯一需要本地化的字段：按当前界面语言取（英文缺失时回落中文）
        out["desc"] = info ? info->desc.get(host.language == "en") : std::string();
        return out;
    };

    // 组件层（边框/浮窗/菜单/进度条/正文/精灵/导航/绘制区域）
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

} // namespace phos

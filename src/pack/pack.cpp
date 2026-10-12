#include "pack/pack.hpp"

#include "api/lua_value.hpp"
#include "core/defaults.hpp"
#include "core/log.hpp"
#include "core/text.hpp"

#include <sol/sol.hpp>

#include <algorithm>
#include <filesystem>

namespace phos {

namespace {

/// 包脚本路径解析：`mods/<包id>/<文件名>` 存在则优先（覆盖层 Mod，见 content-packs.md）。
/// 覆盖层只替换脚本正文，包的身份与列表仍由文件夹决定。
std::string pack_script_path(const std::string& dir, const char* filename) {
    namespace fs = std::filesystem;
    std::error_code ec;
    const std::string id = fs::path(dir).filename().string();
    fs::path mod = fs::path("mods") / id / filename;
    if (!id.empty() && fs::is_regular_file(mod, ec)) return mod.generic_string();
    return (fs::path(dir) / filename).string();
}

/// 包脚本沙箱：最小可用的标准库 + `phos.text`（排版助手）。
/// 皮肤用 `phos.text.width` 做"按显示宽度"的排版（中文一字占 2 列，
/// 按字节补齐会错位）。沙箱里没有它，包脚本一调用就整包加载失败——
/// 表现为"主题从列表里消失、无法切换"。
void open_pack_api(sol::state& lua) {
    lua.open_libraries(sol::lib::base, sol::lib::string, sol::lib::table, sol::lib::math);
    sol::table phos = lua.create_named_table("phos");
    sol::table text = phos.create_named("text");
    text["width"] = [](const std::string& s) { return text::display_width(s); };
    text["truncate"] = [](const std::string& s, int cols) { return text::truncate(s, cols); };
}

} // namespace

bool load_palette(const std::string& dir, Palette& out, std::string& err) {
    namespace fs = std::filesystem;
    std::error_code ec;

    // 显示名一律取文件夹名（唯一权威，见 content-packs.md）：
    // 用户在文件管理器里看到的文件夹 = 设置里选到的名字，不会有第二套命名
    std::string id = fs::path(dir).filename().string();
    std::string name = id;

    const std::string palette_path = pack_script_path(dir, "palette.lua");
    if (!fs::is_regular_file(palette_path, ec)) {
        err = "palette pack missing palette.lua: " + dir;
        return false;
    }

    sol::state lua;
    open_pack_api(lua);
    auto r = lua.safe_script_file(palette_path, &sol::script_pass_on_error);
    if (!r.valid() || !r.get<sol::object>().is<sol::table>()) {
        err = "palette.lua must return a table: " + dir;
        if (!r.valid()) err += " | " + std::string(sol::error(r).what());
        return false;
    }
    sol::table t = r.get<sol::object>().as<sol::table>();

    out = builtin_palette();  // 未声明的槽位/参数回退默认
    out.id = std::move(id);
    out.name = std::move(name);

    sol::object colors = t["colors"];
    if (colors.is<sol::table>()) {
        sol::table ct = colors.as<sol::table>();
        for (size_t i = 0; i < kPaletteSlots; ++i)
            out.slots[i] = api::read_color(ct[palette_slot_name(static_cast<PaletteSlot>(i))],
                                      out.slots[i]);
    }
    sol::object scan = t["scan"];
    if (scan.is<double>() || scan.is<int>()) {
        float s = scan.as<float>();
        out.scan_strength = s < 0.0f ? 0.0f : (s > 1.0f ? 1.0f : s);
    }
    out.tint = api::read_color(t["tint"], out.tint);
    return true;
}

bool load_skin(const std::string& dir, Skin& out, std::string& err) {
    namespace fs = std::filesystem;
    std::error_code ec;

    // 显示名一律取文件夹名（同 palette，见 content-packs.md）
    std::string id = fs::path(dir).filename().string();
    std::string name = id;

    const std::string skin_path = pack_script_path(dir, "skin.lua");
    if (!fs::is_regular_file(skin_path, ec)) {
        err = "skin pack missing skin.lua: " + dir;
        return false;
    }

    sol::state lua;
    open_pack_api(lua);
    auto r = lua.safe_script_file(skin_path, &sol::script_pass_on_error);
    if (!r.valid() || !r.get<sol::object>().is<sol::table>()) {
        // 必须带上 Lua 的报错原文：只说"must return a table"会把真正的原因
        // （脚本里某个函数不存在）藏起来，排查时只能靠猜
        err = "skin.lua must return a table: " + dir;
        if (!r.valid()) err += " | " + std::string(sol::error(r).what());
        return false;
    }
    sol::table t = r.get<sol::object>().as<sol::table>();

    out = builtin_skin();
    out.id = std::move(id);
    out.name = std::move(name);

    auto read_str = [&t](const char* key, const std::string& fallback) {
        sol::object v = t[key];
        return v.is<std::string>() ? v.as<std::string>() : fallback;
    };

    sol::object screen = t["screen"];
    if (screen.is<sol::table>()) {
        sol::table st = screen.as<sol::table>();
        auto num = [&st](const char* key, int fallback) {
            sol::object v = st[key];
            if (v.is<double>() || v.is<int>()) return v.as<int>();
            return fallback;
        };
        // 内容区偏移是"机身留白"，负数没有意义：它会让 grid_w/grid_h 变成非正数，
        // Screen::resize 再拿它去分配（负 width 转 size_t 是天量）——坏主题包不该
        // 把主机撑爆，钳到 >= 0
        const int sx = num("x", out.screen_x);
        const int sy = num("y", out.screen_y);
        out.screen_x = sx < 0 ? 0 : sx;
        out.screen_y = sy < 0 ? 0 : sy;
        // 内容区尺寸由主机规定（当前世代所有皮肤共享同一内容区），
        // 所以 w/h 不是可覆盖项，读它只会误导维护者
        out.screen_w = kContentW;
        out.screen_h = kContentH;
    }
    auto top = api::read_rows(t["top"]);
    auto bottom = api::read_rows(t["bottom"]);
    if (!top.empty()) out.top = std::move(top);
    if (!bottom.empty()) out.bottom = std::move(bottom);
    out.left = read_str("left", out.left);
    out.right = read_str("right", out.right);
    out.palette = read_str("palette", out.palette);  // 主题使用的内容色板（theme/palette/<名>）

    sol::object colors = t["colors"];
    if (colors.is<sol::table>()) {
        sol::table ct = colors.as<sol::table>();
        out.frame = api::read_color(ct["frame"], out.frame);
        out.accent = api::read_color(ct["accent"], out.accent);
        out.ui_fg = api::read_color(ct["ui_fg"], out.ui_fg);
        out.ui_bg = api::read_color(ct["ui_bg"], out.ui_bg);
        out.ui_dim = api::read_color(ct["ui_dim"], out.ui_dim);
        // 面板底色缺省 = 机身色（不区分）；想给侧栏层次感就显式给一个略深/略浅的色
        out.panel = api::read_color(ct["panel"], out.ui_bg);
    }

    sol::object lamps = t["lamps"];
    if (lamps.is<sol::table>()) {
        sol::table lt = lamps.as<sol::table>();
        out.lamps.clear();
        for (size_t i = 1; i <= lt.size(); ++i) {
            sol::object item = lt[i];
            if (!item.is<sol::table>()) continue;
            sol::table e = item.as<sol::table>();
            Skin::Lamp lamp;
            sol::object lx = e["x"], ly = e["y"];
            if (lx.is<double>() || lx.is<int>()) lamp.x = lx.as<int>();
            if (ly.is<double>() || ly.is<int>()) lamp.y = ly.as<int>();
            lamp.color = api::read_color(e["color"], lamp.color);
            sol::object period = e["period"];
            if (period.is<double>() || period.is<int>()) {
                float p = period.as<float>();
                lamp.period = p < 0.2f ? 0.2f : p;
            }
            out.lamps.push_back(lamp);
        }
    }
    return true;
}

namespace {

/// 扫描 `dir` 下的内容包目录：每个子目录交给 loader，装载失败则跳过。
///
/// 四个 scan_* 共用这一套骨架。目录不存在 = 空列表（不是错误）；
/// 目录遍历顺序由文件系统决定，所以统一排成"default 在前、其余按 id"，
/// 让设置界面的列表顺序跨机器一致（同一台机器上也不会时好时坏）。
template <typename T, typename Loader>
std::vector<T> scan_pack_dirs(const std::string& dir, Loader loader) {
    namespace fs = std::filesystem;
    std::vector<T> out;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) return out;
    for (const auto& entry : fs::directory_iterator(dir, ec)) {
        if (!entry.is_directory(ec)) continue;
        T pack;
        if (loader(entry.path(), pack)) out.push_back(std::move(pack));
    }
    // 出厂包（"default"）排最前，其余按 id 字典序。
    // 比较器必须是**严格弱序**：等价的元素两边都得返回 false，否则 sort 行为未定义
    std::sort(out.begin(), out.end(), [](const T& a, const T& b) {
        if ((a.id == "default") != (b.id == "default")) return a.id == "default";
        return a.id < b.id;
    });
    return out;
}

} // namespace

std::vector<Skin> scan_skins(const std::string& dir) {
    return scan_pack_dirs<Skin>(dir, [](const std::filesystem::path& path, Skin& out) {
        std::string err;
        if (load_skin(path.string(), out, err)) return true;
        log::warn("skin pack skipped: " + err);  // 回退到默认，但必须留下痕迹
        return false;
    });
}

std::vector<BootPack> scan_boots(const std::string& dir) {
    return scan_pack_dirs<BootPack>(dir, [](const std::filesystem::path& path, BootPack& out) {
        namespace fs = std::filesystem;
        std::error_code ec;
        if (!fs::is_regular_file(path / "main.lua", ec)) {
            // 内容目录里出现"没有入口脚本的文件夹"通常是包写坏了：
            // 与皮肤/色板一样留痕，否则用户只会看到"开机动画没了"
            log::warn("boot pack skipped (no main.lua): " + path.string());
            return false;
        }
        out.id = path.filename().string();
        out.name = out.id;  // 显示名 = 文件夹名
        out.dir = path.string();
        return true;
    });
}

std::vector<SoundPack> scan_sounds(const std::string& dir) {
    return scan_pack_dirs<SoundPack>(dir, [](const std::filesystem::path& path, SoundPack& out) {
        namespace fs = std::filesystem;
        std::error_code ec;
        const std::string sounds_path = pack_script_path(path.string(), "sounds.lua");
        if (!fs::is_regular_file(sounds_path, ec)) {
            // 与皮肤/色板、开机动画一致：包写坏了要留痕，不能静默少一个音效包
            log::warn("sound pack skipped (no sounds.lua): " + path.string());
            return false;
        }
        out.id = path.filename().string();
        out.name = out.id;  // 显示名 = 文件夹名
        out.dir = path.string();

        sol::state lua;
        open_pack_api(lua);
        const auto script = lua.safe_script_file(sounds_path, &sol::script_pass_on_error);
        if (!script.valid() || !script.get<sol::object>().is<sol::table>()) {
            log::warn("sound pack skipped: " + out.dir);
            return false;
        }
        sol::table events = script.get<sol::object>().as<sol::table>();

        for (auto& kv : events) {
            if (!kv.first.is<std::string>() || !kv.second.is<sol::table>()) continue;
            const std::string event = kv.first.as<std::string>();
            sol::table spec = kv.second.as<sol::table>();

            sol::object file = spec["file"];
            if (file.is<std::string>()) {
                out.files[event] = file.as<std::string>();
                continue;
            }

            ToneSpec tone;
            sol::object wave = spec["wave"];
            if (wave.is<std::string>()) tone.wave = wave_from_name(wave.as<std::string>());
            sol::object perc = spec["perc"];
            if (perc.is<std::string>() && !perc.as<std::string>().empty())
                percussion_spec(perc.as<std::string>()[0], tone);

            auto number = [&spec](const char* key, float fallback) {
                sol::object v = spec[key];
                if (v.is<double>() || v.is<int>()) return v.as<float>();
                return fallback;
            };
            tone.freq = number("freq", tone.freq);
            tone.freq_end = number("sweep", tone.freq_end);
            tone.dur = number("dur", tone.dur);
            tone.volume = number("volume", tone.volume);
            out.tones[event] = tone;
        }
        return true;
    });
}

std::vector<Palette> scan_palettes(const std::string& dir) {
    return scan_pack_dirs<Palette>(dir, [](const std::filesystem::path& path, Palette& out) {
        std::string err;
        if (load_palette(path.string(), out, err)) return true;
        // 回退机制保证总有默认可用，但损坏原因必须留痕，否则用户只会看到"色板没了"
        log::warn("palette pack skipped: " + err);
        return false;
    });
}

} // namespace phos

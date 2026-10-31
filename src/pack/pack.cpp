#include "pack/pack.hpp"

#include "api/lua_guard.hpp"
#include "api/lua_sandbox.hpp"
#include "api/lua_value.hpp"
#include "core/defaults.hpp"
#include "core/font_files.hpp"
#include "core/log.hpp"
#include "core/mods.hpp"
#include "core/text.hpp"

#include <sol/sol.hpp>

#include <algorithm>
#include <cmath>
#include <filesystem>

namespace phos {

namespace {

/// 包脚本路径解析：被任意 mod 覆盖则用覆盖版（见 pack/mods.hpp）。
/// 覆盖层只替换脚本正文，包的身份与列表仍由文件夹决定。
std::string pack_script_path(const std::string& dir, const char* filename) {
    namespace fs = std::filesystem;
    const std::string id = fs::path(dir).filename().string();
    const std::string over = mod_override(id, filename);
    if (!over.empty()) return over;
    return (fs::path(dir) / filename).string();
}

/// 包脚本沙箱：最小可用的标准库 + `phos.text`（排版助手）。
/// 皮肤用 `phos.text.width` 做"按显示宽度"的排版（中文一字占 2 列，
/// 按字节补齐会错位）。沙箱里没有它，包脚本一调用就整包加载失败——
/// 表现为"主题从列表里消失、无法切换"。
void open_pack_api(sol::state& lua) {
    // 沙箱底线（库白名单、摘文件/加载函数、看门狗、print 汇入日志）与卡带共用；
    // phos.text 是内容包的业务面，留在本模块
    lua_sandbox::open(lua, {sol::lib::base, sol::lib::string, sol::lib::table, sol::lib::math},
                      "pack");
    sol::table phos = lua.create_named_table("phos");
    sol::table text = phos.create_named("text");
    text["width"] = [](const std::string& s) { return text::display_width(s); };
    text["truncate"] = [](const std::string& s, int cols) { return text::truncate(s, cols); };
}

} // namespace

bool load_palette(const std::string& dir, Palette& out, std::string& err,
                  std::vector<std::string>* warnings) {
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
    lua_guard::BudgetScope budget;
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

    // warnings 只给 DevKit 的 --check-packs 用：类型不对的声明会被下面的回退吞掉，
    // 运行期静默是对的，但校验工具必须把它列出来
    const auto warn = [warnings](std::string message) {
        if (warnings) warnings->push_back(std::move(message));
    };
    sol::object colors = t["colors"];
    if (colors.is<sol::table>()) {
        sol::table ct = colors.as<sol::table>();
        for (size_t i = 0; i < kPaletteSlots; ++i)
            out.slots[i] = api::read_color(ct[palette_slot_name(static_cast<PaletteSlot>(i))],
                                      out.slots[i]);
    } else if (colors.get_type() != sol::type::nil) {
        warn("colors must be a table (falling back to built-in slots)");
    }
    sol::object scan = t["scan"];
    if (scan.is<double>() || scan.is<int>()) {
        float s = scan.as<float>();
        if (s < 0.0f || s > 1.0f) warn("scan outside 0..1 (clamped)");
        out.scan_strength = s < 0.0f ? 0.0f : (s > 1.0f ? 1.0f : s);
    } else if (scan.get_type() != sol::type::nil) {
        warn("scan must be a number");
    }
    sol::object tint = t["tint"];
    if (tint.get_type() != sol::type::nil && !tint.is<Color>() && !tint.is<sol::table>())
        warn("tint must be a Color or {r,g,b} table");
    out.tint = api::read_color(tint, out.tint);
    return true;
}

bool load_skin(const std::string& dir, Skin& out, std::string& err,
               std::vector<std::string>* warnings) {
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
    lua_guard::BudgetScope budget;
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

    // warnings 只给 --check-packs：类型不对的声明会被回退吞掉（运行期静默是对的）
    const auto warn = [warnings](std::string message) {
        if (warnings) warnings->push_back(std::move(message));
    };
    // ui 覆盖是新增的软字段：坏值回退默认，但运行期也要留一条日志（不只 --check-packs）
    const auto warn_ui = [warnings](std::string message) {
        if (warnings)
            warnings->push_back(message);
        else
            log::warn("skin ui: " + message);
    };
    const auto read_str = [&t, &warn](const char* key, const std::string& fallback) {
        sol::object v = t[key];
        if (v.get_type() != sol::type::nil && !v.is<std::string>())
            warn(std::string(key) + " must be a string");
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
    } else if (screen.get_type() != sol::type::nil) {
        warn("screen must be a table");
    }
    const sol::object top_raw = t["top"];
    const sol::object bottom_raw = t["bottom"];
    if (top_raw.get_type() != sol::type::nil && !top_raw.is<sol::table>())
        warn("top must be a table of strings");
    if (bottom_raw.get_type() != sol::type::nil && !bottom_raw.is<sol::table>())
        warn("bottom must be a table of strings");
    auto top = api::read_rows(top_raw);
    auto bottom = api::read_rows(bottom_raw);
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
    } else if (colors.get_type() != sol::type::nil) {
        warn("colors must be a table");
    }

    sol::object lamps = t["lamps"];
    if (lamps.is<sol::table>()) {
        sol::table lt = lamps.as<sol::table>();
        out.lamps.clear();
        for (size_t i = 1; i <= lt.size(); ++i) {
            sol::object item = lt[i];
            if (!item.is<sol::table>()) {
                warn("lamps[" + std::to_string(i) + "] must be a table");
                continue;
            }
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
    } else if (lamps.get_type() != sol::type::nil) {
        warn("lamps must be a table");
    }

    // 可选 ui 表：只收字形与度量 token（颜色仍走 colors）。所有坏值都回退默认并 warning。
    sol::object ui = t["ui"];
    if (ui.is<sol::table>()) {
        sol::table ut = ui.as<sol::table>();

        auto read_glyph = [&](const char* key, std::optional<char32_t>& slot) {
            sol::object v = ut["glyphs"][key];
            if (v.get_type() == sol::type::nil) return;
            if (!v.is<std::string>()) {
                warn_ui(std::string("ui.glyphs.") + key + " must be a one-character string");
                return;
            }
            char32_t codepoint = 0;
            if (!skin_ui_glyph(v.as<std::string>(), codepoint)) {
                warn_ui(std::string("ui.glyphs.") + key +
                        " must be exactly one non-control character");
                return;
            }
            slot = codepoint;
        };

        sol::object glyphs = ut["glyphs"];
        if (glyphs.is<sol::table>()) {
            read_glyph("h", out.ui.glyphs.h);
            read_glyph("v", out.ui.glyphs.v);
            read_glyph("tl", out.ui.glyphs.tl);
            read_glyph("tr", out.ui.glyphs.tr);
            read_glyph("bl", out.ui.glyphs.bl);
            read_glyph("br", out.ui.glyphs.br);
            read_glyph("cursor", out.ui.glyphs.cursor);
            read_glyph("bullet", out.ui.glyphs.bullet);
            read_glyph("scroll_thumb", out.ui.glyphs.scroll_thumb);
            read_glyph("scroll_track", out.ui.glyphs.scroll_track);
            read_glyph("table_rule", out.ui.glyphs.table_rule);
        } else if (glyphs.get_type() != sol::type::nil) {
            warn_ui("ui.glyphs must be a table");
        }

        auto read_metric = [&](const char* key, std::optional<int>& slot, int min_value,
                               int max_value) {
            sol::object v = ut["metrics"][key];
            if (v.get_type() == sol::type::nil) return;
            if (!v.is<double>() && !v.is<int>()) {
                warn_ui(std::string("ui.metrics.") + key + " must be an integer");
                return;
            }
            const double raw = v.is<int>() ? static_cast<double>(v.as<int>()) : v.as<double>();
            // 先按 double 判范围再转 int：超大 double 直接 static_cast<int> 是 UB
            if (!std::isfinite(raw) || raw != std::floor(raw) || raw < min_value ||
                raw > max_value) {
                warn_ui(std::string("ui.metrics.") + key + " out of range " +
                        std::to_string(min_value) + ".." + std::to_string(max_value));
                return;
            }
            slot = static_cast<int>(raw);
        };

        sol::object metrics = ut["metrics"];
        if (metrics.is<sol::table>()) {
            read_metric("pad_x", out.ui.metrics.pad_x, 0, kSkinUiSpacingMax);
            read_metric("pad_y", out.ui.metrics.pad_y, 0, kSkinUiSpacingMax);
            read_metric("gap", out.ui.metrics.gap, 0, kSkinUiSpacingMax);
            read_metric("label_w", out.ui.metrics.label_w, 1, kSkinUiLabelMax);
            read_metric("indent", out.ui.metrics.indent, 0, kSkinUiSpacingMax);
            read_metric("repeat_delay", out.ui.metrics.repeat_delay, 1, kSkinUiRepeatDelayMax);
            read_metric("repeat_interval", out.ui.metrics.repeat_interval, 1,
                        kSkinUiRepeatEveryMax);
        } else if (metrics.get_type() != sol::type::nil) {
            warn_ui("ui.metrics must be a table");
        }
    } else if (ui.get_type() != sol::type::nil) {
        warn_ui("ui must be a table");
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

bool load_boot(const std::string& dir, BootPack& out, std::string& err) {
    namespace fs = std::filesystem;
    std::error_code ec;
    if (!fs::is_regular_file(fs::path(dir) / "main.lua", ec)) {
        err = "boot pack missing main.lua: " + dir;
        return false;
    }
    out.id = fs::path(dir).filename().string();
    out.name = out.id;  // 显示名 = 文件夹名
    out.dir = dir;
    return true;
}

std::vector<BootPack> scan_boots(const std::string& dir) {
    return scan_pack_dirs<BootPack>(dir, [](const std::filesystem::path& path, BootPack& out) {
        std::string err;
        if (load_boot(path.string(), out, err)) return true;
        // 内容目录里出现"没有入口脚本的文件夹"通常是包写坏了：
        // 与皮肤/色板一样留痕，否则用户只会看到"开机动画没了"
        log::warn(err);
        return false;
    });
}

bool load_shelf_pack(const std::string& dir, ShelfPack& out, std::string& err,
                     std::vector<std::string>* warnings) {
    namespace fs = std::filesystem;
    std::error_code ec;
    const auto warn = [warnings](std::string message) {
        if (warnings) warnings->push_back(std::move(message));
    };
    // 主脚本固定为 shelf.lua（与 boot 的 main.lua 同一约定：入口名写死，不看目录内容猜）
    const std::string shelf_path = pack_script_path(dir, "shelf.lua");
    if (!fs::is_regular_file(shelf_path, ec)) {
        err = "shelf pack missing shelf.lua: " + dir;
        return false;
    }
    out.id = fs::path(dir).filename().string();
    out.name = out.id;  // 显示名回退 = 文件夹名
    out.dir = dir;

    // 读顶层声明（name / cols）。**只为读这两个值**跑一次脚本：与 skin/palette 的
    // pack 扫描同一成本量级（包很少）。脚本坏掉、或顶层就撞空 API（如直接调
    // phos.screen）都只是**读不到声明**——静默回落文件夹名/无列数，绝不因此不列出这个包
    sol::state lua;
    open_pack_api(lua);
    lua_guard::BudgetScope budget;
    auto r = lua.safe_script_file(shelf_path, &sol::script_pass_on_error);
    if (!r.valid()) {
        warn("shelf pack declarations unreadable (using folder name): " + out.dir);
        return true;  // 包仍在列表里（设置可见、可选中），只是用回退值
    }
    // 顶层 name 与 manifest 的本地化读法同一套（字符串 = 中英同文）
    const sol::object declared = lua["name"];
    if (declared.get_type() != sol::type::nil && !declared.is<std::string>() &&
        !declared.is<sol::table>())
        warn("name must be a string or { zh = ..., en = ... } table");
    const lua_sandbox::Localized label = lua_sandbox::read_localized(declared);
    out.name_zh = label.zh;
    out.name_en = label.en;
    sol::object cols = lua["cols"];
    if (cols.is<double>() || cols.is<int>()) {
        const int value = cols.as<int>();
        out.cols = value > 0 ? value : 0;  // 负数/0 = 未声明，主机按一维处理
    } else if (cols.get_type() != sol::type::nil) {
        warn("cols must be a positive number");
    }
    return true;
}

std::vector<ShelfPack> scan_shelves(const std::string& dir) {
    return scan_pack_dirs<ShelfPack>(dir, [](const std::filesystem::path& path, ShelfPack& out) {
        std::string err;
        std::vector<std::string> warnings;
        if (load_shelf_pack(path.string(), out, err, &warnings)) {
            for (const std::string& warning : warnings) log::warn(warning);
            return true;
        }
        log::warn(err);
        return false;
    });
}

ModScan scan_mods() {
    namespace fs = std::filesystem;
    ModScan scan;
    std::error_code ec;
    if (!fs::is_directory("mods", ec)) return scan;

    // 先收齐候选 mod 文件夹并排序：列表顺序与应用顺序（撞键时谁覆盖谁）都由它定，
    // 跨机器一致。`mods/` 下只认文件夹（裸文件不是 mod）
    std::vector<std::string> ids;
    for (fs::directory_iterator it("mods", ec), end; it != end && !ec; it.increment(ec))
        if (it->is_directory(ec)) ids.push_back(it->path().filename().string());
    std::sort(ids.begin(), ids.end());

    for (const std::string& id : ids) {
        const fs::path dir = fs::path("mods") / id;
        const fs::path manifest = dir / "mod.lua";

        // 没有清单就不知道它覆盖到哪 → 跳过（不再有"目录结构即覆盖键"的隐式规则）
        if (!fs::is_regular_file(manifest, ec)) {
            log::warn("mod skipped (no mod.lua): " + dir.generic_string());
            continue;
        }

        // mod.lua 是"纯返回一个表"的声明：最小沙箱跑一次即可（与 shelf/素材包同一套）
        sol::state lua;
        open_pack_api(lua);
        lua_guard::BudgetScope budget;
        auto r = lua.safe_script_file(manifest.string(), &sol::script_pass_on_error);
        if (!r.valid() || !r.get<sol::object>().is<sol::table>()) {
            log::warn("mod skipped (mod.lua must return a table): " + manifest.string());
            continue;
        }
        sol::table t = r.get<sol::object>().as<sol::table>();

        // overrides 是必需的：没有它（或不是表）就无法声明覆盖，跳过这个 mod
        sol::object ov = t["overrides"];
        if (!ov.is<sol::table>()) {
            log::warn("mod skipped (mod.lua has no overrides table): " + manifest.string());
            continue;
        }

        ModManifest m;
        m.id = id;
        // 清单里的 name/desc 与 manifest 同一套本地化读法（字符串 = 中英同文）
        const lua_sandbox::Localized name = lua_sandbox::read_localized(t, "name");
        const lua_sandbox::Localized desc = lua_sandbox::read_localized(t, "desc");
        m.name_zh = name.empty() ? id : name.zh;
        m.name_en = name.empty() ? id : name.en;
        m.desc_zh = desc.zh;
        m.desc_en = desc.en;

        // default_off = true：出厂默认关闭，要玩家显式打开（写进 config 的 mods_enabled）
        sol::object off = t["default_off"];
        m.default_off = off.is<bool>() && off.as<bool>();
        m.enabled = mod_enabled(id, m.default_off);

        // 未启用的 mod 仍列出（UI 能再开），但它的覆盖整份不进表
        if (m.enabled) {
            sol::table map = ov.as<sol::table>();
            for (const auto& kv : map) {
                if (!kv.first.is<std::string>() || !kv.second.is<std::string>()) {
                    log::warn("mod '" + id + "' has a non-string override entry, skipped");
                    continue;
                }
                const std::string key = kv.first.as<std::string>();
                const std::string rel = kv.second.as<std::string>();
                // 键须是 "<目标id>/<包内路径>"：没有斜杠就定位不到目标
                if (key.find('/') == std::string::npos || rel.empty()) {
                    log::warn("mod '" + id + "' override key must be '<target>/<path>': " + key);
                    continue;
                }
                const fs::path file = dir / rel;
                if (!fs::is_regular_file(file, ec)) {
                    log::warn("mod '" + id + "' override file missing: " + file.generic_string());
                    continue;
                }
                // 命名化后两个 mod 可注册同一键：按 id 字典序后处理的覆盖先前的并留痕
                if (scan.overrides.count(key) != 0)
                    log::warn("mod override collision on '" + key + "' (mod '" + id + "' wins)");
                scan.overrides[key] = file.generic_string();
            }
        }
        scan.mods.push_back(std::move(m));
    }

    if (!scan.mods.empty()) {
        std::string list;
        for (const ModManifest& m : scan.mods) {
            if (!list.empty()) list += ", ";
            list += m.id;
            if (!m.enabled) list += m.default_off ? " (off)" : " (disabled)";
        }
        log::info("mods loaded: " + list);
    }
    return scan;
}

bool load_sound(const std::string& dir, SoundPack& out, std::string& err,
                std::vector<std::string>* warnings) {
    namespace fs = std::filesystem;
    std::error_code ec;
    const auto warn = [warnings](std::string message) {
        if (warnings) warnings->push_back(std::move(message));
    };
    const std::string sounds_path = pack_script_path(dir, "sounds.lua");
    if (!fs::is_regular_file(sounds_path, ec)) {
        // 与皮肤/色板、开机动画一致：包写坏了要留痕，不能静默少一个音效包
        err = "sound pack missing sounds.lua: " + dir;
        return false;
    }
    out.id = fs::path(dir).filename().string();
    out.name = out.id;  // 显示名 = 文件夹名
    out.dir = dir;

    sol::state lua;
    open_pack_api(lua);
    lua_guard::BudgetScope budget;
    const auto script = lua.safe_script_file(sounds_path, &sol::script_pass_on_error);
    if (!script.valid() || !script.get<sol::object>().is<sol::table>()) {
        err = "sounds.lua must return a table: " + dir;
        if (!script.valid()) err += " | " + std::string(sol::error(script).what());
        return false;
    }
    sol::table events = script.get<sol::object>().as<sol::table>();

    const auto check_number = [&warn](const sol::table& spec, const char* key) {
        const sol::object v = spec[key];
        if (v.get_type() != sol::type::nil && !v.is<double>() && !v.is<int>())
            warn(std::string("event field '") + key + "' must be a number");
    };

    for (auto& kv : events) {
        if (!kv.first.is<std::string>()) {
            warn("sound pack has a non-string event key");
            continue;
        }
        const std::string event = kv.first.as<std::string>();
        if (!kv.second.is<sol::table>()) {
            warn("event '" + event + "' must be a table (skipped)");
            continue;
        }
        sol::table spec = kv.second.as<sol::table>();

        sol::object file = spec["file"];
        if (file.is<std::string>()) {
            out.files[event] = file.as<std::string>();
            continue;
        }
        if (file.get_type() != sol::type::nil) warn("event '" + event + "' file must be a string");

        ToneSpec tone;
        sol::object wave = spec["wave"];
        if (wave.is<std::string>()) tone.wave = wave_from_name(wave.as<std::string>());
        else if (wave.get_type() != sol::type::nil)
            warn("event '" + event + "' wave must be a string");
        sol::object perc = spec["perc"];
        if (perc.is<std::string>() && !perc.as<std::string>().empty()) {
            if (!percussion_spec(perc.as<std::string>()[0], tone))
                warn("event '" + event + "' has unknown perc token");
        } else if (perc.get_type() != sol::type::nil) {
            warn("event '" + event + "' perc must be a string");
        }

        check_number(spec, "freq");
        check_number(spec, "sweep");
        check_number(spec, "dur");
        check_number(spec, "volume");
        tone.freq = static_cast<float>(api::read_number(spec, "freq", tone.freq));
        tone.freq_end = static_cast<float>(api::read_number(spec, "sweep", tone.freq_end));
        tone.dur = static_cast<float>(api::read_number(spec, "dur", tone.dur));
        tone.volume = static_cast<float>(api::read_number(spec, "volume", tone.volume));
        out.tones[event] = tone;
    }
    return true;
}

std::vector<SoundPack> scan_sounds(const std::string& dir) {
    return scan_pack_dirs<SoundPack>(dir, [](const std::filesystem::path& path, SoundPack& out) {
        std::string err;
        if (load_sound(path.string(), out, err)) return true;
        log::warn(err);
        return false;
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

bool load_font_scheme(const std::string& dir, FontScheme& out, std::string& err,
                      std::vector<std::string>* warnings) {
    namespace fs = std::filesystem;
    std::error_code ec;
    const auto warn = [warnings](std::string message) {
        if (warnings) warnings->push_back(std::move(message));
    };
    // 默认回退顺序（主字体在前、其余按名排序）；没有任何字体文件的目录不算方案
    std::vector<std::string> remaining = font_files_in_scheme(dir);
    if (remaining.empty()) {
        err = "font scheme has no .ttf/.otf/.ttc files: " + dir;
        return false;
    }
    out.name = fs::path(dir).filename().string();

    // font.lua 可选：显式声明字号与回退顺序（缺省按文件名规则）
    const std::string script = pack_script_path(dir, "font.lua");
    if (fs::is_regular_file(script, ec)) {
        sol::state lua;
        open_pack_api(lua);
        lua_guard::BudgetScope budget;
        auto r = lua.safe_script_file(script, &sol::script_pass_on_error);
        if (r.valid() && r.get<sol::object>().is<sol::table>()) {
            sol::table t = r.get<sol::object>().as<sol::table>();
            const auto check_number = [&warn](const sol::table& table, const char* key) {
                const sol::object v = table[key];
                if (v.get_type() != sol::type::nil && !v.is<double>() && !v.is<int>())
                    warn(std::string("font.lua ") + key + " must be a number");
            };
            check_number(t, "size");
            check_number(t, "min");
            check_number(t, "max");
            // 可调范围 min/max：Mod 覆盖 font.lua 抬高 max 即"更大字号"，硬上限只到 ceiling
            auto clamp_range = [&warn](sol::object v, int fallback, const char* key) {
                if (!v.is<double>() && !v.is<int>()) return fallback;
                const int px = v.as<int>();
                if (px < 1) {
                    warn(std::string("font.lua ") + key + " below 1 (clamped)");
                    return 1;
                }
                if (px > kMaxFontPxCeiling) {
                    warn(std::string("font.lua ") + key + " above ceiling (clamped)");
                    return kMaxFontPxCeiling;
                }
                return px;
            };
            out.min_size = clamp_range(t["min"], out.min_size, "min");
            out.max_size = clamp_range(t["max"], out.max_size, "max");
            if (out.max_size <= out.min_size) {
                warn("font.lua max <= min (clamped to min + 1)");
                out.max_size = out.min_size + 1;  // 退化范围兜底
            }
            sol::object size = t["size"];
            if (size.is<double>() || size.is<int>()) {
                const int px = size.as<int>();
                out.size = px < out.min_size ? out.min_size : (px > out.max_size ? out.max_size : px);
            }
            sol::object order = t["order"];
            if (order.get_type() != sol::type::nil && !order.is<sol::table>())
                warn("font.lua order must be a table");
            if (order.is<sol::table>()) {
                std::vector<std::string> files;
                sol::table ot = order.as<sol::table>();
                for (const auto& entry : ot) {
                    if (!entry.second.is<std::string>()) {
                        warn("font.lua order entries must be strings");
                        continue;
                    }
                    const std::string want = entry.second.as<std::string>();
                    // 先按**文件名**精确匹配，再退回按 stem：同一 stem 出现多个扩展名时
                    // （font.ttf + font.otf），精确文件名不受"排序最前"影响
                    auto fit = remaining.end();
                    for (auto it2 = remaining.begin(); it2 != remaining.end(); ++it2)
                        if (fs::path(*it2).filename().string() == want) {
                            fit = it2;
                            break;
                        }
                    if (fit == remaining.end())
                        for (auto it2 = remaining.begin(); it2 != remaining.end(); ++it2)
                            if (fs::path(*it2).stem().string() == want) {
                                fit = it2;
                                break;
                            }
                    if (fit != remaining.end()) {
                        files.push_back(*fit);
                        remaining.erase(fit);
                    } else {
                        warn("font.lua order entry '" + want + "' matches no font file in " + dir);
                    }
                }
                // 声明里漏掉的字体附在其后：绝不静默丢字
                for (const std::string& f : remaining) files.push_back(f);
                remaining = std::move(files);
            }
        } else {
            warn("font.lua 不可用，按文件名顺序加载字体: " + dir);
        }
    }
    out.files = std::move(remaining);
    return true;
}

std::vector<FontScheme> scan_font_schemes(const std::string& dir) {
    namespace fs = std::filesystem;
    std::vector<FontScheme> schemes;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) return schemes;

    for (fs::directory_iterator it(dir, ec), end; it != end && !ec; it.increment(ec)) {
        if (!it->is_directory(ec)) continue;
        FontScheme scheme;
        std::string err;
        std::vector<std::string> warnings;
        if (!load_font_scheme(it->path().generic_string(), scheme, err, &warnings)) continue;
        for (const std::string& warning : warnings) log::warn(warning);
        schemes.push_back(std::move(scheme));
    }

    std::sort(schemes.begin(), schemes.end(),
              [](const FontScheme& a, const FontScheme& b) { return a.name < b.name; });
    std::stable_partition(schemes.begin(), schemes.end(),
                          [](const FontScheme& s) { return s.name == "default"; });
    return schemes;
}

} // namespace phos
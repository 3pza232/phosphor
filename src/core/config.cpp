#include "core/config.hpp"

#include "core/json_lite.hpp"
#include "core/crt.hpp"
#include "core/log.hpp"

#include <algorithm>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace phos {

namespace {

/// 最近打开记录的保留条数：够覆盖一台机器的常用卡带即可
constexpr size_t kMaxRecent = 24;

/// 删掉半份写出的临时文件（失败路径的清理；删不掉也没有更好的补救）。
/// 只删普通文件：临时文件位置被别的东西（例如目录）占住时不动它
void discard_tmp(const std::string& tmp) {
    std::error_code ec;
    if (std::filesystem::is_regular_file(tmp, ec)) std::filesystem::remove(tmp, ec);
}

/// 原子写：先写 <path>.tmp，flush/close 成功后再改名覆盖。
/// 任何一步失败都保留旧文件——设置丢了比写坏一份配置好查得多
bool write_atomic(const std::string& path, const std::string& text, std::string& err) {
    const std::string tmp = path + ".tmp";
    std::ofstream out(tmp, std::ios::trunc);
    if (!out) {
        err = "cannot create " + tmp;
        return false;
    }
    out << text;
    out.flush();
    if (!out) {
        err = "write failed: " + tmp;
        discard_tmp(tmp);
        return false;
    }
    out.close();
    if (!out) {
        err = "close failed: " + tmp;
        discard_tmp(tmp);
        return false;
    }

    std::error_code ec;
    std::filesystem::rename(tmp, path, ec);
    if (ec) {
        err = "rename failed: " + ec.message();
        discard_tmp(tmp);
        return false;
    }
    return true;
}

/// 取字符串：缺项或空串都用默认值（手写配置常把值留空）
std::string pick(const json::Object* scope, const char* key, std::string fallback) {
    if (!scope || !scope->has(key)) return fallback;
    const std::string value = scope->str(key);
    return value.empty() ? fallback : value;
}

int pick_int(const json::Object* scope, const char* key, int fallback) {
    if (!scope || !scope->has(key)) return fallback;
    return scope->integer(key, fallback);
}

int clamp_volume(int value) { return value < 0 ? 0 : (value > 100 ? 100 : value); }

/// 重绑定键名的最小合法性：可见 ASCII、非空、长度受限（与虚拟键名同一套限制）
bool valid_binding_name(const std::string& name) {
    if (name.empty() || name.size() > 64) return false;
    for (unsigned char c : name) {
        if (c < 33 || c > 126) return false;
    }
    return true;
}

/// 读一个字符串数组：去空、去重（手改文件写重复项也只算一次）
std::vector<std::string> read_id_array(const json::Object* scope, const char* key) {
    std::vector<std::string> out;
    if (!scope) return out;
    for (const std::string& id : scope->string_array(key)) {
        if (id.empty()) continue;
        if (std::find(out.begin(), out.end(), id) == out.end()) out.push_back(id);
    }
    return out;
}

} // namespace

Config load_config(const std::string& path) {
    Config cfg;
    std::ifstream in(path);
    if (!in) return cfg;  // 没有配置文件 = 全默认（首次启动的正常路径）
    std::ostringstream ss;
    ss << in.rdbuf();

    // 解析用与控制通道同一份 JSON 工具（core/json_lite.hpp）：格式语义只有一处定义
    json::Object root;
    std::string err;
    if (!root.parse(ss.str(), err)) {
        // 手写配置写坏了必须留痕，并整体退回默认值——绝不让主机因此开不起来
        log::warn("config: cannot parse " + path + " (" + err + "), using defaults");
        return cfg;
    }
    // **按作用域取值**：主题相关的键住在 theme 子对象里，其余在顶层。
    // 全文搜"第一次出现"会被同名键抢走本该读的值——手写时很容易顺手把
    // shelf_style 也抄进 theme 里，那样读到的就是 theme 里那一份。
    const json::Object* theme = root.object("theme");

    // 同一个键写两遍是手写配置的常见失误（会静默只生效一个），两个作用域都提醒
    for (const std::string& key : root.duplicate_keys())
        log::warn("config: duplicate key '" + key + "' at top level in " + path +
                  " (the last one is used)");
    if (theme)
        for (const std::string& key : theme->duplicate_keys())
            log::warn("config: duplicate key '" + key + "' in theme of " + path +
                      " (the last one is used)");
    cfg.skin = pick(theme, "skin", cfg.skin);
    cfg.boot = pick(theme, "boot", cfg.boot);
    cfg.sound = pick(theme, "sound", cfg.sound);
    cfg.font = pick(theme, "font", cfg.font);
    cfg.language = pick(theme, "language", cfg.language);
    // 字号：<=0 视作"跟随字体方案"（0）；正数钳进 [kMinFontPx, kMaxFontPxCeiling] 的**宽松**区间
    // （真正的可调范围由当前字体方案声明，加载时尚不知方案，故只做硬上限钳制）
    const int font_size = pick_int(theme, "font_size", 0);
    cfg.font_size =
        font_size <= 0 ? 0
                       : (font_size < kMinFontPx
                              ? kMinFontPx
                              : (font_size > kMaxFontPxCeiling ? kMaxFontPxCeiling : font_size));

    // 卡带架样式：`list` / `window` / 某个 shelf 包 id。这里不判"包是否存在"——
    // 加载配置时还没扫内容包，是否有对应包由内容库在扫描后裁决（找不到回退 window）
    cfg.shelf_style = pick(&root, "shelf_style", cfg.shelf_style);

    const int level = pick_int(&root, "crt_level", kDefaultCrtLevel);
    cfg.crt_level = level < 0 ? 0 : (level >= kCrtLevelCount ? kCrtLevelCount - 1 : level);

    // 帧率：只认档位表里的值。手写一个表外的数（比如 90）就落到最接近的一档并留痕——
    // 静默接受一个"这台机器做不到"的刷新率，比取整更糟
    const int wanted = pick_int(&root, "fps", kDefaultFps);
    cfg.fps = kFpsChoices[0];
    for (int i = 0; i < kFpsChoiceCount; ++i)
        if (std::abs(kFpsChoices[i] - wanted) < std::abs(cfg.fps - wanted))
            cfg.fps = kFpsChoices[i];
    if (cfg.fps != wanted)
        log::warn("config: fps=" + std::to_string(wanted) + " is not a supported rate, using " +
                  std::to_string(cfg.fps));

    // 兼容旧配置的单 volume 字段：作为两层音量的初值
    const int legacy = pick_int(&root, "volume", -1);
    cfg.music_volume =
        clamp_volume(pick_int(&root, "music_volume", legacy >= 0 ? legacy : kDefaultMusicVolume));
    cfg.sfx_volume =
        clamp_volume(pick_int(&root, "sfx_volume", legacy >= 0 ? legacy : kDefaultSfxVolume));

    // 两个 Mod 列表：默认开的被关掉（mods_disabled）/ 默认关的被打开（mods_enabled）。
    // 各自去重去空，手改文件写重复项也只算一次
    cfg.mods_disabled = read_id_array(&root, "mods_disabled");
    cfg.mods_enabled = read_id_array(&root, "mods_enabled");

    // 输入重绑定：物理键名 → 虚拟键名。空/缺省 = 恒等映射（旧行为）；
    // 非法项忽略并留痕（手写配置写坏一个条目不应让整份配置退回默认）
    if (const json::Object* bindings = root.object("input_bindings")) {
        for (const std::string& physical : bindings->keys()) {
            const std::string virtual_key = bindings->str(physical);
            if (!valid_binding_name(physical) || !valid_binding_name(virtual_key)) {
                log::warn("config: invalid input binding ignored: " + physical);
                continue;
            }
            cfg.input_bindings[physical] = virtual_key;
        }
    } else if (root.has("input_bindings")) {
        log::warn("config: input_bindings must be an object");
    }
    return cfg;
}

void save_config(const std::string& path, const Config& cfg) {
    // 所有字符串字段都走 json::quote：skin 名里一个引号或反斜杠都不能把配置文件写坏
    std::string text;
    text += "{\n";
    text += "  \"theme\": {\n";
    text += "    \"skin\": " + json::quote(cfg.skin) + ",\n";
    text += "    \"boot\": " + json::quote(cfg.boot) + ",\n";
    text += "    \"sound\": " + json::quote(cfg.sound) + ",\n";
    text += "    \"font\": " + json::quote(cfg.font) + ",\n";
    text += "    \"font_size\": " + std::to_string(cfg.font_size) + ",\n";
    text += "    \"language\": " + json::quote(cfg.language) + "\n";
    text += "  },\n";
    text += "  \"shelf_style\": " + json::quote(cfg.shelf_style) + ",\n";
    text += "  \"crt_level\": " + std::to_string(cfg.crt_level) + ",\n";
    text += "  \"fps\": " + std::to_string(cfg.fps) + ",\n";
    text += "  \"music_volume\": " + std::to_string(cfg.music_volume) + ",\n";
    text += "  \"sfx_volume\": " + std::to_string(cfg.sfx_volume) + ",\n";
    text += "  \"input_bindings\": {";
    bool first_binding = true;
    for (const auto& [physical, virtual_key] : cfg.input_bindings) {
        text += first_binding ? "" : ", ";
        text += json::quote(physical) + ": " + json::quote(virtual_key);
        first_binding = false;
    }
    text += "},\n";
    text += "  \"mods_disabled\": [";
    for (size_t i = 0; i < cfg.mods_disabled.size(); ++i)
        text += (i == 0 ? "" : ", ") + json::quote(cfg.mods_disabled[i]);
    text += "],\n";
    text += "  \"mods_enabled\": [";
    for (size_t i = 0; i < cfg.mods_enabled.size(); ++i)
        text += (i == 0 ? "" : ", ") + json::quote(cfg.mods_enabled[i]);
    text += "]\n";
    text += "}\n";

    std::string error;
    if (!write_atomic(path, text, error)) {
        // 写不进去必须留痕：否则用户改了设置却以为已保存，重启后才发现丢了
        log::warn("cannot save config: " + path + " (" + error + ")");
    }
}

std::vector<std::string> load_recent(const std::string& path) {
    std::vector<std::string> ids;
    std::ifstream in(path);
    if (!in) return ids;  // 没有记录 = 首次启动，保持目录顺序

    std::string line;
    while (std::getline(in, line)) {
        while (!line.empty() && (line.back() == '\r' || line.back() == ' ')) line.pop_back();
        if (line.empty()) continue;
        // 手改过这个文件也要能读：重复项只认第一次出现的位置
        if (std::find(ids.begin(), ids.end(), line) == ids.end()) ids.push_back(line);
    }
    return ids;
}

std::string input_binding_for(const std::map<std::string, std::string>& bindings,
                              std::string_view physical) {
    if (bindings.empty()) return std::string(physical);
    const auto it = bindings.find(std::string(physical));
    if (it == bindings.end() || it->second.empty()) return std::string(physical);
    return it->second;  // 有映射：Window 注入虚拟键名，Input/卡带无感
}

void remember_recent(const std::string& path, const std::string& cart_id) {
    if (cart_id.empty()) return;

    std::vector<std::string> ids = load_recent(path);
    ids.erase(std::remove(ids.begin(), ids.end(), cart_id), ids.end());
    ids.insert(ids.begin(), cart_id);
    if (ids.size() > kMaxRecent) ids.resize(kMaxRecent);

    std::ofstream out(path, std::ios::trunc);
    if (!out) {
        log::warn("cannot save recent carts: " + path);
        return;
    }
    for (const std::string& id : ids) out << id << '\n';
}

} // namespace phos
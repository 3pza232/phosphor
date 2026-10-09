#include "core/config.hpp"

#include "agent/json_lite.hpp"
#include "core/crt.hpp"
#include "core/log.hpp"

#include <fstream>
#include <sstream>
#include <string>

namespace phos {

namespace {

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

} // namespace

Config load_config(const std::string& path) {
    Config cfg;
    std::ifstream in(path);
    if (!in) return cfg;  // 没有配置文件 = 全默认（首次启动的正常路径）
    std::ostringstream ss;
    ss << in.rdbuf();

    // 解析用与控制通道同一份 JSON 工具（agent/json_lite.hpp）：格式语义只有一处定义
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
    cfg.filter = pick(theme, "filter", cfg.filter);
    cfg.boot = pick(theme, "boot", cfg.boot);
    cfg.sound = pick(theme, "sound", cfg.sound);
    cfg.font = pick(theme, "font", cfg.font);
    cfg.language = pick(theme, "language", cfg.language);

    const std::string shelf_style = pick(&root, "shelf_style", cfg.shelf_style);
    if (shelf_style == "list" || shelf_style == "window") cfg.shelf_style = shelf_style;

    const int level = pick_int(&root, "crt_level", kDefaultCrtLevel);
    cfg.crt_level = level < 0 ? 0 : (level >= kCrtLevelCount ? kCrtLevelCount - 1 : level);

    // 兼容旧配置的单 volume 字段：作为两层音量的初值
    const int legacy = pick_int(&root, "volume", -1);
    cfg.music_volume =
        clamp_volume(pick_int(&root, "music_volume", legacy >= 0 ? legacy : kDefaultMusicVolume));
    cfg.sfx_volume =
        clamp_volume(pick_int(&root, "sfx_volume", legacy >= 0 ? legacy : kDefaultSfxVolume));
    return cfg;
}

void save_config(const std::string& path, const Config& cfg) {
    std::ofstream out(path, std::ios::trunc);
    if (!out) {
        // 写不进去必须留痕：否则用户改了设置却以为已保存，重启后才发现丢了
        log::warn("cannot save config: " + path);
        return;
    }
    out << "{\n"
        << "  \"theme\": {\n"
        << "    \"skin\": \"" << cfg.skin << "\",\n"
        << "    \"filter\": \"" << cfg.filter << "\",\n"
        << "    \"boot\": \"" << cfg.boot << "\",\n"
        << "    \"sound\": \"" << cfg.sound << "\",\n"
        << "    \"font\": \"" << cfg.font << "\",\n"
        << "    \"language\": \"" << cfg.language << "\"\n"
        << "  },\n"
        << "  \"shelf_style\": \"" << cfg.shelf_style << "\",\n"
        << "  \"crt_level\": " << cfg.crt_level << ",\n"
        << "  \"music_volume\": " << cfg.music_volume << ",\n"
        << "  \"sfx_volume\": " << cfg.sfx_volume << "\n"
        << "}\n";
}

} // namespace phos

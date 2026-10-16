#include "core/config.hpp"

#include "core/json_lite.hpp"
#include "core/crt.hpp"
#include "core/log.hpp"

#include <algorithm>
#include <cstdlib>
#include <fstream>
#include <sstream>
#include <string>
#include <vector>

namespace phos {

namespace {

/// 最近打开记录的保留条数：够覆盖一台机器的常用卡带即可
constexpr size_t kMaxRecent = 24;

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
        << "    \"boot\": \"" << cfg.boot << "\",\n"
        << "    \"sound\": \"" << cfg.sound << "\",\n"
        << "    \"font\": \"" << cfg.font << "\",\n"
        << "    \"font_size\": " << cfg.font_size << ",\n"
        << "    \"language\": \"" << cfg.language << "\"\n"
        << "  },\n"
        << "  \"shelf_style\": \"" << cfg.shelf_style << "\",\n"
        << "  \"crt_level\": " << cfg.crt_level << ",\n"
        << "  \"fps\": " << cfg.fps << ",\n"
        << "  \"music_volume\": " << cfg.music_volume << ",\n"
        << "  \"sfx_volume\": " << cfg.sfx_volume << "\n"
        << "}\n";
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

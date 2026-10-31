#include "devkit/check_packs.hpp"

#include "api/host_api.hpp"
#include "cart/cartridge.hpp"
#include "core/audio.hpp"
#include "core/defaults.hpp"
#include "core/input.hpp"
#include "core/palette.hpp"
#include "core/screen.hpp"
#include "core/text.hpp"
#include "pack/pack.hpp"
#include "ui/toast.hpp"

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <set>
#include <string>
#include <utility>
#include <vector>

namespace phos::devkit {
namespace {

namespace fs = std::filesystem;

void add(PackReport& report, PackSeverity severity, std::string message) {
    report.issues.push_back(PackIssue{severity, std::move(message)});
}

/// 包脚本执行用的最小宿主：所有指针都给安全值，不初始化音频设备/窗口。
/// 包脚本里的 phos.* 调用因此可以真实执行（boot/shelf 的入口与 draw 契约只能在运行时验），
/// 而资产/存档/联机这些没有的子系统保持 nullptr——API 层的空壳会让它们安静返回。
struct CheckHost {
    Screen screen{kContentW, kContentH};
    Input input;
    Palette palette = builtin_palette();
    Audio audio;  // 不 init：所有发声调用安全降级，不碰设备
    ui::Toasts toasts;
    bool capture_escape = false;
    HostContext host;

    CheckHost() {
        host.screen = &screen;
        host.input = &input;
        host.palette = &palette;
        host.audio = &audio;
        host.toasts = &toasts;
        host.capture_escape = &capture_escape;
        host.language = "zh";
    }
};

std::vector<std::string> list_pack_dirs(const fs::path& dir) {
    std::vector<std::string> out;
    std::error_code ec;
    if (!fs::is_directory(dir, ec)) return out;
    for (const auto& entry : fs::directory_iterator(dir, ec)) {
        if (entry.is_directory(ec)) out.push_back(entry.path().generic_string());
    }
    std::sort(out.begin(), out.end());
    return out;
}

void check_skin(PackReport& report, const fs::path& root, const std::string& dir) {
    Skin skin;
    std::string err;
    std::vector<std::string> warnings;
    if (!load_skin(dir, skin, err, &warnings)) {
        add(report, PackSeverity::error, err);
        return;
    }
    for (const std::string& warning : warnings) add(report, PackSeverity::warning, warning);

    if (!skin.palette.empty()) {
        const fs::path palette_lua = root / "theme" / "palette" / skin.palette / "palette.lua";
        std::error_code ec;
        if (!fs::is_regular_file(palette_lua, ec))
            add(report, PackSeverity::error,
                "引用的色板不存在: theme/palette/" + skin.palette + "/palette.lua");
    }

    // 外壳字符画比网格宽：主机按网格硬裁，右侧那截会消失
    const int grid_w = skin.grid_w();
    const auto check_rows = [&report, grid_w](const std::vector<std::string>& rows,
                                             const char* which) {
        for (std::size_t i = 0; i < rows.size(); ++i) {
            const int width = text::display_width(rows[i]);
            if (width <= grid_w) continue;
            add(report, PackSeverity::warning,
                std::string(which) + " 第 " + std::to_string(i + 1) + " 行宽 " +
                    std::to_string(width) + " 超过网格宽 " + std::to_string(grid_w) +
                    "（会被裁掉）");
        }
    };
    check_rows(skin.top, "top");
    check_rows(skin.bottom, "bottom");

    const int grid_h = skin.grid_h();
    for (const Skin::Lamp& lamp : skin.lamps) {
        if (lamp.x < 0 || lamp.x >= grid_w || lamp.y < 0 || lamp.y >= grid_h)
            add(report, PackSeverity::warning, "指示灯坐标超出机身网格 (" +
                                                   std::to_string(lamp.x) + "," +
                                                   std::to_string(lamp.y) + ")");
    }
}

void check_boot(PackReport& report, const std::string& dir) {
    BootPack pack;
    std::string err;
    if (!load_boot(dir, pack, err)) {
        add(report, PackSeverity::error, err);
        return;
    }
    CheckHost host;
    Cartridge cartridge;
    if (!cartridge.load_entry(dir, "main.lua", host.host)) {
        add(report, PackSeverity::error, cartridge.error());
        return;
    }
    // 与主机同一套时长解析：过短会被钳到 0.5s，写在这里提醒作者
    if (cartridge.declared_seconds(kBootDuration) < 0.5f)
        add(report, PackSeverity::warning, "开机时长小于 0.5s（主机会钳到 0.5s）");
}

void check_shelf(PackReport& report, const std::string& dir) {
    ShelfPack declared;
    std::string err;
    std::vector<std::string> warnings;
    if (!load_shelf_pack(dir, declared, err, &warnings)) {
        add(report, PackSeverity::error, err);
        return;
    }
    for (const std::string& warning : warnings) add(report, PackSeverity::warning, warning);

    CheckHost host;
    Cartridge cartridge;
    if (!cartridge.load_shelf(dir, host.host))
        add(report, PackSeverity::error, cartridge.error());  // draw(ctx) 契约只在运行时能验
}

void check_sound(PackReport& report, const std::string& dir) {
    SoundPack pack;
    std::string err;
    std::vector<std::string> warnings;
    if (!load_sound(dir, pack, err, &warnings)) {
        add(report, PackSeverity::error, err);
        return;
    }
    for (const std::string& warning : warnings) add(report, PackSeverity::warning, warning);

    for (const auto& [event, file] : pack.files) {
        const fs::path file_path = fs::path(dir) / file;
        std::error_code ec;
        if (!fs::is_regular_file(file_path, ec)) {
            add(report, PackSeverity::error,
                "事件 '" + event + "' 引用的音频文件不存在: " + file);
            continue;
        }
        std::string ext = file_path.extension().string();
        std::transform(ext.begin(), ext.end(), ext.begin(),
                       [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
        if (ext != ".wav" && ext != ".mp3" && ext != ".flac")
            add(report, PackSeverity::warning,
                "事件 '" + event + "' 的音频扩展名 " + ext + " 不在 wav/mp3/flac 内（解码可能失败）");
    }
}

void check_font(PackReport& report, const std::string& dir) {
    FontScheme scheme;
    std::string err;
    std::vector<std::string> warnings;
    if (!load_font_scheme(dir, scheme, err, &warnings)) {
        // 空目录会被扫描跳过；能跑但少了这个方案，算可修的警告
        add(report, PackSeverity::warning, err);
        return;
    }
    for (const std::string& warning : warnings) add(report, PackSeverity::warning, warning);
}

} // namespace

bool PackReport::has_error() const {
    return std::any_of(issues.begin(), issues.end(), [](const PackIssue& issue) {
        return issue.severity == PackSeverity::error;
    });
}

int PackCheckResult::errors() const {
    int count = 0;
    for (const PackReport& pack : packs)
        for (const PackIssue& issue : pack.issues)
            if (issue.severity == PackSeverity::error) ++count;
    return count;
}

int PackCheckResult::warnings() const {
    int count = 0;
    for (const PackReport& pack : packs)
        for (const PackIssue& issue : pack.issues)
            if (issue.severity == PackSeverity::warning) ++count;
    return count;
}

PackCheckResult check_packs(const std::string& root) {
    PackCheckResult result;
    const fs::path base = root.empty() ? fs::path(".") : fs::path(root);
    const fs::path theme = base / "theme";
    std::error_code ec;
    if (!fs::is_directory(theme, ec)) {
        PackReport meta;
        meta.kind = "theme";
        meta.dir = theme.generic_string();
        add(meta, PackSeverity::error, "内容根下找不到 theme/ 目录");
        result.packs.push_back(std::move(meta));
        return result;
    }

    const auto rel = [&base](const fs::path& dir) {
        const fs::path relative = dir.lexically_relative(base);
        return relative.empty() ? dir.generic_string() : relative.generic_string();
    };
    const auto report_for = [&rel](const char* kind, const std::string& dir) {
        PackReport report;
        report.kind = kind;
        report.id = fs::path(dir).filename().string();
        report.dir = rel(fs::path(dir));
        return report;
    };
    // 用户区与出厂区同名 = 覆盖关系（不是错误，但值得知道）
    const auto system_ids = [&base](const char* type) {
        std::set<std::string> ids;
        for (const std::string& dir : list_pack_dirs(base / "system" / type))
            ids.insert(fs::path(dir).filename().string());
        return ids;
    };
    const auto check_shadowed = [](PackReport& report, const std::set<std::string>& ids) {
        if (ids.count(report.id) == 0) return;
        add(report, PackSeverity::warning,
            "同名包也存在于 system/" + report.kind + "/（用户包会覆盖出厂包）");
    };

    // theme/ 下的目录名拼错（如 theme/skins）会让整类内容"静默消失"：明确点出来
    // icon 是窗口图标资源目录，不属于内容包类型；其余拼错目录才提示
    const std::set<std::string> known_types = {"boot",  "font", "palette", "shelf",
                                               "skin",  "sound", "icon"};
    for (const std::string& dir : list_pack_dirs(theme)) {
        const std::string name = fs::path(dir).filename().string();
        if (known_types.count(name)) continue;
        PackReport unknown;
        unknown.kind = "theme";
        unknown.id = name;
        unknown.dir = rel(fs::path(dir));
        add(unknown, PackSeverity::warning,
            "未知的 theme 子目录（可用类型：skin/palette/boot/sound/shelf/font）");
        result.packs.push_back(std::move(unknown));
    }

    const std::set<std::string> skin_ids = system_ids("skin");
    for (const std::string& dir : list_pack_dirs(theme / "skin")) {
        PackReport report = report_for("skin", dir);
        check_skin(report, base, dir);
        check_shadowed(report, skin_ids);
        result.packs.push_back(std::move(report));
    }

    const std::set<std::string> palette_ids = system_ids("palette");
    for (const std::string& dir : list_pack_dirs(theme / "palette")) {
        PackReport report = report_for("palette", dir);
        Palette palette;
        std::string err;
        std::vector<std::string> warnings;
        if (load_palette(dir, palette, err, &warnings))
            for (const std::string& warning : warnings) add(report, PackSeverity::warning, warning);
        else
            add(report, PackSeverity::error, err);
        check_shadowed(report, palette_ids);
        result.packs.push_back(std::move(report));
    }

    const std::set<std::string> boot_ids = system_ids("boot");
    for (const std::string& dir : list_pack_dirs(theme / "boot")) {
        PackReport report = report_for("boot", dir);
        check_boot(report, dir);
        check_shadowed(report, boot_ids);
        result.packs.push_back(std::move(report));
    }

    const std::set<std::string> sound_ids = system_ids("sound");
    for (const std::string& dir : list_pack_dirs(theme / "sound")) {
        PackReport report = report_for("sound", dir);
        check_sound(report, dir);
        check_shadowed(report, sound_ids);
        result.packs.push_back(std::move(report));
    }

    const std::set<std::string> shelf_ids = system_ids("shelf");
    for (const std::string& dir : list_pack_dirs(theme / "shelf")) {
        PackReport report = report_for("shelf", dir);
        check_shelf(report, dir);
        check_shadowed(report, shelf_ids);
        result.packs.push_back(std::move(report));
    }

    const std::vector<std::string> font_dirs = list_pack_dirs(theme / "font");
    bool has_default_font = false;
    for (const std::string& dir : font_dirs) {
        PackReport report = report_for("font", dir);
        check_font(report, dir);
        if (report.id == "default") has_default_font = true;
        result.packs.push_back(std::move(report));
    }
    if (font_dirs.empty()) {
        PackReport report;
        report.kind = "font";
        report.dir = rel(theme / "font");
        add(report, PackSeverity::warning,
            "没有字体方案（主机使用内置字体的回退顺序）");
        result.packs.push_back(std::move(report));
    } else if (!has_default_font) {
        PackReport report;
        report.kind = "font";
        report.dir = rel(theme / "font");
        add(report, PackSeverity::warning,
            "没有名为 default 的字体方案（设置界面默认选第一个）");
        result.packs.push_back(std::move(report));
    }

    return result;
}

} // namespace phos::devkit

#pragma once

#include <cstddef>
#include <string>
#include <vector>

namespace phos::devkit {

/// 内容包检查的严重级别：error = 这一包/这一条引用已经坏了（退出码 2）；
/// warning = 能回退但值得修（安静回退会让人找不到原因）
enum class PackSeverity { warning, error };

struct PackIssue {
    PackSeverity severity = PackSeverity::warning;
    std::string message;
};

/// 单个内容包的检查结果
struct PackReport {
    std::string kind;  // skin / palette / boot / sound / shelf / font（"theme" 用于整根错误）
    std::string id;    // 目录名（= 包 id）
    std::string dir;   // 相对内容根的目录，如 "theme/skin/default"
    std::vector<PackIssue> issues;

    bool has_error() const;
};

/// --check-packs 的完整结果
struct PackCheckResult {
    std::vector<PackReport> packs;  // 含无问题的包，便于汇总"检查了多少个"
    int errors() const;
    int warnings() const;
    bool ok() const { return errors() == 0; }
    std::size_t count() const { return packs.size(); }
};

/// 只读检查内容根 `root` 下 theme/ 的六类内容包（skin/palette/boot/sound/shelf/font）：
/// 必需脚本是否存在且能在既有沙箱里执行、顶层声明类型、包内引用文件、目录名与 id 规则、
/// 用户区与出厂区（system/<type>）的同名覆盖、字体方案目录为空。
/// 不初始化窗口/音频、不读写配置与存档；不扫描 mods（覆盖层不在本检查范围）。
PackCheckResult check_packs(const std::string& root);

} // namespace phos::devkit

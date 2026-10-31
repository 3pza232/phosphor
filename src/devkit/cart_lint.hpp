#pragma once

#include <string>
#include <vector>

namespace phos::devkit {

enum class LintSeverity { info, warning, error };

struct LintIssue {
    LintSeverity severity = LintSeverity::info;
    std::string where;  // 出问题的文件（相对包根）
    int line = 0;       // 0 = 整个文件/包级
    std::string message;
};

struct LintReport {
    std::string cart_id;
    std::string path;
    std::vector<LintIssue> issues;
    int errors() const;
    int warnings() const;
    bool ok() const { return errors() == 0; }
};

/// 卡带静态检查：manifest/入口是否有效 + 源码里几类"一定会出问题"的写法。
///
/// 它**不运行**卡带（不执行 init/update/draw），因此是静态、可重复、零副作用的；
/// 代价是只认字面写法——漏报好过误报，所以每条检查都写成"高置信度模式"：
///   * 顶层隐式全局（卡带之间/测试之间互相污染，且改名后静默失效）
///   * `phos.screen.size()`（含侧栏的整屏宽，画过去会被面板挡掉；应用 playfield）
///   * `phos.net.discover(`（有界阻塞，放在 update 里会撞 100ms 看门狗）
///   * `require("x")` 指向包内不存在的模块
///   * 既没有 debug_state() 也没有 phos.observe（agent 看不到玩法状态）
LintReport lint_cart(const std::string& cart_dir);

} // namespace phos::devkit

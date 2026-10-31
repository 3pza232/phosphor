#pragma once

#include <optional>
#include <string>

namespace phos {

class Cartridge;
class SaveStore;
class Shell;
struct HostContext;

/// 磁带码与存档路径胶水（S1 尾项）：把"卡带存档 → Shell 磁带码界面"的接线集中一处。
/// 只管数据适配与结果语义；界面状态机/绘制仍归 shell/tape_view，卡带生命周期仍由 App 编排。
class TapeGlue {
public:
    /// 卡带的存档可用性：卡带存在且声明了 save 才有存档（否则界面按 no_save 处理）
    static SaveStore* save_of(Cartridge* cart);

    /// 打开磁带码界面：当前卡带名（按界面语言）与导出码、是否可用
    static void open(Shell& shell, Cartridge* cart, bool english);

    /// 导入一条磁带码：写回结果状态并留日志（新档要重新插卡才生效，提示由界面给）
    static void import(Shell& shell, SaveStore* save, const std::string& code);

    /// --save-dir 覆盖：工具脚本用它隔离真实存档（空 = 用默认 saves/）
    static void apply_save_dir(HostContext& host, const std::optional<std::string>& dir);
};

} // namespace phos

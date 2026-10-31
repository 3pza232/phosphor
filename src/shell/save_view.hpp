#pragma once

#include "core/input.hpp"
#include "core/ui.hpp"
#include "shell/messages.hpp"
#include "ui/element.hpp"

#include <cstdint>
#include <string>
#include <vector>

namespace phos::save {

/// 存档管理屏的一条：App 扫描 save_dir 后注入（文件解析/大小/时间/删除路径都在 App 侧）。
struct Entry {
    std::string cart_id;
    int slot = 0;              // 0 = <id>.sav；1..9 = <id>.s{n}.sav
    std::uintmax_t bytes = 0;  // 文件大小
    std::string modified;      // 已格式化的本地时间（App 注入，界面不再碰文件系统）
    std::string path;          // 删除/读码用的完整路径
};

/// 存档管理屏（屏幕栈上的普通浮层，Esc 返回设置）：列表 + 删除二次确认 + 查看导出码。
/// 数据读取/删除/路径由 App 通过 Shell 的钩子注入；本模块只管视图与选中/确认状态。
class ScreenState {
public:
    static constexpr const char* kScreenId = "shell.saves";  // ui::Frame 的屏 id（焦点状态）
    static constexpr const char* kBackId = "saves/back";
    static constexpr const char* kDeleteId = "saves/delete";
    static constexpr const char* kConfirmId = "saves/confirm_delete";
    static constexpr const char* kCancelId = "saves/cancel_delete";
    /// 列表行 id 前缀："saves/row/<下标>"
    static std::string row_id(int index);

    void open();  // 清确认态、光标归零
    void set_entries(std::vector<Entry> entries);
    const std::vector<Entry>& entries() const { return entries_; }
    bool empty() const { return entries_.empty(); }

    void select(int index);
    int selected() const { return selected_; }
    const Entry* selected_entry() const;

    void set_confirm(bool on) { confirm_ = on; }
    bool confirming() const { return confirm_; }

    /// 声明本屏元素树：列表 / 空状态 / 删除确认（二次确认文案明确"不可撤销"）
    void build(ui::Node& root, const ui::Rect& content, Lang lang) const;

private:
    std::vector<Entry> entries_;
    int selected_ = 0;
    bool confirm_ = false;
};

} // namespace phos::save

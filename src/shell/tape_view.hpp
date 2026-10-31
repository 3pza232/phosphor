#pragma once

#include "cart/save_store.hpp"
#include "core/input.hpp"
#include "core/ui.hpp"
#include "shell/messages.hpp"
#include "ui/element.hpp"

#include <cstddef>
#include <string>
#include <string_view>

namespace phos::tape {

/// 磁带码界面：查看本机存档导出的码 / 输入别的机器的码。
///
/// 状态机（查看页与输入页、滚动、结果行）整套留在这里；外壳只给它数据（`set_tape`）、
/// 把输入页的提交翻成 `Intent`、按它报的文案编号画标题栏与页脚
/// （`page_hint` / `footer_hint`）。版面本身是声明式元素树（见 `build`）。
/// 名字带 State 而不叫 Screen：后者会遮蔽 `phos::Screen`（字符网格），
/// 让同文件里的绘制函数不知不觉拿到错类型。
class ScreenState {
public:
    /// 导入结果。界面只收语义、自己按语言取词——文案属于界面层
    enum class Result { none, ok, invalid, no_save };

    /// 输入页文本域的元素 id。码本身由组件持有（过滤/限长/退格都在 TextInput 里），
    /// 外壳经 `Frame::field_text` 取它：界面的状态不再存两份
    static constexpr const char* kFieldId = "tape/field";

    /// App 在进入界面时填入：卡带名、本机的码、该卡带是否有存档
    void set_tape(std::string cart_name, std::string code, bool available);
    void set_result(Result result) { result_ = result; }
    /// 从暂停菜单进入：回到查看页、滚动归零（文本域由外壳连同本屏状态一起清空）
    void open();

    const std::string& cart_name() const { return cart_; }
    /// 标题栏右侧的状态词（查看页 / 输入页）
    Msg page_hint() const;
    /// 页脚提示：无存档时是"返回"提示，与有码时的操作提示不同
    Msg footer_hint() const;

    /// 把本页声明成一棵元素树。坐标系与旧版面逐格一致（左缘 content.x+kMarginX+2、
    /// 首行 content.y+kContentTop）；`typed` 是输入页文本域的当前内容，只用于"已输入 N 位"。
    void build(ui::Node& root, const ui::Rect& content, Lang lang, std::string_view typed) const;

    /// 左右切页、查看页滚动。导入由输入页文本域提交（Frame 的 submitted 事件）——
    /// 界面自己不产生副作用，App 拿到请求后才动作
    void update(const Input& input);

private:
    std::string cart_;
    std::string code_;
    /// 码的字符上限必须容得下**最大的合法导出码**，否则粘贴一个大会话的码会被静默截断成半份：
    /// 存档上限 kMaxEntries × (键长 + 值长 + 2 个分隔) 字节，再按十六进制 ×2
    static constexpr std::size_t kMaxChars =
        SaveStore::kMaxEntries * (SaveStore::kMaxKeyLength + SaveStore::kMaxValueLength + 2) * 2;
    Result result_ = Result::none;
    bool available_ = false;
    bool edit_ = false;  // true = 输入页，false = 查看页
    int scroll_ = 0;
};

} // namespace phos::tape

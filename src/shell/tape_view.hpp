#pragma once

#include "core/input.hpp"
#include "core/screen.hpp"
#include "core/text_input.hpp"
#include "core/ui.hpp"
#include "cart/save_store.hpp"
#include "shell/messages.hpp"

#include <cstddef>
#include <string>

namespace phos::tape {

/// 磁带码界面：查看本机存档导出的码 / 输入别的机器的码。
///
/// 状态机（查看页与输入页、滚动、输入缓冲、结果行）整套留在这里；外壳只给它数据
/// （`set_tape`）、把它的请求转成 `Intent`（`update`）、按它报的文案编号画标题栏与页脚
/// （`page_hint` / `footer_hint`）。
/// 名字带 State 而不叫 Screen：后者会遮蔽 `phos::Screen`（字符网格），
/// 让同文件里的绘制函数不知不觉拿到错类型。
class ScreenState {
public:
    /// 导入结果。界面只收语义、自己按语言取词——文案属于界面层
    enum class Result { none, ok, invalid, no_save };

    /// App 在进入界面时填入：卡带名、本机的码、该卡带是否有存档
    void set_tape(std::string cart_name, std::string code, bool available);
    void set_result(Result result) { result_ = result; }
    /// 从暂停菜单进入：回到查看页、滚动归零、缓冲区与结果行清空
    void open();

    const std::string& cart_name() const { return cart_; }
    /// 标题栏右侧的状态词（查看页 / 输入页）
    Msg page_hint() const;
    /// 页脚提示：无存档时是"返回"提示，与有码时的操作提示不同
    Msg footer_hint() const;

    /// 处理一帧输入。返回非空串 = 玩家请求导入这段码；其余情况返回空串。
    /// （返回请求而不是直接改外壳状态：界面不产生副作用，App 拿到后才动作）
    std::string update(const Input& input);

    /// 画内容区（标题栏与页脚由外壳画：它们是全机统一的）
    void draw(Screen& screen, const ui::Rect& content, Lang lang, const ui::Style& style) const;

private:
    std::string cart_;
    std::string code_;
    /// 输入缓冲：过滤（只收十六进制）、按码点退格、限长都在缓冲层完成，
    /// 界面自己不做字符判断——中文等非十六进制字符在门口就被挡掉。
    /// 上限必须容得下**最大的合法导出码**，否则粘贴一个大会话的码会被静默截断成半份：
    /// 存档上限 kMaxEntries × (键长 + 值长 + 2 个分隔) 字节，再按十六进制 ×2
    static constexpr std::size_t kMaxChars =
        SaveStore::kMaxEntries * (SaveStore::kMaxKeyLength + SaveStore::kMaxValueLength + 2) * 2;
    text::TextInput input_{text::TextInput::accept_hex, kMaxChars};
    Result result_ = Result::none;
    bool available_ = false;
    bool edit_ = false;  // true = 输入页，false = 查看页
    int scroll_ = 0;
};

} // namespace phos::tape

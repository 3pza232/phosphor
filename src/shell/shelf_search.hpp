#pragma once

#include "cart/cart_info.hpp"
#include "core/text_input.hpp"

#include <string>
#include <string_view>
#include <vector>

namespace phos {

/// 卡带架的搜索：一个查询串 + 一套"什么算匹配"的判据。
///
/// 单独成模块，是因为匹配规则（子序列 + 打分排序）是要单独想清楚的东西，
/// 混进架面的按键处理里以后，谁都说不清"为什么这只能搜到那只"。
///
/// 三个状态互不相同，别合并：
///   * 不显示（没搜过 / 已被 Esc 收起）
///   * 显示但不输入（Enter 确认过：查询串还在、列表还是过滤的、可以直接选）
///   * 显示且输入（正在敲字：这一帧所有可打印字符都进查询串）
class ShelfSearch {
public:
    /// 查询串最长多少**码点**：卡带名与 id 都很短，限制只是防手滑按住不放
    static constexpr std::size_t kMaxChars = 24;

    bool visible() const { return visible_; }
    bool editing() const { return editing_; }
    const std::string& query() const { return input_.value(); }

    /// F：进输入框。已显示时是"回到输入框"，查询串原样留着
    void begin_edit() {
        visible_ = true;
        editing_ = true;
    }
    /// Enter：确认。退出输入但**保留**查询串与过滤结果（这是"确认搜索"）
    void commit() { editing_ = false; }
    /// Esc（输入框内）：清空查询串并收起——架面上的 Esc 原本是关机，
    /// 所以这个键位是刻意抢过来的，见 App::handle_escape
    void cancel() {
        input_.clear();
        editing_ = false;
        visible_ = false;
    }
    /// 把这一帧敲进来的字符喂给缓冲（退格、限长、过滤都在 TextInput 里）
    void apply_text(std::string_view typed) { input_.apply(typed); }

    /// 匹配的卡带下标：按分数从高到低，同分保持原有顺序。
    /// 查询串为空时是全部——于是"没搜索"与"搜索了空串"是同一条路径
    std::vector<int> match(const std::vector<CartInfo>& carts) const;

private:
    text::TextInput input_{text::TextInput::accept_printable, kMaxChars};
    bool visible_ = false;
    bool editing_ = false;
};

} // namespace phos

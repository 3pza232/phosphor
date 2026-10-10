#include "shell/shelf_search.hpp"

#include <algorithm>
#include <cctype>

namespace phos {

namespace {

/// ASCII 折叠：卡带 id 与名字都是英文数字，够用；非 ASCII 原样比较
char fold(char c) { return static_cast<char>(std::tolower(static_cast<unsigned char>(c))); }

/// 子序列匹配的打分。<0 表示不匹配（这条约定要守住——0 分是"匹配但很勉强"）。
/// 加分点按"人找东西的心智"来定：命中更连续、更靠前、目标更短，就越可能是想找的那只
int score_match(std::string_view query, std::string_view target) {
    if (query.empty()) return 1;
    std::size_t q = 0;
    int score = 0;
    int streak = 0;
    for (std::size_t i = 0; i < target.size() && q < query.size(); ++i) {
        if (fold(target[i]) != fold(query[q])) {
            streak = 0;   // 断了：连续性奖励归零，但整条查询不算失败（子序列还能接上）
            continue;
        }
        score += 2 + streak * 2;
        if (i == 0) score += 3;
        ++q;
        ++streak;
    }
    if (q < query.size()) return -1;
    return score - static_cast<int>(target.size()) / 4;
}

/// 一只卡带对查询串的分数：id 与显示名各算一次，取高的那个。
/// 两个字段都要看：玩家记得住"WORMS"，也记得住目录名 "worms"
int cart_score(std::string_view query, const CartInfo& cart) {
    return std::max(score_match(query, cart.id), score_match(query, cart.name));
}

} // namespace

std::vector<int> ShelfSearch::match(const std::vector<CartInfo>& carts) const {
    std::vector<std::pair<int, int>> scored;   // {分数, 下标}
    for (std::size_t i = 0; i < carts.size(); ++i) {
        const int score = cart_score(input_.value(), carts[i]);
        if (score >= 0) scored.emplace_back(score, static_cast<int>(i));
    }
    // 稳定排序 + 分数降序：同分保持架子原有顺序（"最近打开"的顺序有意义，别打乱）
    std::stable_sort(scored.begin(), scored.end(),
                     [](const auto& a, const auto& b) { return a.first > b.first; });
    std::vector<int> out;
    out.reserve(scored.size());
    for (const auto& entry : scored) out.push_back(entry.second);
    return out;
}

} // namespace phos

#pragma once

#include "core/color.hpp"

#include <algorithm>
#include <map>
#include <string>
#include <vector>

namespace phos {

/// 一段可本地化的文本（当前用于 manifest 的 desc）：
/// `desc = "…"` 表示中英同文；`desc = { zh = "…", en = "…" }` 各语言一份。
struct Localized {
    std::string zh;
    std::string en;
    /// 按机器界面语言取；english=false → 中文（en 为空时回落中文，绝不给出空串）
    const std::string& get(bool english) const { return english && !en.empty() ? en : zh; }
};

/// 卡带元信息（来自 manifest.lua）。
///
/// 单独成文件（而非留在 cartridge.hpp）：卡带列表 / 搜索这类**不碰 Lua** 的模块只该依赖
/// 这份纯数据，不该因为"要用 CartInfo"就连整个 Lua 宿主（sol2）一起编译
struct CartInfo {
    std::string id;
    std::string name;
    std::string author;
    std::string version;
    Localized desc;
    std::string path;      // 卡带路径（目录或 .phos 文件）
    std::string error;     // 非空表示损坏卡带及原因
    std::string entry;     // 入口脚本（缺省 main.lua）——解析一次，装配与打包共用
    int sidebar_w = 0;     // 右侧栏面板宽度（0 = 无侧栏）
    bool wants_save = false;

    // 像素图标：逐行字符画 + 每字符颜色（'.' 与空格为透明）
    std::vector<std::string> icon_rows;
    std::map<char, Color> icon_colors;
};

/// 按"最近打开"重排卡带：最近的在最前，其余保持原顺序（stable）。
/// 用 id 匹配而不是路径——同一张卡带换个目录也认得出来；不在记录里的（新卡带）排在后面，
/// 位置由原顺序决定。纯函数（只读 CartInfo 与 recent 列表），单测直接覆盖
inline void order_by_recent(std::vector<CartInfo>& carts, const std::vector<std::string>& recent) {
    const auto rank = [&recent](const CartInfo& cart) {
        const auto it = std::find(recent.begin(), recent.end(), cart.id);
        return it == recent.end() ? recent.size() : static_cast<size_t>(it - recent.begin());
    };
    std::stable_sort(carts.begin(), carts.end(),
                     [&rank](const CartInfo& a, const CartInfo& b) { return rank(a) < rank(b); });
}

} // namespace phos

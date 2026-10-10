#pragma once

#include "core/palette.hpp"
#include "pack/pack.hpp"

#include <algorithm>
#include <vector>

namespace phos {

/// 出厂内置内容的兜底与合并规则。
/// 留在 `pack/` 是因为这里定义的是**内容**（内置包长什么样、出厂区与用户区谁优先）；
/// 挪进 `core/` 会让下层反向依赖 `pack/` 的 `SoundPack`

/// "NONE" 滤镜：不做色调处理，保留卡带原本配色（扫描线由机器档位单独控制）
Palette raw_filter();

/// "SILENT" 音效包：内置空包，用于彻底关闭主机事件音
SoundPack silent_sound_pack();

/// 合并用户区与出厂区的包（同 id 时用户区胜出）
template <typename T>
void merge_packs(std::vector<T>& base, const std::vector<T>& extra) {
    for (const auto& pack : extra) {
        const bool shadowed =
            std::any_of(base.begin(), base.end(),
                        [&pack](const T& existing) { return existing.id == pack.id; });
        if (!shadowed) base.push_back(pack);
    }
}

} // namespace phos

#pragma once

#include "core/palette.hpp"
#include "pack/pack.hpp"

#include <algorithm>
#include <vector>

namespace phos {

/// 出厂内置内容的兜底与合并规则。
///
/// 为什么在 `pack/`：这里定义的是**内容**（内置包长什么样、出厂区与用户区谁优先），
/// 不是 App 的生命周期。App 的初始化与设置落地都要用它，所以单独成文件。
/// 放 `core/` 不行——`silent_sound_pack()` 要返回 `pack/` 的 `SoundPack`，
/// 那会让下层反向依赖上层。

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

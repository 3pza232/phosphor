#pragma once

#include "core/palette.hpp"
#include "core/skin.hpp"
#include "pack/pack.hpp"

#include <string>
#include <vector>

namespace phos {
struct Config;

/// 内容库：本机有哪些内容包、各自当前选中哪一个。
///
/// 只管"有什么、选中哪个"——把选中的那套**应用**出去（改几何 / 配色 / 音频 / 外壳）
/// 是主机行为，仍归 App：前者是纯数据 + 目录扫描，后者要动渲染与音频设备。
/// 集中在一处后，"列清单 / 按 id 定位 / 由主题解析色板"不再散在 App 的各成员里。
///
/// 两个兜底不变量（`scan` 永远保证其存在，故索引 0 恒有效）：
///   * `palettes[0]` = `raw_palette()`（无主题可解析时的原色兜底）
///   * `sounds[0]`   = `silent_sound_pack()`（彻底静音）
struct ContentLibrary {
    std::vector<Skin> skins;
    std::vector<Palette> palettes;
    std::vector<BootPack> boots;
    std::vector<SoundPack> sounds;

    int skin_index = 0;
    int palette_index = 0;  // 由当前主题的 skin.palette 解析得出
    int boot_index = 0;
    int sound_index = 0;

    /// 扫描用户区 + 出厂区并按配置里的选择定位各索引。
    /// 目录缺失 / 包损坏只是少几项，绝不抛（回退见文件头的不变量）。
    void scan(const Config& config);

    const Skin& skin() const { return skins[static_cast<size_t>(skin_index)]; }
    const Palette& palette() const { return palettes[static_cast<size_t>(palette_index)]; }

    /// 按当前主题声明的 `skin.palette` 名解出色板索引（找不到回落 0 = raw）。
    /// 纯数据逻辑，留头内联——既能被单测直接覆盖，也省一次跨单元调用
    void resolve_palette() {
        palette_index = 0;
        const std::string& wanted = skin().palette;
        for (std::size_t i = 0; i < palettes.size(); ++i)
            if (palettes[i].id == wanted) {
                palette_index = static_cast<int>(i);
                return;
            }
    }
};

} // namespace phos

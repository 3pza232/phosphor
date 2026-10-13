#include "pack/content_library.hpp"

#include "core/config.hpp"
#include "pack/builtin.hpp"

namespace phos {

namespace {

// 内容目录：用户区优先，出厂区兜底（查找顺序见 content-packs.md）。
// 放在内容库自己的翻译单元里：这几个常量回答的是"内容在哪"，是内容库的知识
constexpr const char* kUserSkinDir = "theme/skin";
constexpr const char* kUserPaletteDir = "theme/palette";
constexpr const char* kUserBootDir = "theme/boot";
constexpr const char* kUserSoundDir = "theme/sound";
constexpr const char* kFactorySkinDir = "system/skin";
constexpr const char* kFactoryPaletteDir = "system/palette";
constexpr const char* kFactoryBootDir = "system/boot";
constexpr const char* kFactorySoundDir = "system/sound";

/// 按 id 定位：找不到返回 0（各列表的 [0] 都是兜底项，永远有效）
template <typename T, typename IdOf>
int index_of_id(const std::vector<T>& items, const std::string& id, IdOf id_of) {
    for (std::size_t i = 0; i < items.size(); ++i)
        if (id_of(items[i]) == id) return static_cast<int>(i);
    return 0;
}

} // namespace

void ContentLibrary::scan(const Config& config) {
    // 色板：先塞兜底，再叠用户区、出厂区
    palettes.push_back(raw_palette());
    merge_packs(palettes, scan_palettes(kUserPaletteDir));
    merge_packs(palettes, scan_palettes(kFactoryPaletteDir));
    palette_index = 0;  // 先指向兜底；主题在 resolve_palette 里解

    skins = scan_skins(kUserSkinDir);
    merge_packs(skins, scan_skins(kFactorySkinDir));
    if (skins.empty()) skins.push_back(builtin_skin());
    skin_index = index_of_id(skins, config.skin, [](const Skin& s) { return s.id; });

    boots = scan_boots(kUserBootDir);
    merge_packs(boots, scan_boots(kFactoryBootDir));
    boot_index = index_of_id(boots, config.boot, [](const BootPack& b) { return b.id; });

    sounds.push_back(silent_sound_pack());
    merge_packs(sounds, scan_sounds(kUserSoundDir));
    merge_packs(sounds, scan_sounds(kFactorySoundDir));
    sound_index = index_of_id(sounds, config.sound, [](const SoundPack& s) { return s.id; });
}

} // namespace phos

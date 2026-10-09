#include "pack/builtin.hpp"

namespace phos {

Palette raw_filter() {
    Palette palette = builtin_palette();
    palette.id = "none";
    palette.name = "NONE (RAW)";
    palette.scan_strength = 0.0f;
    palette.tint = Color{255, 255, 255};
    return palette;
}

SoundPack silent_sound_pack() {
    SoundPack pack;
    pack.id = "silent";
    pack.name = "SILENT";
    return pack;
}

} // namespace phos

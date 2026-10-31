#include "app/sound_state.hpp"

#include "core/audio.hpp"
#include "core/defaults.hpp"
#include "pack/content_library.hpp"

#include <filesystem>
#include <fstream>
#include <sstream>
#include <string>

namespace phos {

namespace {

/// 主机事件音的声部优先级：错误反馈最高；确认/插拔/开机次之；按键音是氛围级。
/// 池被卡带音效压满时，至少不会把"操作失败"这种关键反馈丢掉
int host_event_priority(const std::string& event) {
    if (event == "error") return kPriorityCritical;
    if (event == "confirm" || event == "insert" || event == "eject" || event == "boot")
        return kPrioritySfx;
    return kPriorityMin;
}

} // namespace

void SoundState::play_event(const std::string& event, const ContentLibrary& packs,
                            const CartFiles* asset_gate, Audio& audio) {
    if (packs.sounds.empty()) return;
    const SoundPack& pack = packs.sounds[static_cast<size_t>(packs.sound_index)];
    const int priority = host_event_priority(event);

    if (auto it = pack.files.find(event); it != pack.files.end()) {
        const int handle = sample_handle_for(pack, event, it->second, asset_gate, audio);
        if (handle > 0) {
            audio.play_sample(handle, 0.9f, false, priority, AudioBus::ui);
            return;
        }
    }
    if (auto tone = pack.tones.find(event); tone != pack.tones.end()) {
        ToneSpec spec = tone->second;
        if (spec.priority < priority) spec.priority = priority;
        audio.play_tone(spec, AudioBus::ui);
    }
}

int SoundState::sample_handle_for(const SoundPack& pack, const std::string& event,
                                  const std::string& path, const CartFiles* asset_gate,
                                  Audio& audio) {
    const std::string key = pack.id + ":" + event;
    if (auto it = cache_.find(key); it != cache_.end()) return it->second;

    int handle = 0;
    if (asset_gate) {
        // 音效包的音频文件：按包目录读取（此处 path 相对包目录）。
        // 读之前**先看大小**：与卡带素材同一道闸，不把天量文件读进内存再交给解码器
        const std::string file = pack.dir + "/" + path;
        std::error_code ec;
        const auto on_disk = std::filesystem::file_size(file, ec);
        if (!ec && on_disk <= kMaxAssetBytes) {
            std::ifstream in(file, std::ios::binary);
            if (in) {
                std::ostringstream ss;
                ss << in.rdbuf();
                handle = audio.load_sample(key, ss.str());
            }
        }
    }
    cache_[key] = handle;
    return handle;
}

void SoundState::apply_music_volume(Audio& audio, int percent) {
    audio.set_music_volume(static_cast<float>(percent) / 100.0f);
}

void SoundState::apply_sfx_volume(Audio& audio, int percent) {
    audio.set_sfx_volume(static_cast<float>(percent) / 100.0f);
}

void SoundState::apply_volumes(Audio& audio, int music_percent, int sfx_percent) {
    apply_music_volume(audio, music_percent);
    apply_sfx_volume(audio, sfx_percent);
}

} // namespace phos

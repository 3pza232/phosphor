#pragma once

#include <map>
#include <string>

namespace phos {

class Audio;
class CartFiles;
struct ContentLibrary;
struct SoundPack;

/// 主机事件音与采样缓存（S1 阶段四从 App 抽出的内聚子系统）。
/// 只负责：事件 → 音效包（按 ContentLibrary::sound_index）→ 采样缓存 / 合成音触发，
/// 以及把配置里的音量百分比推给 Audio。
/// 不持有 ContentLibrary/Audio（按引用注入），也不做包索引与配置持久化——那些仍归 App。
class SoundState {
public:
    /// 播放主机事件音（boot / insert / eject / confirm / key / error …）：
    /// 音效包优先用包内音频文件，取不到再回落合成音；两者都走 UI 总线并带事件优先级
    void play_event(const std::string& event, const ContentLibrary& packs,
                    const CartFiles* asset_gate, Audio& audio);

    /// 取（并缓存）事件采样句柄：asset_gate 为空 = 当前没有可读的卡带包资源，
    /// 与旧 App::sample_handle_for 的 host_.cart_files 判空同一道闸（决定是否真去读盘解码）
    int sample_handle_for(const SoundPack& pack, const std::string& event,
                          const std::string& path, const CartFiles* asset_gate, Audio& audio);

    /// 音效包切换 / 换卡带时清空解码句柄缓存（旧包句柄随旧包失效）
    void clear_cache() { cache_.clear(); }

    /// 配置百分比（0..100）→ Audio 音量：初始化时两个都推，设置里只推改动的那一个
    void apply_music_volume(Audio& audio, int percent);
    void apply_sfx_volume(Audio& audio, int percent);
    void apply_volumes(Audio& audio, int music_percent, int sfx_percent);

private:
    std::map<std::string, int> cache_;  // "包 id:事件" → 解码句柄（0 = 解码失败也缓存）
};

} // namespace phos

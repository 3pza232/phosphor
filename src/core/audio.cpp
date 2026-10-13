#include "core/audio.hpp"

#include "core/log.hpp"

#define MINIAUDIO_IMPLEMENTATION
#include <miniaudio.h>

#include <algorithm>
#include <cmath>
#include <cstring>

namespace phos {

namespace {

constexpr int kMaxVoices = 48;
constexpr float kTwoPi = 6.2831853f;
constexpr float kMusicNoteVolume = 0.22f;  // 音序器单音音量（多轨叠加后的基准）
constexpr int kSemitoneA4 = 69;
constexpr float kFreqA4 = 440.0f;

/// 音量夹到 0..1；非有限值（NaN / ±inf）当 0 处理。
/// `std::clamp` 遇到 NaN 会**原样返回**，一个坏音量会污染整条混音，所以统一走这里
float clamp01(float v) { return std::isfinite(v) ? std::clamp(v, 0.0f, 1.0f) : 0.0f; }

/// 半音相对 A4 的频率
float semitone_freq(int midi_note) {
    return kFreqA4 * std::pow(2.0f, static_cast<float>(midi_note - kSemitoneA4) / 12.0f);
}

int note_name_to_midi(const std::string& note) {
    if (note.size() < 2) return -1;
    static const int kBase[] = {9, 11, 0, 2, 4, 5, 7};  // A B C D E F G
    char letter = note[0];
    int index = -1;
    switch (letter) {
        case 'C': case 'c': index = 2; break;
        case 'D': case 'd': index = 3; break;
        case 'E': case 'e': index = 4; break;
        case 'F': case 'f': index = 5; break;
        case 'G': case 'g': index = 6; break;
        case 'A': case 'a': index = 0; break;
        case 'B': case 'b': index = 1; break;
        default: return -1;
    }
    int semitone = kBase[index];
    size_t pos = 1;
    if (note[pos] == '#') {
        ++semitone;
        ++pos;
    } else if (note[pos] == 'b') {
        --semitone;
        ++pos;
    }
    if (pos >= note.size()) return -1;
    int octave = 0;
    for (; pos < note.size(); ++pos) {
        if (note[pos] < '0' || note[pos] > '9') return -1;
        octave = octave * 10 + (note[pos] - '0');
    }
    // MIDI: C4 = 60 → 八度 4 的 C
    return (octave + 1) * 12 + semitone;
}

} // namespace

float note_to_freq(const std::string& note) {
    const int midi = note_name_to_midi(note);
    if (midi < 0 || midi > 127) return 0.0f;
    return semitone_freq(midi);
}

Wave wave_from_name(const std::string& name) {
    if (name == "sine") return Wave::sine;
    if (name == "triangle") return Wave::triangle;
    if (name == "saw") return Wave::saw;
    if (name == "noise") return Wave::noise;
    return Wave::square;
}

bool percussion_spec(char token, ToneSpec& out) {
    switch (token) {
        case 'K':  // 底鼓：低频下扫
            out.wave = Wave::sine;
            out.freq = 120.0f;
            out.freq_end = 45.0f;
            out.dur = 0.14f;
            out.volume = 0.55f;
            out.release = 0.10f;
            return true;
        case 'S':  // 军鼓：噪声短促
            out.wave = Wave::noise;
            out.dur = 0.12f;
            out.volume = 0.35f;
            out.release = 0.09f;
            return true;
        case 'H':  // 踩镲：极短噪声
            out.wave = Wave::noise;
            out.dur = 0.04f;
            out.volume = 0.20f;
            out.release = 0.03f;
            return true;
        default:
            return false;
    }
}

// ---------------------------------------------------------------- 内部结构

struct Audio::Sample {
    std::vector<float> pcm;  // 交错立体声
    uint64_t frames = 0;
};

struct Audio::Voice {
    bool active = false;
    bool is_sample = false;
    bool is_music = false;  // 归属音乐轨（音量与音效独立）

    // 合成
    Wave wave = Wave::square;
    float phase = 0.0f;
    float phase_inc = 0.0f;
    float freq = 440.0f;
    float freq_end = 0.0f;
    float t = 0.0f;
    float dur = 0.1f;
    float attack = 0.004f;
    float release = 0.05f;
    float volume = 0.3f;
    uint32_t noise_state = 0x1234567u;

    // 采样
    const Sample* sample = nullptr;
    uint64_t pos = 0;
    bool loop = false;
    int sample_handle = 0;
};

// ---------------------------------------------------------------- 生命周期

Audio::Audio() = default;
Audio::~Audio() { shutdown(); }

bool Audio::init(std::string& err) {
    context_ = std::make_unique<ma_context>();
    if (ma_context_init(nullptr, 0, nullptr, context_.get()) != MA_SUCCESS) {
        context_.reset();
        err = "audio context init failed";
        return false;
    }

    device_ = std::make_unique<ma_device>();
    ma_device_config config = ma_device_config_init(ma_device_type_playback);
    config.playback.pDeviceID = nullptr;
    config.playback.format = ma_format_f32;
    config.playback.channels = 2;
    config.sampleRate = 0;  // 设备原生采样率
    config.dataCallback = &Audio::data_callback;
    config.pUserData = this;

    if (ma_device_init(context_.get(), &config, device_.get()) != MA_SUCCESS) {
        device_.reset();
        context_.reset();
        err = "audio device init failed";
        return false;
    }
    sample_rate_ = static_cast<int>(device_->sampleRate);
    if (sample_rate_ <= 0) sample_rate_ = 48000;

    voices_.reserve(kMaxVoices);
    for (int i = 0; i < kMaxVoices; ++i) voices_.push_back(std::make_unique<Voice>());

    if (ma_device_start(device_.get()) != MA_SUCCESS) {
        ma_device_uninit(device_.get());
        device_.reset();
        context_.reset();
        err = "audio device start failed";
        return false;
    }

    active_ = true;
    return true;
}

void Audio::shutdown() {
    if (device_) {
        // 这里会等音频回调收尾：日志停在这行说明设备后端没把回调线程放开
        log::info("audio: stopping device");
        ma_device_uninit(device_.get());
        device_.reset();
        log::info("audio: device stopped");
    }
    if (context_) {
        ma_context_uninit(context_.get());
        context_.reset();
    }
    voices_.clear();
    sample_table_.clear();  // 混音线程已停：此时清样本表是安全的
    sample_names_.clear();
    active_ = false;
}

void Audio::set_master_volume(float volume) {
    if (!std::isfinite(volume)) return;  // NaN/±inf：忽略，保住当前值，别污染混音
    master_volume_.store(std::clamp(volume, 0.0f, 1.0f));
}

void Audio::set_music_volume(float volume) {
    if (!std::isfinite(volume)) return;
    music_volume_.store(std::clamp(volume, 0.0f, 1.0f));
}

void Audio::set_sfx_volume(float volume) {
    if (!std::isfinite(volume)) return;
    sfx_volume_.store(std::clamp(volume, 0.0f, 1.0f));
}

void Audio::set_paused(bool paused) {
    paused_.store(paused);
}

int TunePattern::rows() const {
    int count = 0;
    for (const auto& track : tracks)
        count = std::max(count, static_cast<int>(track.steps.size()));
    return count;
}

// ---------------------------------------------------------------- 播放接口

bool Audio::push(Request&& request) {
    if (!active_) return false;  // 无设备：不积压请求
    const size_t head = queue_head_.load(std::memory_order_relaxed);
    const size_t tail = queue_tail_.load(std::memory_order_acquire);
    if (head - tail >= kRequestQueue) {
        ++dropped_;  // 队列满：宁可少一声，也不阻塞游戏循环
        return false;
    }
    queue_[head % kRequestQueue] = std::move(request);
    queue_head_.store(head + 1, std::memory_order_release);
    return true;
}

/// 把音加进声部表。仅音频线程调用，因此不需要任何同步。
void Audio::spawn_voice(const ToneSpec& spec, bool music) {
    for (auto& voice : voices_) {
        if (voice->active) continue;
        voice->active = true;
        voice->is_sample = false;
        voice->is_music = music;
        voice->wave = spec.wave;
        voice->freq = spec.freq;
        voice->freq_end = spec.freq_end;
        voice->dur = std::max(0.01f, spec.dur);
        voice->attack = std::max(0.0f, spec.attack);
        voice->release = std::max(0.01f, spec.release);
        voice->volume = clamp01(spec.volume);
        voice->t = 0.0f;
        voice->phase = 0.0f;
        voice->sample = nullptr;
        return;
    }
    // 声部用尽：丢弃本次触发（宁可静音也不卡音频线程）
}

void Audio::spawn_voice_note(const std::string& note, const ToneSpec& base, bool music) {
    const float freq = note_to_freq(note);
    if (freq <= 0.0f) return;
    ToneSpec spec = base;
    spec.freq = freq;
    spec.freq_end = 0.0f;
    spawn_voice(spec, music);
}

void Audio::play_tone(const ToneSpec& spec) {
    Request request;
    request.kind = Request::Kind::tone;
    request.spec = spec;
    push(std::move(request));
}

void Audio::play_note(const std::string& note, const ToneSpec& base) {
    Request request;
    request.kind = Request::Kind::note;
    request.note = note;
    request.spec = base;
    push(std::move(request));
}

void Audio::play_percussion(char token) {
    ToneSpec spec;
    if (percussion_spec(token, spec)) play_tone(spec);
}

void Audio::play_tune(const Tune& tune) {
    if (!active_) return;
    order_names_ = tune.order;  // 主线程侧留一份名字，供状态查询显示
    Request request;
    request.kind = Request::Kind::tune;
    request.tune = std::make_unique<Tune>(tune);
    push(std::move(request));
}

std::string Audio::music_section() const {
    if (!music_on_.load()) return {};
    const size_t index = order_index_.load();
    if (index >= order_names_.size()) return {};
    return order_names_[index];
}

void Audio::stop_music() {
    Request request;
    request.kind = Request::Kind::silence_music;
    push(std::move(request));
}

void Audio::stop_all() {
    Request request;
    request.kind = Request::Kind::stop_all;
    push(std::move(request));
}

void Audio::apply(Request& request) {
    switch (request.kind) {
        case Request::Kind::tone:
            spawn_voice(request.spec, request.music);
            break;
        case Request::Kind::note:
            spawn_voice_note(request.note, request.spec, request.music);
            break;
        case Request::Kind::register_sample:
            // 采样数据在这里**移交**给音频线程：此后只有音频线程持有它，
            // 回调侧读样本因此不需要任何同步（寿命由 sample_table_ 决定）
            if (request.sample) sample_table_.push_back(std::move(request.sample));
            break;
        case Request::Kind::sample: {
            const Sample* sample =
                (request.handle > 0 && request.handle <= static_cast<int>(sample_table_.size()))
                    ? sample_table_[static_cast<size_t>(request.handle - 1)].get()
                    : nullptr;
            if (!sample) break;
            for (auto& voice : voices_) {
                if (voice->active) continue;
                voice->active = true;
                voice->is_sample = true;
                voice->is_music = false;  // 采样走**音效**音量：声部会复用，不写就会继承上一支的 music 标记
                voice->sample = sample;
                voice->pos = 0;
                voice->loop = request.loop;
                voice->volume = clamp01(request.volume);
                voice->sample_handle = request.handle;
                break;
            }
            break;
        }
        case Request::Kind::stop_sample:
            for (auto& voice : voices_)
                if (voice->active && voice->is_sample && voice->sample_handle == request.handle)
                    voice->active = false;
            break;
        case Request::Kind::stop_all:
            for (auto& voice : voices_) voice->active = false;
            [[fallthrough]];
        case Request::Kind::silence_music:
            music_on_ = false;
            pattern_ = nullptr;
            step_ = 0;
            step_timer_ = 0.0f;
            tune_ = Tune{};
            break;
        case Request::Kind::tune:
            if (request.tune) {
                tune_ = std::move(*request.tune);
                order_index_ = 0;
                step_ = 0;
                step_timer_ = 0.0f;
                pattern_ = nullptr;
                music_on_ = advance_pattern();
            }
            break;
    }
}

void Audio::drain_requests() {
    size_t tail = queue_tail_.load(std::memory_order_relaxed);
    const size_t head = queue_head_.load(std::memory_order_acquire);
    while (tail != head) {
        Request& request = queue_[tail % kRequestQueue];
        apply(request);
        request.tune.reset();    // 取走持有的资源，槽位归零
        request.sample.reset();
        ++tail;
        queue_tail_.store(tail, std::memory_order_release);
    }
}

int Audio::load_sample(const std::string& name, const std::string& bytes) {
    if (!active_ || bytes.empty()) return 0;

    for (size_t i = 0; i < sample_names_.size(); ++i)
        if (sample_names_[i] == name) return static_cast<int>(i) + 1;

    ma_decoder_config config =
        ma_decoder_config_init(ma_format_f32, 2, static_cast<ma_uint32>(sample_rate_));
    ma_decoder decoder;
    if (ma_decoder_init_memory(bytes.data(), bytes.size(), &config, &decoder) != MA_SUCCESS)
        return 0;

    ma_uint64 frame_count = 0;
    if (ma_decoder_get_length_in_pcm_frames(&decoder, &frame_count) != MA_SUCCESS ||
        frame_count == 0) {
        ma_decoder_uninit(&decoder);
        return 0;
    }
    // 解码后的 PCM 体积也要设上限：压缩文件（或伪造的长度）可能解出天量样本，
    // 8 MiB 的**编码**上限拦不住它（见 roadmap 第 8 条的精神）
    constexpr ma_uint64 kMaxDecodedBytes = 32ull * 1024 * 1024;
    if (frame_count * 2 * sizeof(float) > kMaxDecodedBytes) {
        log::warn("sample too large, refusing to decode: " + name);
        ma_decoder_uninit(&decoder);
        return 0;
    }

    auto sample = std::make_unique<Sample>();
    sample->pcm.resize(static_cast<size_t>(frame_count) * 2);
    ma_uint64 read = 0;
    if (ma_decoder_read_pcm_frames(&decoder, sample->pcm.data(), frame_count, &read) !=
            MA_SUCCESS ||
        read == 0) {  // 一帧都没读到：当无效——否则空 PCM 遇上 loop 会越界读
        ma_decoder_uninit(&decoder);
        return 0;
    }
    sample->frames = read;
    sample->pcm.resize(static_cast<size_t>(read) * 2);
    ma_decoder_uninit(&decoder);

    // 句柄 = 登记序号（1 基）。数据本体移交给音频线程，名字留在主机侧供下次去重
    const int handle = static_cast<int>(sample_names_.size()) + 1;
    Request request;
    request.kind = Request::Kind::register_sample;
    request.sample = std::move(sample);
    if (!push(std::move(request))) return 0;  // 队列满：本次登记作废，不占句柄
    sample_names_.push_back(name);
    return handle;
}

void Audio::play_sample(int handle, float volume, bool loop) {
    if (handle <= 0 || handle > static_cast<int>(sample_names_.size())) return;
    Request request;
    request.kind = Request::Kind::sample;
    request.handle = handle;
    request.volume = volume;
    request.loop = loop;
    push(std::move(request));
}

void Audio::stop_sample(int handle) {
    Request request;
    request.kind = Request::Kind::stop_sample;
    request.handle = handle;
    push(std::move(request));
}

// ---------------------------------------------------------------- 混音

bool Audio::advance_pattern() {
    while (order_index_ < tune_.order.size()) {
        const std::string& name = tune_.order[order_index_];
        for (const auto& pattern : tune_.patterns) {
            if (pattern.name != name) continue;
            pattern_ = &pattern;
            rows_ = pattern.rows();
            last_note_.assign(pattern.tracks.size(), std::string());  // 延音不跨乐段
            if (rows_ > 0) return true;
            break;
        }
        ++order_index_;  // 空乐段或未找到：跳到下一项
    }
    return false;
}

void Audio::advance_sequencer(uint32_t frames) {
    if (!music_on_ || !pattern_) return;

    // 一行 = 十六分音符
    const float step_dur = 60.0f / std::max(20.0f, tune_.bpm) / 4.0f;
    step_timer_ += static_cast<float>(frames) / static_cast<float>(sample_rate_);

    while (step_timer_ >= step_dur) {
        step_timer_ -= step_dur;

        for (size_t index = 0; index < pattern_->tracks.size(); ++index) {
            const TuneTrack& track = pattern_->tracks[index];
            if (track.steps.empty()) continue;
            const std::string& token = track.steps[static_cast<size_t>(step_) % track.steps.size()];
            if (token.empty() || token == "-") continue;

            if (token[0] == '=') {
                // 延音：延续本轨上一个音，时值拉长、力度略降（像按键延续）
                if (last_note_.size() <= index) continue;
                const std::string& held = last_note_[index];
                if (held.empty()) continue;
                ToneSpec spec;
                spec.wave = track.custom_wave ? track.wave : tune_.wave;
                spec.dur = step_dur * 4.0f;
                spec.volume = kMusicNoteVolume * track.volume * 0.85f;
                spec.attack = track.attack;
                spec.release = track.release * 2.0f;
                spawn_voice_note(held, spec, /*music=*/true);
                continue;
            }

            ToneSpec spec;
            spec.volume = kMusicNoteVolume * track.volume;
            spec.attack = track.attack;
            spec.release = track.release;
            if (token.size() == 1 && percussion_spec(token[0], spec)) {
                spec.volume *= track.volume;  // 打击乐同样受轨道音量控制
                spawn_voice(spec, /*music=*/true);
                continue;
            }

            spec.wave = track.custom_wave ? track.wave : tune_.wave;
            spec.dur = step_dur * 1.9f;  // 音符略长于一步，形成连音
            if (last_note_.size() <= index) last_note_.resize(index + 1);
            last_note_[index] = token;
            spawn_voice_note(token, spec, /*music=*/true);
        }

        ++step_;
        if (step_ >= rows_) {
            step_ = 0;
            ++order_index_;
            if (!advance_pattern()) {  // order 耗尽
                if (tune_.loop) {
                    order_index_ = 0;
                    if (!advance_pattern()) music_on_ = false;
                } else {
                    music_on_ = false;
                    break;
                }
            }
        }
    }
}

void Audio::mix(float* out, uint32_t frames) {
    std::memset(out, 0, sizeof(float) * frames * 2);

    // 暂停：输出静音但不推进任何状态，恢复后原地续播
    if (paused_.load()) return;

    // 音频线程是声部表唯一的写入者：先落地主线程排队的触发，再推进音序器
    drain_requests();
    advance_sequencer(frames);
    int playing = 0;
    for (const auto& voice : voices_)
        if (voice->active) ++playing;
    active_voices_ = playing;

    const float master = master_volume_.load();
    const float music_gain = music_volume_.load();
    const float sfx_gain = sfx_volume_.load();
    const float dt = 1.0f / static_cast<float>(sample_rate_);

    auto gain_of = [music_gain, sfx_gain](const Voice& voice) {
        return voice.is_music ? music_gain : sfx_gain;
    };

    for (auto& voice_ptr : voices_) {
        Voice& voice = *voice_ptr;
        if (!voice.active) continue;

        if (voice.is_sample) {
            if (!voice.sample) {
                voice.active = false;
                continue;
            }
            const uint64_t total = voice.sample->frames;
            for (uint32_t i = 0; i < frames; ++i) {
                if (voice.pos >= total) {
                    if (voice.loop) voice.pos = 0;
                    else {
                        voice.active = false;
                        break;
                    }
                }
                const float left = voice.sample->pcm[static_cast<size_t>(voice.pos) * 2];
                const float right = voice.sample->pcm[static_cast<size_t>(voice.pos) * 2 + 1];
                const float gain = master * gain_of(voice);
                out[i * 2] += left * voice.volume * gain;
                out[i * 2 + 1] += right * voice.volume * gain;
                ++voice.pos;
            }
            continue;
        }

        // 合成音：包络 = 起振 + 保持 + 释放
        for (uint32_t i = 0; i < frames; ++i) {
            if (voice.t >= voice.dur) {
                voice.active = false;
                break;
            }

            float envelope = 1.0f;
            if (voice.t < voice.attack && voice.attack > 0.0f)
                envelope = voice.t / voice.attack;
            const float release_start = std::max(0.0f, voice.dur - voice.release);
            if (voice.t > release_start)
                envelope *= std::max(0.0f, (voice.dur - voice.t) / voice.release);

            float freq = voice.freq;
            if (voice.freq_end > 0.0f) {
                const float progress = voice.dur > 0.0f ? voice.t / voice.dur : 1.0f;
                freq = voice.freq + (voice.freq_end - voice.freq) * progress;
            }
            voice.phase_inc = freq / static_cast<float>(sample_rate_);

            float value = 0.0f;
            switch (voice.wave) {
                case Wave::sine: value = std::sin(voice.phase * kTwoPi); break;
                case Wave::square: value = voice.phase < 0.5f ? 1.0f : -1.0f; break;
                case Wave::triangle:
                    value = voice.phase < 0.5f ? (voice.phase * 4.0f - 1.0f)
                                              : (3.0f - voice.phase * 4.0f);
                    break;
                case Wave::saw: value = voice.phase * 2.0f - 1.0f; break;
                case Wave::noise: {
                    voice.noise_state = voice.noise_state * 1664525u + 1013904223u;
                    value = static_cast<float>(voice.noise_state >> 8) / 8388608.0f - 1.0f;
                    break;
                }
            }

            voice.phase += voice.phase_inc;
            if (voice.phase >= 1.0f) voice.phase -= 1.0f;
            voice.t += dt;

            const float sample = value * envelope * voice.volume * master * gain_of(voice);
            out[i * 2] += sample;
            out[i * 2 + 1] += sample;
        }
    }

    // 软限幅，避免叠加削波爆音
    for (uint32_t i = 0; i < frames * 2; ++i)
        out[i] = std::tanh(out[i]);
}

void Audio::data_callback(ma_device* device, void* output, const void*, uint32_t frame_count) {
    auto* self = static_cast<Audio*>(device->pUserData);
    self->mix(static_cast<float*>(output), frame_count);
}

} // namespace phos

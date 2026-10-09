#pragma once

#include "core/defaults.hpp"

#include <array>
#include <atomic>
#include <cstdint>
#include <map>
#include <memory>
#include <string>
#include <vector>

struct ma_device;
struct ma_context;

namespace phos {

/// 合成波形
enum class Wave { sine, square, triangle, saw, noise };

/// 合成音描述：卡带音效、主机事件音、音序器音符共用同一种表达
struct ToneSpec {
    Wave wave = Wave::square;
    float freq = 440.0f;      // 起始频率（Hz）
    float freq_end = 0.0f;    // > 0 时线性扫频到该频率（坠落音、上升音）
    float dur = 0.10f;        // 总时长（含释放段）
    float volume = 0.35f;     // 0..1
    float attack = 0.004f;    // 起振
    float release = 0.05f;    // 释放
};

/// 音序器轨道。每格为一个记号：
///   音符 "C4" / "F#3"、"`-`" 休止、"`=`" 延音（延续上一个音）、
///   打击乐 "K"（底鼓）/ "S"（军鼓）/ "H"（踩镲）
/// 轨道可自带音色（波形/音量/包络）——柔和的低音用 triangle、旋律用 square 等。
struct TuneTrack {
    std::string name;
    std::vector<std::string> steps;
    bool custom_wave = false;      // 是否显式指定波形（否则跟随 Tune::wave）
    Wave wave = Wave::square;
    float volume = 1.0f;           // 相对音量（乘在音符基准音量上）
    float attack = 0.008f;         // 起振：稍慢更圆润
    float release = 0.10f;         // 释放：给音符留尾巴，避免断奏的生硬感
};

/// 乐段（pattern）：一组同名轨道，作为曲式的构建块
struct TunePattern {
    std::string name;
    std::vector<TuneTrack> tracks;
    int rows() const;
};

/// 卡带自带音乐：文本记谱 + 曲式（pattern 序列），随卡带包分发（可被 mod 覆盖）。
/// 长曲子（两分钟级）靠 patterns + order 组合而成，无需把谱面写成一条长龙。
struct Tune {
    float bpm = 120.0f;
    Wave wave = Wave::square;
    bool loop = true;
    std::vector<TunePattern> patterns;
    std::vector<std::string> order;   // pattern 名序列；每项播放一遍该乐段
};

/// 音频子系统：纯软件混音 + miniaudio 输出设备。
/// 设备初始化失败时整机静音运行（所有调用安全降级），绝不因此中断主机。
class Audio {
public:
    Audio();
    ~Audio();
    Audio(const Audio&) = delete;
    Audio& operator=(const Audio&) = delete;

    /// 打开输出设备并启动混音线程；失败返回 false 并填 err，此后整机静音运行
    bool init(std::string& err);
    /// 停止混音线程并释放设备（析构自动调用）
    void shutdown();
    bool active() const { return active_; }

    /// 主音量（0..1），音乐与音效各自的音量在此之上独立调节
    void set_master_volume(float volume);
    float master_volume() const { return master_volume_.load(); }

    /// 音乐音量（音序器产出）
    void set_music_volume(float volume);
    float music_volume() const { return music_volume_.load(); }

    /// 暂停/恢复全部声音（音乐随之暂停并原地续播，用于游戏暂停）
    void set_paused(bool paused);
    bool paused() const { return paused_.load(); }

    /// 音效音量（beep / note / perc / 采样）
    void set_sfx_volume(float volume);
    float sfx_volume() const { return sfx_volume_.load(); }

    // --- 即时音（主线程只入队，不触碰声部表） ---
    /// 一条合成音：波形/频率/包络由 ToneSpec 给出
    void play_tone(const ToneSpec& spec);
    /// 单个音符（"C4" 等），名字无法识别时静默
    void play_note(const std::string& note, const ToneSpec& base);
    /// 一个打击音：token 由音效包定义（'K' 底鼓、'S' 军鼓等）
    void play_percussion(char token);

    // --- 音乐 ---
    /// 开始播放一段曲子：按 tune.order 依次播放乐段，loop 为真则循环
    void play_tune(const Tune& tune);
    /// 停止音乐（乐段位置与步进一起复位，下次从头开始）
    void stop_music();

    /// 音乐是否在播（无音频设备时恒为 false）。
    /// 音序器跑在音频线程上，这里读的是原子快照。
    bool music_on() const { return music_on_.load(); }
    /// 当前乐段序号（0 基）与乐段总数；不在播时为 0
    int music_section_index() const {
        return music_on_.load() ? static_cast<int>(order_index_.load()) : 0;
    }
    int music_section_count() const { return static_cast<int>(order_names_.size()); }
    /// 当前乐段名（不在播或无名时为空）
    std::string music_section() const;

    // --- 采样（卡带包内的音频文件，内存解码） ---
    /// 解码并登记（同名重复登记返回既有句柄）。失败返回 0。
    int load_sample(const std::string& name, const std::string& bytes);
    void play_sample(int handle, float volume, bool loop);
    void stop_sample(int handle);

    void stop_all();

    /// 活跃声部数（诊断用；读到的可能落后一块混音）
    int active_voices() const { return active_voices_.load(); }
    /// 因请求队列满而被丢弃的触发数：宁可少一声，也不阻塞游戏循环
    size_t dropped_requests() const { return dropped_.load(); }

private:
    struct Voice;
    struct Sample;

    static void data_callback(ma_device* device, void* output, const void* input,
                              uint32_t frame_count);
    void mix(float* out, uint32_t frames);

    /// 主线程 → 音频线程的触发请求。
    ///
    /// 分工：**主线程只入队，绝不触碰声部表**；音频线程是声部表的唯一写入者，
    /// 每块混音开始前整批取走。于是既不需要锁，游戏循环也不会为"发一个音"
    /// 而等待音频线程——音频回调偶尔跑得久，也只是晚几十毫秒出声。
    struct Request {
        enum class Kind {
            tone,
            note,
            sample,
            register_sample,
            stop_sample,
            stop_all,
            tune,
            silence_music
        };
        Kind kind = Kind::tone;
        ToneSpec spec{};
        std::string note;
        bool music = false;
        int handle = 0;
        float volume = 1.0f;
        bool loop = false;
        std::unique_ptr<Tune> tune;      // Kind::tune 时携带
        std::unique_ptr<Sample> sample;  // Kind::register_sample 时携带（所有权交给音频线程）
    };
    static constexpr size_t kRequestQueue = 64;
    bool push(Request&& request);  // 队列入参；满则计数丢弃
    void drain_requests();         // 音频线程侧：取走并应用全部请求
    void apply(Request& request);  // 音频线程侧：单个请求落地

    /// 把音加进声部表（仅音频线程调用：请求队列与音序器共用同一套落地逻辑）
    void spawn_voice(const ToneSpec& spec, bool music);
    void spawn_voice_note(const std::string& note, const ToneSpec& base, bool music);

    void advance_sequencer(uint32_t frames);
    /// 进入下一个乐段（order 推进）；order 耗尽且不循环时停止音乐
    bool advance_pattern();

    std::unique_ptr<ma_context> context_;
    std::unique_ptr<ma_device> device_;
    bool active_ = false;
    int sample_rate_ = 48000;

    std::vector<std::unique_ptr<Voice>> voices_;

    // 采样登记分两侧：主线程独占名字表（去重 + 句柄编号），数据本体经请求队列
    // 移交给音频线程后只由音频线程持有——回调侧读样本因此不需要锁，也不会与
    // 主线程的追加撞车（追加会让 vector 重分配，而回调正拿着里面的裸指针）。
    // 句柄在音频子系统存活期间一直有效：登记即常驻，不做回收。
    std::vector<std::string> sample_names_;               // 主线程侧：名字 → 句柄（下标 + 1）
    std::vector<std::unique_ptr<Sample>> sample_table_;   // 音频线程侧：样本本体

    // SPSC 请求队列：head/tail 由各自线程独占写入，用原子发布
    std::array<Request, kRequestQueue> queue_;
    std::atomic<size_t> queue_head_{0};  // 主线程写
    std::atomic<size_t> queue_tail_{0};  // 音频线程写
    std::atomic<size_t> dropped_{0};
    std::atomic<int> active_voices_{0};

    std::atomic<float> master_volume_{0.8f};
    // 与配置默认同源：主机启动时会按用户设置覆盖，这里只是引擎兜底
    std::atomic<float> music_volume_{kDefaultMusicVolume / 100.0f};
    std::atomic<float> sfx_volume_{kDefaultSfxVolume / 100.0f};
    std::atomic<bool> paused_{false};
    Tune tune_;  // 音频线程侧使用
    // 以下音乐状态被音频线程写入、主线程读取（状态查询），故用原子
    std::atomic<bool> music_on_{false};
    std::atomic<size_t> order_index_{0};  // 当前乐段在 order 中的位置
    std::vector<std::string> order_names_;  // 主线程侧副本，仅供状态查询显示
    const TunePattern* pattern_ = nullptr;  // 当前乐段
    int step_ = 0;
    int rows_ = 0;
    float step_timer_ = 0.0f;
    std::vector<std::string> last_note_;  // 每轨最近一个音（供 "=" 延音）
};

/// 音符名（"C4"/"F#3"）→ 频率；非法返回 0
float note_to_freq(const std::string& note);

/// 波形名（"square" 等）→ 枚举；非法返回 square
Wave wave_from_name(const std::string& name);

/// 打击乐记号（'K'/'S'/'H'）→ 合成参数；非法返回 false
bool percussion_spec(char token, ToneSpec& out);

} // namespace phos

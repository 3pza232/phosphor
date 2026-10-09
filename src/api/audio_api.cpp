#include "api/audio_api.hpp"

#include "api/host_api.hpp"
#include "cart/cart_files.hpp"
#include "core/audio.hpp"

#include <sol/sol.hpp>

#include <sstream>
#include <string>
#include <vector>

namespace phos {

namespace {

/// 从 Lua 选项表读取合成音参数（未提供字段沿用 base）
ToneSpec tone_from_table(const sol::object& obj, ToneSpec base) {
    if (!obj.is<sol::table>()) return base;
    sol::table t = obj.as<sol::table>();

    sol::object wave = t["wave"];
    if (wave.is<std::string>()) base.wave = wave_from_name(wave.as<std::string>());

    auto number = [&t](const char* key, float fallback) {
        sol::object v = t[key];
        if (v.is<double>() || v.is<int>()) return v.as<float>();
        return fallback;
    };
    base.freq = number("freq", base.freq);
    base.freq_end = number("sweep", base.freq_end);
    base.dur = number("dur", base.dur);
    base.volume = number("volume", base.volume);
    base.attack = number("attack", base.attack);
    base.release = number("release", base.release);
    return base;
}

/// 谱面：支持表（{"E4","-","G4"}）或空格分隔字符串（"E4 - G4 -"）
std::vector<std::string> step_list(const sol::object& obj) {
    std::vector<std::string> out;
    if (obj.is<std::string>()) {
        std::istringstream stream(obj.as<std::string>());
        std::string token;
        while (stream >> token) out.push_back(token);
        return out;
    }
    if (!obj.is<sol::table>()) return out;
    sol::table t = obj.as<sol::table>();
    for (size_t i = 1; i <= t.size(); ++i) {
        sol::object v = t[i];
        out.push_back(v.is<std::string>() ? v.as<std::string>() : std::string("-"));
    }
    return out;
}

/// 轨道：可直接给谱面（字符串/表），也可给带音色的表
/// { wave="triangle", volume=0.7, attack=0.01, release=0.2, steps="E2 - - -" }
TuneTrack track_from_object(const std::string& name, const sol::object& obj) {
    TuneTrack track;
    track.name = name;

    if (obj.is<sol::table>()) {
        sol::table spec = obj.as<sol::table>();
        if (sol::object steps = spec["steps"]; steps.get_type() != sol::type::nil) {
            track.steps = step_list(steps);
            if (sol::object wave = spec["wave"]; wave.is<std::string>()) {
                track.wave = wave_from_name(wave.as<std::string>());
                track.custom_wave = true;
            }
            auto number = [&spec](const char* key, float fallback) {
                sol::object v = spec[key];
                if (v.is<double>() || v.is<int>()) return v.as<float>();
                return fallback;
            };
            track.volume = number("volume", track.volume);
            track.attack = number("attack", track.attack);
            track.release = number("release", track.release);
            return track;
        }
    }
    track.steps = step_list(obj);  // 简写：整表/字符串即谱面
    return track;
}

TunePattern pattern_from_table(const std::string& name, const sol::table& tracks) {
    TunePattern pattern;
    pattern.name = name;
    for (auto& kv : tracks) {
        if (!kv.first.is<std::string>()) continue;
        TuneTrack track = track_from_object(kv.first.as<std::string>(), kv.second);
        if (!track.steps.empty()) pattern.tracks.push_back(std::move(track));
    }
    return pattern;
}

/// Lua 音乐表 → Tune：支持曲式（patterns + order），也兼容单乐段（tracks）
Tune tune_from_table(const sol::table& t) {
    Tune tune;

    sol::object bpm = t["bpm"];
    if (bpm.is<double>() || bpm.is<int>()) tune.bpm = bpm.as<float>();
    sol::object wave = t["wave"];
    if (wave.is<std::string>()) tune.wave = wave_from_name(wave.as<std::string>());
    sol::object loop = t["loop"];
    if (loop.is<bool>()) tune.loop = loop.as<bool>();

    sol::object patterns = t["patterns"];
    if (patterns.is<sol::table>()) {
        for (auto& kv : patterns.as<sol::table>()) {
            if (!kv.first.is<std::string>() || !kv.second.is<sol::table>()) continue;
            tune.patterns.push_back(
                pattern_from_table(kv.first.as<std::string>(), kv.second.as<sol::table>()));
        }
    } else if (sol::object tracks = t["tracks"]; tracks.is<sol::table>()) {
        // 单乐段简写：自动包装为乐段 "A" 并只播放一次
        tune.patterns.push_back(pattern_from_table("A", tracks.as<sol::table>()));
        tune.order.push_back("A");
    }

    sol::object order = t["order"];
    if (order.is<sol::table>()) {
        sol::table ot = order.as<sol::table>();
        for (size_t i = 1; i <= ot.size(); ++i) {
            sol::object v = ot[i];
            if (v.is<std::string>()) tune.order.push_back(v.as<std::string>());
        }
    } else if (tune.order.empty()) {
        // 未给 order：按声明顺序各播放一遍
        for (const auto& pattern : tune.patterns) tune.order.push_back(pattern.name);
    }
    return tune;
}

} // namespace

void register_audio_api(sol::state& lua, HostContext& host) {
    sol::table phos = lua["phos"];
    sol::table audio = phos.create_named("audio");

    audio["available"] = [&host]() { return host.audio && host.audio->active(); };

    // 音量：主 / 音乐 / 音效 三层，均为「传参即设置、返回当前值」
    audio["volume"] = [&host](sol::object value) -> float {
        if (!host.audio) return 0.0f;
        if (value.is<double>() || value.is<int>())
            host.audio->set_master_volume(value.as<float>());
        return host.audio->master_volume();
    };
    audio["music_volume"] = [&host](sol::object value) -> float {
        if (!host.audio) return 0.0f;
        if (value.is<double>() || value.is<int>())
            host.audio->set_music_volume(value.as<float>());
        return host.audio->music_volume();
    };
    audio["sfx_volume"] = [&host](sol::object value) -> float {
        if (!host.audio) return 0.0f;
        if (value.is<double>() || value.is<int>())
            host.audio->set_sfx_volume(value.as<float>());
        return host.audio->sfx_volume();
    };

    // 基础合成音：beep(freq, dur [, opts])
    audio["beep"] = [&host](float freq, float dur, sol::object opts) {
        if (!host.audio) return;
        ToneSpec spec;
        spec.freq = freq;
        spec.dur = dur;
        host.audio->play_tone(tone_from_table(opts, spec));
    };

    // 音符：note("C4" [, opts]) —— 音名写法见文档
    audio["note"] = [&host](const std::string& name, sol::object opts) {
        if (!host.audio) return;
        ToneSpec spec;
        spec.dur = 0.25f;
        host.audio->play_note(name, tone_from_table(opts, spec));
    };

    // 打击乐：perc("K" | "S" | "H")
    audio["perc"] = [&host](const std::string& token) {
        if (!host.audio || token.empty()) return;
        host.audio->play_percussion(token[0]);
    };

    // 音乐：music({ bpm=, wave=, loop=, tracks={ lead={...}, bass={...} } })
    audio["music"] = [&host](sol::table tune) {
        if (!host.audio) return;
        host.audio->play_tune(tune_from_table(tune));
    };
    audio["stop_music"] = [&host]() {
        if (host.audio) host.audio->stop_music();
    };
    audio["paused"] = [&host](sol::object value) -> bool {
        if (!host.audio) return false;
        if (value.is<bool>()) host.audio->set_paused(value.as<bool>());
        return host.audio->paused();
    };
    audio["stop_all"] = [&host]() {
        if (host.audio) host.audio->stop_all();
    };

    // 采样：sample("assets/hit.wav") → 句柄（0 表示失败），数据来自卡带包
    audio["sample"] = [&host](const std::string& path) -> int {
        if (!host.audio || !host.cart_files) return 0;
        auto bytes = host.cart_files->read(path);
        if (!bytes) return 0;
        return host.audio->load_sample(path, *bytes);
    };
    audio["play_sample"] = [&host](int handle, sol::object opts) {
        if (!host.audio) return;
        float volume = 0.8f;
        bool loop = false;
        if (opts.is<sol::table>()) {
            sol::table t = opts.as<sol::table>();
            sol::object v = t["volume"];
            if (v.is<double>() || v.is<int>()) volume = v.as<float>();
            sol::object l = t["loop"];
            if (l.is<bool>()) loop = l.as<bool>();
        }
        host.audio->play_sample(handle, volume, loop);
    };
    audio["stop_sample"] = [&host](int handle) {
        if (host.audio) host.audio->stop_sample(handle);
    };
}

} // namespace phos

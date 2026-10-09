#pragma once

namespace sol { class state; }

namespace phos {

struct HostContext;

/// 注册 phos.audio.* API（合成音 / 音符 / 打击乐 / 音序器音乐 / 采样）。
/// 卡带的音乐与音效数据随卡带包分发，见 docs/api-reference.md。
void register_audio_api(sol::state& lua, HostContext& host);

} // namespace phos

-- music.lua —— WORMS 的背景乐（曲式化文本记谱）
--
--   * 一拍 = 十六分音符；"-" 休止；"=" 延音（让旋律能呼吸）
--   * 打击乐 K 底鼓 / S 军鼓 / H 踩镲
--   * 每轨可自带音色：低音用 triangle 更柔，旋律用 square 保持复古感
--   * patterns 是乐段，order 决定播放顺序；loop = true 时循环
--
-- 这首的要求是"轻缓欢快"：C 大调、100 bpm、I-V-vi-IV 这种听着就顺耳的进行，
-- 旋律留给长音（每句都有喘气的地方），鼓只用底鼓与踩镲、军鼓轻一点。
-- 4 个 64 步乐段，曲序 6 项 ≈ 一轮 58 秒 —— 一首一分钟左右、能一直循环的曲子。

local function bars(...)
  return table.concat({ ... }, " ")
end

local LEAD = { wave = "square", volume = 0.50, attack = 0.006, release = 0.18 }
local BASS = { wave = "triangle", volume = 0.75, attack = 0.014, release = 0.32 }
local DRUM = { volume = 0.55 }

local function track(instrument, steps)
  return {
    wave = instrument.wave, volume = instrument.volume,
    attack = instrument.attack, release = instrument.release,
    steps = steps,
  }
end

-- 乐段 A：主题（C - G - Am - F），旋律走顺阶，句尾都落在长音上
local A = {
  lead = track(LEAD, bars(
    "E4 = = G4 = = C5 = = = G4 = = E4 - -",
    "D4 = = G4 = = B4 = = = D5 = = B4 - -",
    "C5 = = A4 = = E4 = = = A4 = = C5 - -",
    "A4 = = C5 = = F4 = = = A4 = = G4 = ="
  )),
  bass = track(BASS, bars(
    "C2 - - - - - - - G2 - - - - - - -",
    "G1 - - - - - - - D2 - - - - - - -",
    "A1 - - - - - - - E2 - - - - - - -",
    "F1 - - - - - - - C2 - - - - - - -"
  )),
  perc = track(DRUM, ("K - H - S - H - K - H - S - H - "):rep(4)),
}

-- 乐段 B：亮一点、动一点（副歌），低音走八分音符的脉动
local B = {
  lead = track(LEAD, bars(
    "C5 - E5 - G5 = = E5 - D5 - C5 = = -",
    "D5 - F5 - A5 = = F5 - E5 - D5 = = -",
    "E5 - C5 - A4 = = C5 - E5 - A4 = = -",
    "F5 - E5 - D5 = = C5 - D5 - E5 = = -"
  )),
  bass = track(BASS, bars(
    "C2 - - C2 - - - - G2 - - G2 - - - -",
    "D2 - - D2 - - - - A1 - - A1 - - - -",
    "A1 - - A1 - - - - E2 - - E2 - - - -",
    "F1 - - F1 - - - - G1 - - G1 - - - -"
  )),
  perc = track(DRUM, ("K - H - S - H - K - H - S - H S "):rep(4)),
}

-- 乐段 C：间奏（只留长音与轻鼓，给耳朵一点空隙）
local C = {
  lead = track(LEAD, bars(
    "E4 = = = G4 = = = A4 = = = G4 = = =",
    "D4 = = = F4 = = = G4 = = = E4 = = =",
    "C4 = = = E4 = = = A4 = = = G4 = = =",
    "F4 = = = A4 = = = C5 = = = G4 = = -"
  )),
  bass = track(BASS, bars(
    "C2 - - - - - - - - - - - - - - -",
    "G1 - - - - - - - - - - - - - - -",
    "A1 - - - - - - - - - - - - - - -",
    "F1 - - - - - - - - - - - - - - -"
  )),
  perc = track(DRUM, ("K - - - - - - - S - - - - - - - "):rep(4)),
}

-- 乐段 D：过门（上行推进，末尾回到主和弦）
local D = {
  lead = track(LEAD, bars(
    "G4 - A4 - B4 - C5 - D5 = = E5 = = -",
    "D5 = = C5 = = B4 = = A4 = = G4 = =",
    "E5 - - - G5 - - - C5 = = = E5 = = =",
    "G4 = = A4 = = B4 = = C5 = = = = ="
  )),
  bass = track(BASS, bars(
    "C2 - - - G1 - - - A1 - - - F1 - - -",
    "G1 - - - D2 - - - E2 - - - A1 - - -",
    "A1 - - - E2 - - - F1 - - - G1 - - -",
    "F1 - - - G1 - - - C2 - - - - - - -"
  )),
  perc = track(DRUM, ("K - K - S - H - K - K - S - H S "):rep(4)),
}

return {
  bpm = 100,          -- 慢一点更像"轻缓"，也不抢瞄准时的注意力
  wave = "square",
  loop = true,
  patterns = { A = A, B = B, C = C, D = D },
  -- 曲序：主题 - 副歌 - 主题 - 间奏 - 副歌 - 过门，一轮约 58 秒后循环
  order = { "A", "B", "A", "C", "B", "D" },
}

-- music.lua —— 迷宫里的紧张循环（曲式化文本记谱，格式见 carts/snake/music.lua）
--
--   * 一拍 = 十六分音符；"-" 休止；"=" 延音；打击乐 K 底鼓 / S 军鼓 / H 踩镲
--   * 每行 16 个记号；patterns 是乐段，order 决定播放顺序，loop = true 时循环
--
-- 和声：A 小调（Am - F - G - E），低音走根音，旋律在三四度间来回游走——
-- 这样即使只有两个乐段，听起来也不像原地打转。

local function bars(...)
  return table.concat({ ... }, " ")
end

local LEAD = { wave = "square", volume = 0.40, attack = 0.005, release = 0.12 }
local BASS = { wave = "triangle", volume = 0.80, attack = 0.010, release = 0.26 }
local DRUM = { volume = 0.55 }

local function track(instrument, steps)
  return {
    wave = instrument.wave, volume = instrument.volume,
    attack = instrument.attack, release = instrument.release,
    steps = steps,
  }
end

-- A 段：主题，暗而跑动
local A = {
  lead = track(LEAD, bars(
    "A3 - - E4 - - A4 - C5 - - G4 - - E4 -",
    "F3 - - C4 - - F4 - A4 - - E4 - - C4 -",
    "G3 - - D4 - - G4 - B4 - - F4 - - D4 -",
    "E3 - - B3 - - E4 - G#4 - - E4 - B3 - -"
  )),
  bass = track(BASS, bars(
    "A1 - - - - - - - E1 - - - - - - -",
    "F1 - - - - - - - C2 - - - - - - -",
    "G1 - - - - - - - D2 - - - - - - -",
    "E1 - - - - - - - B1 - - - - - - -"
  )),
  perc = track(DRUM, ("K - H - S - H - "):rep(2)),
}

-- B 段：高一个八度，鼓更实（吃到能量豆时听感明显不一样）
local B = {
  lead = track(LEAD, bars(
    "C5 - - A4 - - E4 - A4 - - C5 - - E5 -",
    "D5 - - B4 - - G4 - B4 - - D5 - - F5 -",
    "E5 - - C5 - - A4 - C5 - - E5 - - G5 -",
    "F5 - - E5 - - D5 - C5 - - B4 - - A4 -"
  )),
  bass = track(BASS, bars(
    "A1 - - A1 - - - - E2 - - E2 - - - -",
    "F1 - - F1 - - - - C2 - - C2 - - - -",
    "G1 - - G1 - - - - D2 - - D2 - - - -",
    "E1 - - E1 - - - - B1 - - B1 - - - -"
  )),
  perc = track(DRUM, "K - H - S - H - K - K - S - H - "),
}

return {
  bpm = 138,
  wave = "square",
  loop = true,
  patterns = { A = A, B = B },
  order = { "A", "A", "B", "A", "B", "A", "B", "A" },
}

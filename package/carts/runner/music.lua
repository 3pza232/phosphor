-- music.lua —— 长跑的循环（曲式化文本记谱，格式见 carts/snake/music.lua）
--
--   * 一拍 = 十六分音符；"-" 休止；"=" 延音；打击乐 K 底鼓 / S 军鼓 / H 踩镲
--   * 每行 16 个记号；patterns 是乐段，order 决定播放顺序
--
-- 和声：D 大调五声音阶，旋律尽量落在正拍上——跑动感来自鼓与低音，旋律只管亮。

local function bars(...)
  return table.concat({ ... }, " ")
end

local LEAD = { wave = "square", volume = 0.34, attack = 0.004, release = 0.10 }
local BASS = { wave = "triangle", volume = 0.75, attack = 0.010, release = 0.22 }
local DRUM = { volume = 0.50 }

local function track(instrument, steps)
  return {
    wave = instrument.wave, volume = instrument.volume,
    attack = instrument.attack, release = instrument.release,
    steps = steps,
  }
end

-- A 段：主题，明亮
local A = {
  lead = track(LEAD, bars(
    "D4 - - A4 - - F#4 - A4 - - D5 - - A4 -",
    "B3 - - D4 - - G4 - B4 - - D5 - - B4 -"
  )),
  bass = track(BASS, bars(
    "D2 - - - - - - - A1 - - - - - - -",
    "G1 - - - - - - - D2 - - - - - - -"
  )),
  perc = track(DRUM, ("K - H - S - H - "):rep(2)),
}

-- B 段：升高、鼓更密（速度感上来）
local B = {
  lead = track(LEAD, bars(
    "F#4 - - A4 - - D5 - E5 - - D5 - - A4 -",
    "G4 - - B4 - - D5 - F#5 - - E5 - - B4 -"
  )),
  bass = track(BASS, bars(
    "B1 - - B1 - - - - F#2 - - F#2 - - - -",
    "G1 - - G1 - - - - D2 - - D2 - - - -"
  )),
  perc = track(DRUM, "K - H - S - H K - K - H - S - H "),
}

return {
  bpm = 146,
  wave = "square",
  loop = true,
  patterns = { A = A, B = B },
  order = { "A", "A", "B", "A", "B", "B" },
}

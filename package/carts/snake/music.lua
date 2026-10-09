-- music.lua —— 卡带自带 BGM（曲式化文本记谱）
--
--   * 一拍 = 十六分音符；"-" 休止；"=" 延音（延续上一个音，让旋律能呼吸）
--   * 打击乐 K 底鼓 / S 军鼓 / H 踩镲
--   * 每轨可自带音色：低音用 triangle 更柔，旋律用 square 保持复古感
--   * patterns 是乐段，order 决定播放顺序；loop = true 时循环
--   * 本曲：4 个 64 步乐段，曲序 18 项 ≈ 每轮 131 秒（约两分钟）
--
-- 和声：E 小调常见进行 Em - C - Am - B7（尾句回到 Em），
-- 低音走根音+五度，旋律避免与低音撞音，因此听起来不"生硬"。

local function bars(...)
  return table.concat({ ... }, " ")
end

local LEAD = { wave = "square", volume = 0.55, attack = 0.006, release = 0.16 }
local BASS = { wave = "triangle", volume = 0.85, attack = 0.012, release = 0.30 }
local DRUM = { volume = 0.7 }

local function track(instrument, steps)
  return {
    wave = instrument.wave, volume = instrument.volume,
    attack = instrument.attack, release = instrument.release,
    steps = steps,
  }
end

-- 乐段 A：主题（Em - C - Am - B7），旋律留白多、句尾收在属音
local A = {
  lead = track(LEAD, bars(
    "E4 = = = G4 = = B4 = = - - - - -",
    "C5 = = B4 = = G4 = = - - - - -",
    "A4 = = C5 = = B4 = = - - - - -",
    "F#4 = = A4 = = B4 = = = = - - -"
  )),
  bass = track(BASS, bars(
    "E2 - - - - - - - B1 - - - - - - -",
    "C2 - - - - - - - G1 - - - - - - -",
    "A1 - - - - - - - E2 - - - - - - -",
    "B1 - - - - - - - F#2 - - - - - - -"
  )),
  perc = track(DRUM, ("K - H - S - H - K - H - S - H - "):rep(4)),
}

-- 乐段 B：副歌（旋律上行、节奏收紧，鼓更实）
local B = {
  lead = track(LEAD, bars(
    "B4 - E5 - D5 = B4 = A4 - G4 - A4 =",
    "G4 - C5 - B4 = G4 = F#4 - E4 - F#4 =",
    "A4 - D5 - C5 = A4 = G4 - F#4 - G4 =",
    "F#4 - B4 - A4 = F#4 = E4 = = D4 - -"
  )),
  bass = track(BASS, bars(
    "E2 - - E2 - - - - B1 - - B1 - - - -",
    "C2 - - C2 - - - - G1 - - G1 - - - -",
    "D2 - - D2 - - - - A1 - - A1 - - - -",
    "B1 - - B1 - - - - F#2 - - F#2 - - - -"
  )),
  perc = track(DRUM, ("K - H - S - H - K - H - S - H S "):rep(4)),
}

-- 乐段 C：间奏（稀疏、留白，只留低音与轻鼓）
local C = {
  lead = track(LEAD, bars(
    "E4 = = = = = = = B4 = = = = = = =",
    "A4 = = = = = = = C5 = = = = = = =",
    "G4 = = = = = = = B4 = = = = = = =",
    "F#4 = = = = = = = E4 = = = = - - -"
  )),
  bass = track(BASS, bars(
    "E2 - - - - - - - - - - - - - - -",
    "A1 - - - - - - - - - - - - - - -",
    "C2 - - - - - - - - - - - - - - -",
    "B1 - - - - - - - - - - - - - - -"
  )),
  perc = track(DRUM, ("K - - - - - - - S - - - - - - - "):rep(4)),
}

-- 乐段 D：过门（回到主题前的推进，末尾收在属和弦引回 Em）
local D = {
  lead = track(LEAD, bars(
    "B3 - D4 - E4 - F#4 - G4 = = A4 = =",
    "B4 = = A4 = = G4 = = F#4 = = E4 =",
    "E4 - - - G4 - - - B4 - - - E5 = =",
    "D5 = = B4 = = A4 = = F#4 = = B4 ="
  )),
  bass = track(BASS, bars(
    "E2 - - - E2 - - - B1 - - - B1 - - -",
    "C2 - - - C2 - - - G1 - - - G1 - - -",
    "A1 - - - A1 - - - E2 - - - E2 - - -",
    "F#2 - - - F#2 - - - B1 - - - B1 - - -"
  )),
  perc = track(DRUM, ("K - K - S - H - K - K - S - H S "):rep(4)),
}

return {
  bpm = 132,          -- 略慢一点，句法更从容
  wave = "square",
  loop = true,
  patterns = { A = A, B = B, C = C, D = D },
  -- 曲序：主题 - 副歌 - 主题 - 间奏 - 副歌 - 主题 - 过门 - 主题…
  order = {
    "A", "A", "B", "A", "A", "B",
    "C", "B", "A", "A", "B", "A",
    "D", "A", "B", "A", "A", "B",
  },
}

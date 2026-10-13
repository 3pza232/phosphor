-- music.lua —— 中国象棋的循环 BGM（五声音阶、舒缓；2 个乐段 + 曲序，进入对局后才播）。
return {
  bpm = 84,
  wave = "triangle",
  loop = true,
  patterns = {
    A = {
      lead = { wave = "triangle", volume = 0.5, release = 0.26,
               steps = "A4 - C5 - D5 = C5 - A4 - G4 - A4 - - - - - -" },
      bass = { wave = "sine", volume = 0.7, release = 0.40,
               steps = "A2 - - - E2 - - - F2 - - - E2 - - -" },
    },
    B = {
      lead = { wave = "triangle", volume = 0.5, release = 0.26,
               steps = "G4 - A4 - C5 - D5 = C5 - A4 - G4 - E4 - - -" },
      bass = { wave = "sine", volume = 0.7, release = 0.40,
               steps = "C2 - - - G1 - - - A1 - - - E2 - - -" },
    },
  },
  order = { "A", "A", "B", "A" },
}

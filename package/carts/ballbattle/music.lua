-- music.lua —— 球球大作战的循环 BGM（曲式写法：4 个乐段 + 曲序，约一分钟不重样）。
return {
  bpm = 148,
  wave = "square",
  loop = true,
  patterns = {
    A = {
      lead = { wave = "square", volume = 0.5, release = 0.10,
               steps = "E4 - G4 - B4 = A4 - G4 - E4 - D4 - E4 - - - - - -" },
      bass = { wave = "triangle", volume = 0.85, release = 0.28,
               steps = "E2 - - - - - - - A1 - - - - - - -" },
      perc = { volume = 0.7, steps = "K - H - S - H - K - H - S - H - S" },
    },
    B = {
      lead = { wave = "square", volume = 0.5, release = 0.10,
               steps = "B4 - A4 - G4 = E4 - G4 - A4 = B4 - - - - - -" },
      bass = { wave = "triangle", volume = 0.85, release = 0.28,
               steps = "C2 - - - - - - - G1 - - - - - - -" },
      perc = { volume = 0.7, steps = "K - H S H - S - H K - H - S - H -" },
    },
    C = {
      lead = { wave = "saw", volume = 0.4, release = 0.08,
               steps = "E5 = = = D5 = B4 = C5 - B4 - A4 - G4 -" },
      bass = { wave = "triangle", volume = 0.9, release = 0.30,
               steps = "A1 - - - E2 - - - F2 - - - G2 - - -" },
      perc = { volume = 0.75, steps = "K - S - K H S - H - K - S - H S" },
    },
    D = {
      lead = { wave = "square", volume = 0.5, release = 0.10,
               steps = "G4 - B4 - D5 = C5 - B4 - A4 - G4 - A4 - - -" },
      bass = { wave = "triangle", volume = 0.85, release = 0.28,
               steps = "G1 - - - D2 - - - E2 - - - B1 - - -" },
      perc = { volume = 0.7, steps = "K - H - S - H S K - H - S - H -" },
    },
  },
  order = { "A", "A", "B", "A", "C", "A", "B", "D" },
}

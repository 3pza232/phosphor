-- 背景音乐：街机感的中速循环
--
-- 四个乐段：A 主句 / B 上行 / C 过门 / D 高音段，按 A B A C A B D C 排列，
-- 约 28 秒才回到开头（太短的循环会让玩家很快听腻）；每段 32 步（两小节），
-- 低音走根音、打击乐给骨架，主旋律用延音写出呼吸感。

return {
  bpm = 138,
  wave = "square",
  loop = true,
  patterns = {
    A = {
      lead = { wave = "square", volume = 0.34, release = 0.14,
               steps = "A4 - C5 - E5 - C5 - D5 - - - C5 - B4 - A4 - C5 - E5 - A5 - G5 - E5 - D5 - - -" },
      bass = { wave = "triangle", volume = 0.7, release = 0.26,
               steps = "A2 - - - A2 - - - G2 - - - G2 - - - F2 - - - F2 - - - E2 - - - E2 - - -" },
      perc = { volume = 0.5,
               steps = "K - H - S - H - K - H - S - H H K - H - S - H - K - H - S - H S" },
    },
    B = {
      lead = { wave = "square", volume = 0.34, release = 0.14,
               steps = "E5 - G5 - A5 - G5 - F5 - E5 - D5 - C5 - E5 - G5 - B5 - A5 - G5 - F5 - E5 - - -" },
      bass = { wave = "triangle", volume = 0.7, release = 0.26,
               steps = "A2 - - - E2 - - - F2 - - - C3 - - - D2 - - - A2 - - - E2 - - - E2 - - -" },
      perc = { volume = 0.5,
               steps = "K - H - S - H H K - H - S - H - K - H - S - H H K H S H K H S H" },
    },
    C = {
      -- 过门：旋律全用延音、打击乐只留零星几点，让耳朵歇一下
      lead = { wave = "square", volume = 0.28, release = 0.3,
               steps = "C5 = = = B4 = = = A4 = = = G4 = = = F4 = = = G4 = = = A4 = = = = = = =" },
      bass = { wave = "triangle", volume = 0.6, release = 0.5,
               steps = "F2 - - - - - - - G2 - - - - - - - A2 - - - - - - - E2 - - - - - - -" },
      perc = { volume = 0.4,
               steps = "K - - - - - - - - - - - S - - - K - - - - - - - - - - - - - - -" },
    },
    D = {
      -- 高音段：情绪抬起来，收在长延音上
      lead = { wave = "square", volume = 0.36, release = 0.16,
               steps = "A5 - G5 - E5 - D5 - C5 - D5 - E5 = = = A5 - G5 - E5 - G5 - A5 = = = = = = =" },
      bass = { wave = "triangle", volume = 0.72, release = 0.26,
               steps = "A2 - - - - - - - A2 - - - - - - - F2 - - - - - - - G2 - - - - - - -" },
      perc = { volume = 0.55,
               steps = "K - H - S - H H K - H - S - H - K - H - S - H H K H S H K H S H" },
    },
  },
  order = { "A", "B", "A", "C", "A", "B", "D", "C" },
}

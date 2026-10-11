-- music.lua —— 背景音乐：俄式民谣味的中速循环（四段：主句 / 上行 / 过门 / 高音段）
--
-- 用自然小调写，主旋律走级进 + 跳进交替，低音只走根音——老式游戏机的配器就这两层，
-- 加厚反而糊。每段 32 步（两小节），按 A B A C A B D C 排列，约 25 秒回到开头。

return {
  bpm = 144,
  wave = "square",
  loop = true,
  patterns = {
    A = {
      lead = { wave = "square", volume = 0.34, release = 0.14,
               steps = "E5 - B4 - C5 - D5 - C5 - B4 - A4 - A4 - C5 - E5 - D5 - C5 - B4 - - - - -" },
      bass = { wave = "triangle", volume = 0.7, release = 0.26,
               steps = "A2 - - - E2 - - - A2 - - - E2 - - - F2 - - - C3 - - - E2 - - - E2 - - -" },
      perc = { volume = 0.5,
               steps = "K - H - S - H - K - H - S - H H K - H - S - H - K - H - S - H S" },
    },
    B = {
      lead = { wave = "square", volume = 0.34, release = 0.14,
               steps = "E5 - C5 - D5 - E5 - F5 - E5 - D5 - C5 - B4 - C5 - D5 - E5 - C5 - - - - -" },
      bass = { wave = "triangle", volume = 0.7, release = 0.26,
               steps = "F2 - - - C3 - - - D2 - - - A2 - - - E2 - - - A2 - - - E2 - - - E2 - - -" },
      perc = { volume = 0.5,
               steps = "K - H - S - H H K - H - S - H - K - H - S - H H K H S H K H S H" },
    },
    C = {
      -- 过门：全用延音、打击乐只留零星几点，让耳朵歇一下
      lead = { wave = "square", volume = 0.28, release = 0.3,
               steps = "A4 = = = G4 = = = F4 = = = E4 = = = D4 = = = E4 = = = A4 = = = = = = =" },
      bass = { wave = "triangle", volume = 0.6, release = 0.5,
               steps = "D2 - - - - - - - E2 - - - - - - - F2 - - - - - - - E2 - - - - - - -" },
      perc = { volume = 0.4,
               steps = "K - - - - - - - - - - - S - - - K - - - - - - - - - - - - - - -" },
    },
    D = {
      -- 高音段：抬起来，收在长延音上
      lead = { wave = "square", volume = 0.36, release = 0.16,
               steps = "A5 - G5 - E5 - D5 - C5 - D5 - E5 = = = B5 - A5 - G5 - A5 = = = = = = =" },
      bass = { wave = "triangle", volume = 0.72, release = 0.26,
               steps = "A2 - - - - - - - A2 - - - - - - - F2 - - - - - - - E2 - - - - - - -" },
      perc = { volume = 0.55,
               steps = "K - H - S - H H K - H - S - H - K - H - S - H H K H S H K H S H" },
    },
  },
  order = { "A", "B", "A", "C", "A", "B", "D", "C" },
}

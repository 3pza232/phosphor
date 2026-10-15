-- music.lua —— 地牢循环 BGM（曲式写法：4 段 + 曲序，DESIGN §13）。
--
-- 基调：低音 triangle 缓慢下行 + 稀疏 square 旋律 + 心跳般 perc。
-- 旋律**逐级进行**（相邻音只差 1~2 度），不做大跳——目标是耐听、不抢戏，
-- 让"回合制探索"的安静留得住。`=` 是延音，把旋律连成有呼吸的线。
-- 每轨都是 16 步，四段对齐循环。

return {
  bpm = 96,
  wave = "triangle",
  loop = true,
  patterns = {
    A = {
      lead = { wave = "square", volume = 0.30, release = 0.22,
               steps = "A4 = C5 = B4 = A4 = G4 = = = E4 = = = =" },
      bass = { wave = "triangle", volume = 0.70, release = 0.40,
               steps = "A2 = = = = = = = A2 = = = = = = =" },
      perc = { volume = 0.45, steps = "K - - - H - - - K - - - H - - -" },
    },
    B = {
      lead = { wave = "square", volume = 0.30, release = 0.22,
               steps = "G4 = A4 = G4 = F4 = E4 = = = D4 = = = =" },
      bass = { wave = "triangle", volume = 0.70, release = 0.40,
               steps = "F2 = = = = = = = F2 = = = = = = =" },
      perc = { volume = 0.45, steps = "K - - - H - - - K - - - H - - -" },
    },
    C = {
      lead = { wave = "square", volume = 0.30, release = 0.22,
               steps = "C5 = B4 = A4 = G4 = F4 = E4 = D4 = = =" },
      bass = { wave = "triangle", volume = 0.70, release = 0.40,
               steps = "C2 = = = = = = = C2 = = = = = = =" },
      perc = { volume = 0.45, steps = "K - - - H - - - K - - - H - H -" },
    },
    D = {
      lead = { wave = "square", volume = 0.30, release = 0.24,
               steps = "E4 = = F4 = = G4 = = A4 = = = = = =" },
      bass = { wave = "triangle", volume = 0.75, release = 0.45,
               steps = "E2 = = = = = = = E2 = = = = = = =" },
      perc = { volume = 0.5, steps = "K - - - H - - - K - - H - H - -" },
    },
  },
  order = { "A", "B", "C", "D" },
}

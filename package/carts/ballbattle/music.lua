-- music.lua —— 球球大作战的循环 BGM（曲式写法：4 个乐段 + 曲序）。
-- 每轨均 16 步（引擎按最长轨循环）。旋律**逐级进行**：相邻两音只差 1~2 个半音，顶多三度，
-- 不做大跳；低音是平滑的 Am–G–F–G，每段一个长音。音色用 triangle 并把速度放缓——
-- 目标是耐听、不刺耳，而不是热闹。`=` 是延音，把旋律连成有呼吸的线。
return {
  bpm = 116,
  wave = "triangle",
  loop = true,
  patterns = {
    A = {
      lead = { wave = "triangle", volume = 0.45, release = 0.16,
               steps = "A4 = B4 = C5 = B4 = A4 = G4 = A4 = - -" },
      bass = { wave = "triangle", volume = 0.72, release = 0.30,
               steps = "A2 = = = = = = = A2 = = = = = = =" },
      perc = { volume = 0.5, steps = "K - - H - - H - K - - H - - H -" },
    },
    B = {
      lead = { wave = "triangle", volume = 0.45, release = 0.16,
               steps = "G4 = A4 = B4 = A4 = G4 = F4 = G4 = - -" },
      bass = { wave = "triangle", volume = 0.72, release = 0.30,
               steps = "G2 = = = = = = = G2 = = = = = = =" },
      perc = { volume = 0.5, steps = "K - - H - - H - K - - H - - H -" },
    },
    C = {
      lead = { wave = "triangle", volume = 0.45, release = 0.16,
               steps = "F4 = G4 = A4 = G4 = F4 = E4 = F4 = - -" },
      bass = { wave = "triangle", volume = 0.72, release = 0.30,
               steps = "F2 = = = = = = = F2 = = = = = = =" },
      perc = { volume = 0.5, steps = "K - - H - - H - K - - H - - H -" },
    },
    D = {
      lead = { wave = "triangle", volume = 0.45, release = 0.16,
               steps = "G4 = F4 = E4 = F4 = G4 = A4 = B4 = - -" },
      bass = { wave = "triangle", volume = 0.72, release = 0.30,
               steps = "G2 = = = = = = = G2 = = = = = = =" },
      perc = { volume = 0.5, steps = "K - - H - - H - K - - H - - H -" },
    },
  },
  order = { "A", "B", "C", "D" },
}

-- music.lua —— 背景音乐：极缓慢的环境音（简短、轻柔、舒缓）
--
-- 生命游戏是"看着它自己演化"的东西，音乐不该抢戏：
--   速度慢（bpm 62）、几乎全是长延音、只用 sine/triangle、音量压低，
--   听感更像机器在呼吸，而不是一段旋律在重复。
-- 乐段只有三段，靠曲序 A B A C 拉开约 30 秒才回到开头。

return {
  bpm = 62,
  wave = "sine",
  loop = true,
  patterns = {
    A = {
      lead = { wave = "sine", volume = 0.22, attack = 0.3, release = 1.1,
               steps = "E4 = = = = = = = G4 = = = = = = = A4 = = = = = = = B4 = = = = = = =" },
      bass = { wave = "triangle", volume = 0.32, attack = 0.4, release = 1.4,
               steps = "E2 = = = = = = = = = = = = = = = C2 = = = = = = = = = = = = = = =" },
    },
    B = {
      lead = { wave = "sine", volume = 0.20, attack = 0.3, release = 1.1,
               steps = "B4 = = = = = = = A4 = = = = = = = G4 = = = = = = = E4 = = = = = = =" },
      bass = { wave = "triangle", volume = 0.30, attack = 0.4, release = 1.4,
               steps = "A2 = = = = = = = = = = = = = = = E2 = = = = = = = = = = = = = = =" },
    },
    C = {
      lead = { wave = "sine", volume = 0.20, attack = 0.3, release = 1.1,
               steps = "C5 = = = = = = = B4 = = = = = = = A4 = = = = = = = G4 = = = = = = =" },
      bass = { wave = "triangle", volume = 0.30, attack = 0.4, release = 1.4,
               steps = "F2 = = = = = = = = = = = = = = = G2 = = = = = = = = = = = = = = =" },
    },
  },
  order = { "A", "B", "A", "C" },
}

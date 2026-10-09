-- SOFT TONES：正弦波为主，起振与释放都更慢
return {
  boot    = { wave = "sine", freq = 165, sweep = 660, dur = 0.9, volume = 0.22, attack = 0.08, release = 0.4 },
  insert  = { wave = "sine", freq = 320, sweep = 480, dur = 0.35, volume = 0.20, attack = 0.02, release = 0.2 },
  eject   = { wave = "sine", freq = 420, sweep = 120, dur = 0.5, volume = 0.18, release = 0.3 },
  key     = { wave = "sine", freq = 720, dur = 0.05, volume = 0.12, attack = 0.01 },
  confirm = { wave = "triangle", freq = 620, sweep = 790, dur = 0.16, volume = 0.16 },
  error   = { wave = "triangle", freq = 220, sweep = 140, dur = 0.7, volume = 0.22 },
}

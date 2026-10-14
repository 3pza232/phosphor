-- MUTED：轻柔极简（正弦、极短、低音量，深夜不吵）
return {
  boot    = { wave = "sine", freq = 160, sweep = 120, dur = 0.30, volume = 0.12, release = 0.25 },
  insert  = { wave = "sine", freq = 520, dur = 0.050, volume = 0.10 },
  eject   = { wave = "sine", freq = 360, sweep = 200, dur = 0.12, volume = 0.10 },
  key     = { wave = "sine", freq = 900, dur = 0.012, volume = 0.06 },
  confirm = { wave = "sine", freq = 700, sweep = 900, dur = 0.05, volume = 0.09 },
  error   = { wave = "sine", freq = 240, sweep = 160, dur = 0.30, volume = 0.12 },
}

-- CHIP BEEP：8 位芯片音（方波、短促、跳脱的街机味）
return {
  boot    = { wave = "square", freq = 330, sweep = 990,  dur = 0.36, volume = 0.26, release = 0.02 },
  insert  = { wave = "square", freq = 660, sweep = 1320, dur = 0.08, volume = 0.24 },
  eject   = { wave = "square", freq = 880, sweep = 220,  dur = 0.16, volume = 0.24 },
  key     = { wave = "square", freq = 1980, dur = 0.015, volume = 0.14 },
  confirm = { wave = "square", freq = 1046, sweep = 1568, dur = 0.06, volume = 0.20 },
  error   = { wave = "square", freq = 220, sweep = 110, dur = 0.30, volume = 0.30 },
}

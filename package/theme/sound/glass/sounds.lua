-- GLASS BELL：清脆玻璃钟（正弦、高频、余音长）
return {
  boot    = { wave = "sine", freq = 880,  sweep = 2640, dur = 0.60, volume = 0.16, attack = 0.02, release = 0.50 },
  insert  = { wave = "sine", freq = 1568, sweep = 2093, dur = 0.14, volume = 0.18 },
  eject   = { wave = "sine", freq = 2093, sweep = 1046, dur = 0.20, volume = 0.18 },
  key     = { wave = "sine", freq = 2637, dur = 0.020, volume = 0.12 },
  confirm = { wave = "sine", freq = 1318, sweep = 1975, dur = 0.10, volume = 0.16 },
  error   = { wave = "sine", freq = 880,  sweep = 220,  dur = 0.40, volume = 0.20 },
}

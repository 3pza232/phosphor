-- DEEP HULL：低频厚重（三角/锯齿为主，机箱共振的沉响）
return {
  boot    = { wave = "triangle", freq = 90,  sweep = 42,  dur = 0.50, volume = 0.34, release = 0.40 },
  insert  = { wave = "noise",    dur = 0.22, volume = 0.40, release = 0.20 },
  eject   = { wave = "triangle", freq = 260, sweep = 70,  dur = 0.32, volume = 0.30 },
  key     = { wave = "triangle", freq = 620, dur = 0.030, volume = 0.20 },
  confirm = { wave = "triangle", freq = 420, sweep = 640, dur = 0.12, volume = 0.28 },
  error   = { wave = "saw",      freq = 120, sweep = 60,  dur = 0.60, volume = 0.34 },
}

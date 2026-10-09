-- RELAY CLACK：噪声与低频咔哒，机械继电器质感
return {
  boot    = { wave = "noise", dur = 0.09, volume = 0.30, release = 0.06 },
  insert  = { perc = "K" },
  eject   = { wave = "noise", dur = 0.07, volume = 0.26, release = 0.05 },
  key     = { wave = "noise", dur = 0.015, volume = 0.14, release = 0.01 },
  confirm = { perc = "H" },
  error   = { wave = "square", freq = 90, dur = 0.35, volume = 0.28, release = 0.25 },
}

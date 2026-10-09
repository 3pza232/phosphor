-- 主机事件音：wave/freq/sweep/dur/volume 均可缺省（回退同名默认）
-- 事件名：boot 开机 / insert 插卡 / eject 拔卡 / key 按键 / confirm 确认 / error 故障
return {
  -- 开机：电源合闸的低频重击（高压起振与自检 tick 由开机动画自己发声）
  boot    = { wave = "triangle", freq = 130, sweep = 52, dur = 0.30, volume = 0.26,
              attack = 0.005, release = 0.22 },
  insert  = { wave = "noise",  dur = 0.16, volume = 0.35, release = 0.12 },
  eject   = { wave = "square", freq = 520, sweep = 90, dur = 0.24, volume = 0.28 },
  key     = { wave = "square", freq = 1500, dur = 0.022, volume = 0.18 },
  confirm = { wave = "square", freq = 880, sweep = 1180, dur = 0.07, volume = 0.24 },
  error   = { wave = "square", freq = 170, sweep = 80, dur = 0.5, volume = 0.34 },
}

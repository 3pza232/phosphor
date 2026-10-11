-- sfx.lua —— 音效：只依赖 phos.audio，不接触游戏状态（mod 可整体替换）

local Sfx = {}

-- 砖块档位越高，击碎音越脆
local TIER_FREQ = { 392, 440, 494, 523, 587, 659 }

function Sfx.paddle()
  phos.audio.beep(220, 0.05, { wave = "square", volume = 0.22, sweep = 320 })
end

function Sfx.wall()
  phos.audio.beep(160, 0.04, { wave = "square", volume = 0.16 })
end

function Sfx.brick(tier)
  local freq = TIER_FREQ[tier] or 440
  phos.audio.beep(freq, 0.05, { wave = "square", volume = 0.2, sweep = freq * 1.25 })
end

function Sfx.launch()
  phos.audio.beep(300, 0.12, { wave = "saw", volume = 0.2, sweep = 720 })
end

function Sfx.dead()
  phos.audio.beep(320, 0.45, { wave = "saw", volume = 0.24, sweep = 70, release = 0.2 })
end

function Sfx.cleared()
  phos.audio.note("C5", { wave = "square", dur = 0.1, volume = 0.2 })
  phos.audio.note("E5", { wave = "square", dur = 0.1, volume = 0.2 })
  phos.audio.note("G5", { wave = "square", dur = 0.18, volume = 0.22 })
end

function Sfx.gameover()
  phos.audio.perc("K")
  phos.audio.note("A3", { wave = "triangle", dur = 0.28, volume = 0.24 })
  phos.audio.note("E3", { wave = "triangle", dur = 0.5, volume = 0.24 })
end

return Sfx

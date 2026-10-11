-- sfx.lua —— 音效：只依赖 phos.audio，不接触游戏状态（mod 可整体替换）

local Sfx = {}

function Sfx.move()
  phos.audio.beep(300, 0.03, { wave = "square", volume = 0.12 })
end

function Sfx.rotate()
  phos.audio.beep(440, 0.04, { wave = "square", volume = 0.14, sweep = 520 })
end

function Sfx.lock()
  phos.audio.beep(180, 0.05, { wave = "triangle", volume = 0.18 })
end

-- 一次消得越多，音越高：耳朵也能听出"这一下值多少"
function Sfx.clear(count)
  local notes = { "C5", "E5", "G5", "C6" }
  for i = 1, math.min(count, 4) do
    phos.audio.note(notes[i], { wave = "square", dur = 0.09, volume = 0.2 })
  end
end

function Sfx.hard_drop()
  phos.audio.beep(520, 0.06, { wave = "saw", volume = 0.16, sweep = 160 })
end

function Sfx.levelup()
  phos.audio.note("G5", { wave = "square", dur = 0.1, volume = 0.2 })
  phos.audio.note("C6", { wave = "square", dur = 0.16, volume = 0.22 })
end

function Sfx.gameover()
  phos.audio.perc("K")
  phos.audio.note("A3", { wave = "triangle", dur = 0.3, volume = 0.24 })
  phos.audio.note("D3", { wave = "triangle", dur = 0.55, volume = 0.24 })
end

return Sfx

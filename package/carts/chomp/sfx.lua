-- sfx.lua —— 卡带自带音效（合成音，无外部素材）
--
-- "咀嚼"是两声一对、交替音高：这是这个类型最容易被认出来的声音。
-- 音效只描述"发生了什么"，什么时候发由 main.lua 决定。

local function tone(freq, dur, opts)
  phos.audio.beep(freq, dur, opts)
end

return {
  chomp = function(phase)
    tone((phase % 2 == 0) and 520 or 380, 0.045, { wave = "square", volume = 0.15 })
  end,

  power = function()
    tone(220, 0.30, { wave = "saw", sweep = 700, volume = 0.2, release = 0.2 })
  end,

  -- 吃掉幽灵：三连上行，越往上越亮
  ghost = function()
    tone(880, 0.07, { wave = "square", volume = 0.22 })
    tone(1320, 0.08, { wave = "square", volume = 0.18 })
    tone(1760, 0.10, { wave = "square", volume = 0.15 })
  end,

  bonus = function()
    phos.audio.note("E5", { dur = 0.08, volume = 0.2 })
    phos.audio.note("G5", { dur = 0.10, volume = 0.2 })
    phos.audio.note("B5", { dur = 0.14, volume = 0.18 })
  end,

  cleared = function()
    for _, n in ipairs({ "C5", "E5", "G5", "C6" }) do
      phos.audio.note(n, { dur = 0.12, volume = 0.2 })
    end
  end,

  death = function()
    tone(520, 0.7, { wave = "triangle", sweep = 60, volume = 0.25, release = 0.4 })
  end,

  gameover = function()
    for _, n in ipairs({ "G4", "E4", "C4", "G3" }) do
      phos.audio.note(n, { dur = 0.22, volume = 0.2 })
    end
  end,
}

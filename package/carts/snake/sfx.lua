-- sfx.lua —— 卡带自带音效（合成音，无外部素材）

local function tone(freq, dur, opts)
  phos.audio.beep(freq, dur, opts)
end

return {
  eat = function()
    tone(920, 0.05, { wave = "square", volume = 0.22 })
    tone(1380, 0.06, { wave = "square", volume = 0.16 })
  end,

  die = function()
    tone(420, 0.55, { wave = "square", sweep = 70, volume = 0.28, release = 0.32 })
  end,

  start = function()
    phos.audio.note("C4", { dur = 0.09, volume = 0.2 })
    phos.audio.note("G4", { dur = 0.12, volume = 0.2 })
  end,
}

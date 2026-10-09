-- sfx.lua —— 卡带自带音效（合成音，无外部素材）
--
-- 只描述"发生了什么"（跳了 / 落地 / 过百 / 昼夜交替），什么时候发由 main.lua 决定。

local function tone(freq, dur, opts)
  phos.audio.beep(freq, dur, opts)
end

return {
  jump = function()
    tone(520, 0.15, { wave = "square", sweep = 900, volume = 0.17 })
  end,

  land = function()
    tone(140, 0.05, { wave = "noise", volume = 0.13 })
  end,

  -- 越过整百：两声短促的上行，提示"又快了"
  milestone = function()
    phos.audio.note("A5", { dur = 0.05, volume = 0.16 })
    phos.audio.note("E6", { dur = 0.09, volume = 0.14 })
  end,

  -- 昼夜交替：白天用明亮上行、夜里用柔和下行（听感上就知道"换场景了"）
  stage = function(night)
    local notes = night and { "A4", "F4", "D4" } or { "D4", "F4", "A4" }
    for _, note in ipairs(notes) do
      phos.audio.note(note, { dur = 0.13, volume = 0.18 })
    end
  end,

  death = function()
    tone(420, 0.5, { wave = "square", sweep = 90, volume = 0.24, release = 0.3 })
  end,

  gameover = function()
    for _, note in ipairs({ "A4", "F4", "D4", "A3" }) do
      phos.audio.note(note, { dur = 0.2, volume = 0.2 })
    end
  end,
}

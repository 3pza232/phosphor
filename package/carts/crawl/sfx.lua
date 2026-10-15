-- sfx.lua —— 玩法事件 → 合成音（DESIGN §13）。
--
-- 只用卡带自带的合成音，不依赖二进制素材。**规则模块不发声音**：world 把事件
-- 以 `events` 表返回，main 交给这里播放。于是"什么时候响"与"响什么音"分开，
-- 换一套音效不必碰玩法。

local Sfx = {}

local function beep(freq, dur, opts) phos.audio.beep(freq, dur, opts) end
local function note(n, opts) phos.audio.note(n, opts) end

-- 事件名 → 播放函数。未登记的事件静默跳过（比如 start）。
local HANDLERS = {
  hit      = function() beep(220, 0.05, { wave = "square", volume = 0.20 }) end,
  miss     = function() beep(160, 0.04, { wave = "square", volume = 0.10, sweep = 120 }) end,
  hurt     = function() beep(140, 0.09, { wave = "saw", sweep = 90, volume = 0.22 }) end,
  ranged   = function() beep(300, 0.10, { wave = "square", sweep = 160, volume = 0.18 }) end,
  kill     = function() beep(120, 0.14, { wave = "square", sweep = 60, volume = 0.20 }) end,
  coin     = function() note("E5", { dur = 0.05, volume = 0.16 }) end,
  pickup   = function() note("E5", { dur = 0.08, volume = 0.18 }) end,
  equip    = function() beep(520, 0.10, { wave = "triangle", sweep = 780, volume = 0.20 }) end,
  levelup  = function()
    note("C5", { dur = 0.1, volume = 0.22 })
    note("E5", { dur = 0.1, volume = 0.22 })
    note("G5", { dur = 0.14, volume = 0.22 })
  end,
  descend  = function() beep(300, 0.3, { wave = "triangle", sweep = 120, volume = 0.22 }) end,
  lightout = function() beep(90, 0.5, { wave = "sine", sweep = 40, volume = 0.24 }) end,
  drain    = function() beep(180, 0.16, { wave = "saw", sweep = 70, volume = 0.18 }) end,
  summon   = function() beep(70, 0.34, { wave = "saw", sweep = 200, volume = 0.24 }) end,
  enrage   = function() beep(110, 0.4, { wave = "square", sweep = 320, volume = 0.26 }) end,
  split    = function() beep(240, 0.12, { wave = "triangle", sweep = 140, volume = 0.16 }) end,
  use_oil    = function() note("A4", { dur = 0.12, volume = 0.20 }) end,
  use_potion = function() note("C5", { dur = 0.14, volume = 0.20 }) end,
  use_ration = function() note("G4", { dur = 0.12, volume = 0.18 }) end,
  use_blink  = function() beep(600, 0.16, { wave = "triangle", sweep = 1200, volume = 0.20 }) end,
  use_shock  = function() beep(160, 0.28, { wave = "square", sweep = 60, volume = 0.24 }) end,
  use_map    = function() note("D5", { dur = 0.12, volume = 0.18 }) end,
  use_flame  = function() beep(240, 0.3, { wave = "saw", sweep = 90, volume = 0.24 }) end,
  win      = function()
    for _, n in ipairs({ "C5", "E5", "G5", "C6" }) do note(n, { dur = 0.16, volume = 0.22 }) end
  end,
  death    = function() beep(180, 0.7, { wave = "saw", sweep = 50, volume = 0.26, release = 0.4 }) end,
}

function Sfx.play(event)
  local fn = HANDLERS[event and event.kind]
  if fn then fn() end
end

function Sfx.play_all(events)
  for _, e in ipairs(events) do Sfx.play(e) end
end

return Sfx

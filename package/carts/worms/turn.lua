-- turn.lua —— 回合：计时、换手、胜负。不读键盘、不绘制
--
-- 规则见 DESIGN.md：
--   * 每回合 60 秒，一次只能开一炮
--   * 开炮后进入 flying；弹药结算完由上层调 end_shot 回到 aim（见 main.lua 的 settle）
--   * 换手（next_team）：换队、重置计时与炮数；轮到队 1 才是新一轮、重掷风
--   * 任意一队全灭即结束
--
-- 稀有性**不用冷却表达**，而是"每只虫自己的弹药数"（weapons.lua 的 ammo 字段）：
-- 冷却会按武器把同一只虫卡住好几轮，手感别扭；弹药按虫算，谁省着用由玩家决定

local Physics = require("physics")

local Turn = {}
Turn.__index = Turn

Turn.TIME = 60          -- 每回合秒数

function Turn.new()
  local self = setmetatable({}, Turn)
  self.team = 1
  self.round = 1
  self.left = Turn.TIME
  self.phase = "aim"       -- aim / flying / over
  self.shots_left = 1      -- 每回合只能开一炮
  self.winner = nil
  self:roll_wind()
  return self
end

function Turn:roll_wind()
  self.wind = phos.sys.random(-Physics.MAX_WIND, Physics.MAX_WIND)
end

-- 能不能开炮：只看"是不是瞄准态"与"这一炮还没打"。
-- 弹药够不够由 Weapons.has_ammo 判，不在这里分叉
function Turn:ready()
  return self.phase == "aim" and self.shots_left > 0
end

function Turn:begin_shot()
  self.shots_left = 0
  self.phase = "flying"
end

-- 弹药结算完了：回到瞄准态（还没换手，等计时或手动结束）
function Turn:end_shot()
  self.phase = "aim"
end

-- 真正换手：换队、重置计时与炮数。
-- 风**一轮换一次**：轮到队 1 才是新的一轮开始（队 1、队 2 各打一轮 = 一回合）。
-- 每换手就重掷风的话，玩家刚算好的角度下一炮就作废，风也就没了意义
function Turn:next_team()
  self.team = (self.team == 1) and 2 or 1
  self.left = Turn.TIME
  self.shots_left = 1
  self.phase = "aim"
  if self.team == 1 then
    self.round = self.round + 1
    self:roll_wind()
  end
end

function Turn:finish(winner)
  self.phase = "over"
  self.winner = winner
end

-- 推进一帧。返回 { timeout = true } 表示这一回合时间到，该换手了。
-- 只在瞄准态被调用（main.lua 里弹药在飞时不走计时），所以这里不动 phase
function Turn:tick(dt)
  if self.phase == "over" then return {} end
  local events = {}
  self.left = self.left - dt
  if self.left <= 0 then
    events.timeout = true
  end
  return events
end

function Turn:time_text()
  return string.format("%02d", math.max(0, math.ceil(self.left)))
end

return Turn

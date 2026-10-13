-- game.lua —— 蛇的玩法状态机（不碰输入、绘制、音频与存档）
--
-- 与 bricks / life 同一套分层（见 docs/devkit.md）：玩法模块只认规则。
-- 输入由 main.lua 读键盘后经 turn() 传进来，画面由 main.lua 自己画——
-- 这样"哪个键转向"和"蛇长什么样"改动时都碰不到规则本身。
--
-- update(dt) 只回报"发生了什么"（事件表），由 main.lua 决定如何响应
-- （放音效、记分数）：玩法不知道有音效与存档这回事。

local ARENA = { x = 0, y = 1, w = 59, h = 39 }
local MOVE_INTERVAL = 0.09

local Game = {}
Game.__index = Game

function Game.new()
  local self = setmetatable({}, Game)
  self:reset()
  -- 每次移动的间隔（秒）。**不放进 reset**：这样 `~` 面板调好的速度在死亡重开后仍在
  self.move_interval = MOVE_INTERVAL
  return self
end

function Game:reset()
  local cx, cy = ARENA.w // 2, ARENA.h // 2
  self.body = { { cx, cy }, { cx - 1, cy }, { cx - 2, cy } }
  self.dx, self.dy = 1, 0
  self.pdx, self.pdy = 1, 0
  self.acc, self.score, self.alive = 0, 0, true
  self:place_food()
end

function Game:length()
  return #self.body
end

-- 转向意图：main.lua 读到方向键后调用。禁止 180 度掉头——
-- 那是玩法规则，不该散落在输入层（输入层只需回答"哪个键按下去了"）
function Game:turn(dx, dy)
  if dx ~= 0 and self.dx == -dx then return end
  if dy ~= 0 and self.dy == -dy then return end
  self.pdx, self.pdy = dx, dy
end

function Game:place_food()
  while true do
    local fx = phos.sys.random(0, ARENA.w - 1)
    local fy = phos.sys.random(0, ARENA.h - 1)
    local on_body = false
    for _, seg in ipairs(self.body) do
      if seg[1] == fx and seg[2] == fy then on_body = true break end
    end
    if not on_body then
      self.food = { fx, fy }
      return
    end
  end
end

function Game:step()
  self.dx, self.dy = self.pdx, self.pdy

  local head = { self.body[1][1] + self.dx, self.body[1][2] + self.dy }
  local out_of_bounds = head[1] < 0 or head[2] < 0 or
                        head[1] >= ARENA.w or head[2] >= ARENA.h
  local self_hit = false
  for _, seg in ipairs(self.body) do
    if seg[1] == head[1] and seg[2] == head[2] then self_hit = true break end
  end

  if out_of_bounds or self_hit then
    self.alive = false
    return "died"
  end

  table.insert(self.body, 1, head)
  if head[1] == self.food[1] and head[2] == self.food[2] then
    self.score = self.score + 10
    self:place_food()
    return "eaten"
  end
  table.remove(self.body)
  return nil
end

-- 推进一帧；返回事件表 { eaten=?, died=? }
-- 死亡后不再推进（重开由入口决定：那个键属于输入层，不属于规则）
function Game:update(dt)
  local events = {}
  if not self.alive then return events end

  self.acc = self.acc + dt
  while self.acc >= self.move_interval do
    self.acc = self.acc - self.move_interval
    local what = self:step()
    if what == "eaten" then events.eaten = true end
    if what == "died" then
      events.died = true
      return events
    end
  end
  return events
end

Game.ARENA = ARENA
return Game

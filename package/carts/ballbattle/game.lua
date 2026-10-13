-- game.lua —— 球球大作战的规则：生长、吞噬、AI 决策、大地图与持续出球。
-- 不读键盘、不画东西、不发声音；单位一律用"格"与"秒"。世界比屏幕大得多，由 main 的摄像机取景。

local Game = {}
Game.__index = Game

Game.WORLD_W, Game.WORLD_H = 280, 170   -- 世界尺寸（远大于屏幕，靠摄像机跟随）

local FOOD_R = 0.5
local FOOD_COUNT = 190        -- 世界里的食物目标数（铺满整个大图）
local MAX_AI = 14             -- 电脑球上限
local AI_SPAWN_EVERY = 2.2    -- 秒：每隔这么久补一支（低于上限时）
local START_AI = 8            -- 开局先放几支
local EAT_RATIO = 1.15        -- 半径比超过它才能吞
local START_R = 1.8

local function hypot(x, y) return math.sqrt(x * x + y * y) end
local function speed_of(r) return 17.0 / (1 + 0.40 * r) end  -- 越大越慢

function Game.new(rand)
  local self = setmetatable({}, Game)
  self.rand = rand or function() return 0.5 end
  self.time = 0
  self.alive = true
  self.eaten = 0
  self.best_r = START_R
  self.blobs = {}
  self.food = {}
  self.ai_timer = AI_SPAWN_EVERY
  self.hue = 0                 -- 给每支电脑球一个稳定色号（main 映射成色板颜色）

  self.player = { x = Game.WORLD_W / 2, y = Game.WORLD_H / 2, vx = 0, vy = 0, r = START_R,
                  role = "player", dirx = 0, diry = 0 }
  self.blobs[1] = self.player

  for _ = 1, START_AI do self:spawn_ai() end
  for _ = 1, FOOD_COUNT do self:drop_food() end
  return self
end

function Game:drop_food()
  self.food[#self.food + 1] = { x = self.rand(2, Game.WORLD_W - 2),
                                y = self.rand(2, Game.WORLD_H - 2) }
end

-- 在离玩家足够远的随机处放一支电脑球（避免出生即被围猎）
function Game:spawn_ai()
  local bx, by
  for _ = 1, 20 do
    bx, by = self.rand(6, Game.WORLD_W - 6), self.rand(6, Game.WORLD_H - 6)
    if hypot(bx - self.player.x, by - self.player.y) > 45 then break end
  end
  self.hue = self.hue + 1
  self.blobs[#self.blobs + 1] = {
    x = bx, y = by, vx = 0, vy = 0,
    r = 0.8 + self.rand() * 0.9, role = "ai", hue = self.hue, think = self.rand() * 0.3,
    tx = self.rand(2, Game.WORLD_W - 2), ty = self.rand(2, Game.WORLD_H - 2),
  }
end

function Game:steer(dx, dy)
  self.player.dirx, self.player.diry = dx, dy
end

function Game:think_ai(b, dt)
  b.think = b.think - dt
  if b.think > 0 then return end
  b.think = 0.3

  local flee_x, flee_y, threat = 0, 0, 0
  local best_d, tgt_x, tgt_y = math.huge, nil, nil
  for _, o in ipairs(self.blobs) do
    if o ~= b then
      local dx, dy, d = o.x - b.x, o.y - b.y, hypot(o.x - b.x, o.y - b.y)
      if o.r > b.r * EAT_RATIO and d < b.r + o.r + 12 then
        threat = threat + 1 / (d + 0.5)
        flee_x, flee_y = flee_x - dx / (d + 0.1), flee_y - dy / (d + 0.1)
      elseif b.r > o.r * EAT_RATIO and d < 22 and d < best_d then
        best_d, tgt_x, tgt_y = d, o.x, o.y
      end
    end
  end
  if not tgt_x then
    for _, f in ipairs(self.food) do
      local d = hypot(f.x - b.x, f.y - b.y)
      if d < best_d then best_d, tgt_x, tgt_y = d, f.x, f.y end
    end
  end
  if threat > 0 then
    b.tx, b.ty = b.x + flee_x, b.y + flee_y
  elseif tgt_x then
    b.tx, b.ty = tgt_x, tgt_y
  elseif hypot(b.tx - b.x, b.ty - b.y) < 3 then
    b.tx, b.ty = self.rand(2, Game.WORLD_W - 2), self.rand(2, Game.WORLD_H - 2)
  end
end

local function move_blob(b, dx, dy, dt, radius)
  local sp = speed_of(b.r)
  b.vx, b.vy = dx * sp, dy * sp
  b.x = b.x + b.vx * dt
  b.y = b.y + b.vy * dt
  local m = b.r
  if b.x < m then b.x = m elseif b.x > radius[1] - m then b.x = radius[1] - m end
  if b.y < m then b.y = m elseif b.y > radius[2] - m then b.y = radius[2] - m end
end

function Game:update(dt)
  if not self.alive then return {} end
  self.time = self.time + dt
  local events = {}
  local bounds = { Game.WORLD_W, Game.WORLD_H }

  -- 持续出球：低于上限就按节奏补
  self.ai_timer = self.ai_timer - dt
  if self.ai_timer <= 0 then
    self.ai_timer = AI_SPAWN_EVERY
    local ais = 0
    for _, b in ipairs(self.blobs) do if b.role == "ai" then ais = ais + 1 end end
    if ais < MAX_AI then self:spawn_ai() end
  end

  local p = self.player
  local dl = hypot(p.dirx, p.diry)
  if dl > 0 then move_blob(p, p.dirx / dl, p.diry / dl, dt, bounds) else p.vx, p.vy = 0, 0 end
  for _, b in ipairs(self.blobs) do
    if b.role == "ai" then
      self:think_ai(b, dt)
      local dx, dy = b.tx - b.x, b.ty - b.y
      local d = hypot(dx, dy)
      if d > 0.4 then move_blob(b, dx / d, dy / d, dt, bounds) else b.vx, b.vy = 0, 0 end
    end
  end

  -- 吃食物
  for i = #self.food, 1, -1 do
    local f = self.food[i]
    for _, b in ipairs(self.blobs) do
      if hypot(f.x - b.x, f.y - b.y) < b.r + FOOD_R then
        b.r = math.sqrt(b.r * b.r + FOOD_R * FOOD_R * 1.6)
        table.remove(self.food, i)
        if b == p then self.eaten = self.eaten + 1; events.eat = true end
        break
      end
    end
  end
  while #self.food < FOOD_COUNT do self:drop_food() end

  -- 球吃球（标记删除 + 重建，避免边遍历边删导致下标错位）
  local removed = {}
  for i = 1, #self.blobs do
    for j = i + 1, #self.blobs do
      if not removed[i] and not removed[j] then
        local a, b = self.blobs[i], self.blobs[j]
        local big, small, si = a, b, j
        if a.r < b.r then big, small, si = b, a, i end
        if big.r > small.r * EAT_RATIO and
           hypot(big.x - small.x, big.y - small.y) < big.r * 0.95 then
          big.r = math.sqrt(big.r * big.r + small.r * small.r)
          removed[si] = true
          if small == p then
            self.alive = false
            events.player_died = true
          elseif big == p then
            self.eaten = self.eaten + 1
            events.kill = true
          end
        end
      end
    end
  end
  if next(removed) then
    local kept = {}
    for i, b in ipairs(self.blobs) do if not removed[i] then kept[#kept + 1] = b end end
    self.blobs = kept
  end

  if self.player.r > self.best_r then self.best_r = self.player.r end
  if #self.blobs == 1 and self.alive then events.won = true end
  return events
end

function Game:ranked()
  local list = {}
  for _, b in ipairs(self.blobs) do list[#list + 1] = b end
  table.sort(list, function(x, y) return x.r > y.r end)
  return list
end

function Game:status()
  return {
    alive = self.alive, time = self.time, eaten = self.eaten,
    size = self.player.r, px = self.player.x, py = self.player.y,
    world_w = Game.WORLD_W, world_h = Game.WORLD_H,
    blobs = #self.blobs, food = #self.food,
    score = math.floor(self.eaten * 10 + self.best_r * 20),
  }
end

return Game

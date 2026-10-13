-- game.lua —— 球球大作战的规则：生长、吞噬、AI 决策。
-- 三条纪律：不读键盘（main 翻成 steer）、不画东西（main 画）、不发声音（返回事件表）。
-- 单位一律用"格"与"秒"，与屏幕无关。

local Game = {}
Game.__index = Game

local FOOD_R = 0.45          -- 食物半径
local FOOD_COUNT = 40        -- 场上食物目标数
local AI_COUNT = 4           -- 电脑球数量
local EAT_RATIO = 1.15       -- 半径比超过它才能吞（防止势均力敌互吃）
local START_R = 1.8

local function hypot(x, y) return math.sqrt(x * x + y * y) end
-- 半径越大越慢（经典手感）：速度 = base / (1 + k*r)
local function speed_of(r) return 15.5 / (1 + 0.42 * r) end

function Game.new(w, h, rand)
  local self = setmetatable({}, Game)
  self.w, self.h = w, h
  self.rand = rand or math.random
  self.time = 0
  self.alive = true
  self.eaten = 0          -- 吃掉的食物 + 球数
  self.blobs = {}
  self.food = {}

  self.player = { x = w / 2, y = h / 2, vx = 0, vy = 0, r = START_R,
                  role = "player", dirx = 0, diry = 0 }
  self.blobs[1] = self.player

  -- 电脑球：初始都比玩家略小或相当（免得开局就被围猎），且出生点离玩家至少 15 格
  for i = 1, AI_COUNT do
    local bx, by
    repeat
      bx, by = self.rand(6, w - 6), self.rand(6, h - 6)
    until hypot(bx - self.player.x, by - self.player.y) > 15
    self.blobs[#self.blobs + 1] = {
      x = bx, y = by, vx = 0, vy = 0,
      r = 0.8 + self.rand() * 0.8, role = "ai", ai = i, think = 0,
      tx = self.rand(2, w - 2), ty = self.rand(2, h - 2),   -- 漫游点（别都往中心挤）
    }
  end
  for _ = 1, FOOD_COUNT do self:drop_food() end
  return self
end

function Game:drop_food()
  self.food[#self.food + 1] = { x = self.rand(1, self.w - 1), y = self.rand(1, self.h - 1) }
end

-- 玩家意图：方向键按住时的期望方向（单位向量由 main 归一化后传入）
function Game:steer(dx, dy)
  self.player.dirx, self.player.diry = dx, dy
end

-- AI：追最近的食物或更小的球；附近有更大的球就逃。每 0.25 秒重新决策一次
function Game:think_ai(b, dt)
  b.think = b.think - dt
  if b.think > 0 then return end
  b.think = 0.25

  local flee_x, flee_y, threat = 0, 0, 0
  local best_d, tgt_x, tgt_y = math.huge, nil, nil
  for _, o in ipairs(self.blobs) do
    if o ~= b then
      local dx, dy, d = o.x - b.x, o.y - b.y, hypot(o.x - b.x, o.y - b.y)
      if o.r > b.r * EAT_RATIO and d < b.r + o.r + 8 then
        threat = threat + (1 / (d + 0.5))           -- 越近越怕
        flee_x, flee_y = flee_x - dx / (d + 0.1), flee_y - dy / (d + 0.1)
      elseif b.r > o.r * EAT_RATIO and d < 14 and d < best_d then
        best_d, tgt_x, tgt_y = d, o.x, o.y            -- 追更小的球
      end
    end
  end
  if not tgt_x then                                  -- 没有猎物就找最近的失物
    for _, f in ipairs(self.food) do
      local d = hypot(f.x - b.x, f.y - b.y)
      if d < best_d then best_d, tgt_x, tgt_y = d, f.x, f.y end
    end
  end
  if threat > 0 then
    b.tx, b.ty = b.x + flee_x, b.y + flee_y
  elseif tgt_x then
    b.tx, b.ty = tgt_x, tgt_y
  elseif hypot(b.tx - b.x, b.ty - b.y) < 2 then
    b.tx, b.ty = self.rand(2, self.w - 2), self.rand(2, self.h - 2)  -- 到点就换个漫游目标
  end
end

local function move_blob(self, b, dx, dy, dt)
  local sp = speed_of(b.r)
  b.vx, b.vy = dx * sp, dy * sp
  b.x = b.x + b.vx * dt
  b.y = b.y + b.vy * dt
  -- 撞墙即停（把圆心夹在 [r, w-r] 内，球体不出界）
  local m = b.r
  if b.x < m then b.x = m elseif b.x > self.w - m then b.x = self.w - m end
  if b.y < m then b.y = m elseif b.y > self.h - m then b.y = self.h - m end
end

function Game:update(dt)
  if not self.alive then return {} end
  self.time = self.time + dt
  local events = {}

  -- 玩家
  local p = self.player
  local dl = hypot(p.dirx, p.diry)
  if dl > 0 then move_blob(self, p, p.dirx / dl, p.diry / dl, dt) else p.vx, p.vy = 0, 0 end

  -- 电脑球
  for _, b in ipairs(self.blobs) do
    if b.role == "ai" then
      self:think_ai(b, dt)
      local dx, dy = b.tx - b.x, b.ty - b.y
      local d = hypot(dx, dy)
      if d > 0.3 then move_blob(self, b, dx / d, dy / d, dt) else b.vx, b.vy = 0, 0 end
    end
  end

  -- 吃食物
  for i = #self.food, 1, -1 do
    local f = self.food[i]
    for _, b in ipairs(self.blobs) do
      if hypot(f.x - b.x, f.y - b.y) < b.r + FOOD_R then
        b.r = math.sqrt(b.r * b.r + FOOD_R * FOOD_R * 1.6)  -- 面积守恒地长大
        table.remove(self.food, i)
        if b == p then self.eaten = self.eaten + 1; events.eat = true end
        break
      end
    end
  end
  while #self.food < FOOD_COUNT do self:drop_food() end

  -- 球吃球：大的吞小的（半径比够大、圆心足够贴近）。先标记再重建——
  -- 边遍历边 table.remove 会让下标错位（同一帧连吃两个就会漏判）
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
    for i, b in ipairs(self.blobs) do
      if not removed[i] then kept[#kept + 1] = b end
    end
    self.blobs = kept
  end

  if #self.blobs == 1 and self.alive then events.won = true end
  return events
end

-- 排行榜：按半径从大到小
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
    blobs = #self.blobs, food = #self.food,
    score = math.floor(self.eaten * 10 + self.player.r * 20),
  }
end

return Game

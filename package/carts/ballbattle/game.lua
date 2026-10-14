-- game.lua —— 球球大作战的规则：生长、吞噬、AI 决策、大地图与持续出球；
-- 玩家不再是一颗球，而是一组**细胞**（可分裂 / 吐食 / 合并）。
-- 不读键盘、不画东西、不发声音；单位一律"格"与"秒"。

local Game = {}
Game.__index = Game

Game.WORLD_W, Game.WORLD_H = 360, 220   -- 世界尺寸（远大于屏幕，靠摄像机跟随）

local FOOD_R = 0.5
local FOOD_COUNT = 220        -- 世界里的食物目标数
local MAX_AI = 26             -- 电脑球上限
local AI_SPAWN_EVERY = 1.1    -- 秒：每隔这么久补一支
local START_AI = 14
local EAT_RATIO = 1.15        -- 半径比超过它才能吞
local START_R = 1.8

-- 分裂 / 吐食 / 合并参数（集中在这里，方便调手感）
Game.SPLIT_MIN = 3.4          -- 半径达到它才能分裂
Game.MAX_CELLS = 16           -- 玩家细胞数上限
Game.MERGE_DELAY = 10         -- 分裂后多久才可合并（秒）
local SPLIT_BOOST = 62        -- 弹射初速（世界单位/秒）
local BOOST_TIME = 0.5        -- 弹射速度衰减到 0 的时间（"动态"，不是瞬停）
local EJECT_COST = 0.55       -- 每次吐食损失的半径平方（略大于吐出的食物：净亏一点）
local EJECT_MIN = 2.4         -- 半径小于它不许吐（防把自己吐饿死）
local EJECT_INTERVAL = 0.13   -- 每秒最多吐几次
local FOOD_SPEED = 46         -- 吐出食物的初速
local FOOD_DECAY = 3.0        -- 食物速度衰减（1/秒）

local function hypot(x, y) return math.sqrt(x * x + y * y) end
local function speed_of(r) return 26.0 / (1 + 0.30 * r) end

-- 只夹**球心**到世界矩形内：身体允许探出边界一部分。夹"球心 ± r"会让大球永远离墙 ≥ r，
-- 够不到边角的小球，而吞噬判定比的是圆心距——两者一冲突就"看着贴上却吃不掉"
local function clamp_center(b, w, h)
  if b.x < 0 then b.x = 0 elseif b.x > w then b.x = w end
  if b.y < 0 then b.y = 0 elseif b.y > h then b.y = h end
end

function Game.new(rand)
  local self = setmetatable({}, Game)
  self.rand = rand or function() return 0.5 end
  self.time = 0
  self.alive = true
  self.won = false
  self.eaten = 0
  self.best_m = START_R * START_R   -- 体格峰值按**总质量**记（分裂不改变它）
  self.blobs = {}
  self.food = {}
  self.ai_timer = AI_SPAWN_EVERY
  self.hue = 0
  self.eject_t = 0
  self.dirx, self.diry = 0, 0

  self.blobs[1] = self:new_player(Game.WORLD_W / 2, Game.WORLD_H / 2, START_R)
  for _ = 1, START_AI do self:spawn_ai() end
  for _ = 1, FOOD_COUNT do self:drop_food() end
  return self
end

function Game:new_player(x, y, r)
  return { x = x, y = y, vx = 0, vy = 0, r = r, role = "player",
           boost_t = 0, bvx = 0, bvy = 0, merge_t = 0 }
end

function Game:player_cells()
  local out = {}
  for _, b in ipairs(self.blobs) do if b.role == "player" then out[#out + 1] = b end end
  return out
end

-- 总质量 = Σ r²：相机视距按它算，于是"一分为二"视角不变（只有真正吃大才拉远）
function Game:mass()
  local m = 0
  for _, b in ipairs(self.blobs) do if b.role == "player" then m = m + b.r * b.r end end
  return m
end

-- 相机/状态用：质量加权质心（分身被吃，质心自然移动）
function Game:centroid()
  local m, cx, cy = 0, 0, 0
  for _, b in ipairs(self.blobs) do
    if b.role == "player" then m = m + b.r * b.r; cx = cx + b.x * b.r * b.r; cy = cy + b.y * b.r * b.r end
  end
  if m <= 0 then return Game.WORLD_W / 2, Game.WORLD_H / 2 end
  return cx / m, cy / m
end

-- 排行榜数据：玩家的所有细胞**合成一行**（否则分裂后一屏"你"），AI 各一行
function Game:leaderboard()
  local list, pm = {}, 0
  for _, b in ipairs(self.blobs) do
    if b.role == "player" then pm = pm + b.r * b.r
    else list[#list + 1] = { role = "ai", hue = b.hue, m = b.r * b.r } end
  end
  if pm > 0 then list[#list + 1] = { role = "player", m = pm } end
  table.sort(list, function(x, y) return x.m > y.m end)
  return list
end

function Game:drop_food()
  self.food[#self.food + 1] = { x = self.rand(2, Game.WORLD_W - 2),
                                y = self.rand(2, Game.WORLD_H - 2), vx = 0, vy = 0 }
end

function Game:spawn_ai()
  local px, py = Game.WORLD_W / 2, Game.WORLD_H / 2
  local bx, by
  for _ = 1, 20 do
    bx, by = self.rand(6, Game.WORLD_W - 6), self.rand(6, Game.WORLD_H - 6)
    if hypot(bx - px, by - py) > 45 then break end
  end
  self.hue = self.hue + 1
  self.blobs[#self.blobs + 1] = {
    x = bx, y = by, vx = 0, vy = 0,
    r = 0.8 + self.rand() * 0.9, role = "ai", hue = self.hue,
    think = self.rand() * 0.3,
    tx = self.rand(2, Game.WORLD_W - 2), ty = self.rand(2, Game.WORLD_H - 2),
  }
end

function Game:steer(dx, dy)
  self.dirx, self.diry = dx, dy
end

-- X：朝行进方向分裂。静止时无效；每个够大的细胞一分为二；总数不超过 MAX_CELLS
function Game:split()
  if not self.alive then return end
  local dl = hypot(self.dirx, self.diry)
  if dl < 0.01 then return end                  -- 没方向就不分裂
  local ux, uy = self.dirx / dl, self.diry / dl
  local cells = self:player_cells()
  local room = Game.MAX_CELLS - #cells
  if room <= 0 then return end
  local spawn = {}
  for _, c in ipairs(cells) do
    if room <= 0 then break end
    if c.r >= Game.SPLIT_MIN then
      c.r = c.r / math.sqrt(2)                  -- 质量对半 → 半径 /√2
      c.merge_t = Game.MERGE_DELAY
      local n = self:new_player(c.x, c.y, c.r)
      n.bvx, n.bvy = ux * SPLIT_BOOST, uy * SPLIT_BOOST
      n.boost_t = BOOST_TIME
      n.merge_t = Game.MERGE_DELAY
      spawn[#spawn + 1] = n
      room = room - 1
    end
  end
  for _, n in ipairs(spawn) do self.blobs[#self.blobs + 1] = n end
end

-- Z（按住）：每 EJECT_INTERVAL 从每个够大的细胞朝行进方向吐一颗食物
function Game:eject(dt)
  if not self.alive then return end
  local dl = hypot(self.dirx, self.diry)
  if dl < 0.01 then return end
  local ux, uy = self.dirx / dl, self.diry / dl
  self.eject_t = self.eject_t - dt
  if self.eject_t > 0 then return end
  self.eject_t = EJECT_INTERVAL
  for _, c in ipairs(self:player_cells()) do
    if c.r >= EJECT_MIN then
      c.r = math.sqrt(math.max(0.01, c.r * c.r - EJECT_COST))
      self.food[#self.food + 1] = {
        x = c.x + ux * (c.r + 1.1), y = c.y + uy * (c.r + 1.1),
        vx = ux * FOOD_SPEED, vy = uy * FOOD_SPEED,
      }
    end
  end
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
    local fl = hypot(flee_x, flee_y)
    if fl > 0.001 then
      b.tx, b.ty = b.x + flee_x / fl * 24, b.y + flee_y / fl * 24
    else
      b.tx, b.ty = b.x + 24, b.y
    end
  elseif tgt_x then
    b.tx, b.ty = tgt_x, tgt_y
  elseif hypot(b.tx - b.x, b.ty - b.y) < 3 then
    b.tx, b.ty = self.rand(2, Game.WORLD_W - 2), self.rand(2, Game.WORLD_H - 2)
  end
end

local function move_blob(b, dx, dy, dt, w, h)
  local sp = speed_of(b.r)
  b.vx, b.vy = dx * sp, dy * sp
  b.x = b.x + b.vx * dt
  b.y = b.y + b.vy * dt
  clamp_center(b, w, h)
end

-- 玩家自家细胞之间：还没到合并时间 → 硬碰撞（推开、不能重叠）；到了 → 相互吸引、重叠即合并
function Game:resolve_own(dt)
  local cells = self:player_cells()
  local removed = {}
  for i = 1, #cells do
    for j = i + 1, #cells do
      if not removed[i] and not removed[j] then
        local a, b = cells[i], cells[j]
        local dx, dy = b.x - a.x, b.y - a.y
        local d = hypot(dx, dy)
        if d < 0.0001 then d = 0.0001 end
        local ux, uy = dx / d, dy / d
        local sum = a.r + b.r
        if a.merge_t <= 0 and b.merge_t <= 0 then
          if d < sum * 0.5 then                       -- 叠够深 → 合并（质量相加，落在质心）
            local ma, mb = a.r * a.r, b.r * b.r
            a.x = (a.x * ma + b.x * mb) / (ma + mb)
            a.y = (a.y * ma + b.y * mb) / (ma + mb)
            a.r = math.sqrt(ma + mb)
            removed[j] = true
          else
            -- 已到合并时间：**取消碰撞**、互相吸引。不限接触——所有细胞同向平行移动时
            -- 间距恒定，只在接触时吸就永远合不回来
            local pull = math.min(4 * dt, d * 0.5)
            a.x = a.x + ux * pull; a.y = a.y + uy * pull
            b.x = b.x - ux * pull; b.y = b.y - uy * pull
          end
        elseif d < sum then                           -- 未到点：硬碰撞，各退一半
          local push = (sum - d) * 0.5
          a.x = a.x - ux * push; a.y = a.y - uy * push
          b.x = b.x + ux * push; b.y = b.y + uy * push
        end
      end
    end
  end
  if next(removed) then
    local dead = {}
    for k in pairs(removed) do dead[cells[k]] = true end
    local kept = {}
    for _, b in ipairs(self.blobs) do if not dead[b] then kept[#kept + 1] = b end end
    self.blobs = kept
  end
end

function Game:update(dt)
  if not self.alive then return {} end
  self.time = self.time + dt
  local events = {}
  local W, H = Game.WORLD_W, Game.WORLD_H

  -- 持续出球：低于上限就按节奏补
  self.ai_timer = self.ai_timer - dt
  if self.ai_timer <= 0 then
    self.ai_timer = AI_SPAWN_EVERY
    local ais = 0
    for _, b in ipairs(self.blobs) do if b.role == "ai" then ais = ais + 1 end end
    if ais < MAX_AI then self:spawn_ai() end
  end

  -- 玩家：所有细胞共用行进方向，各自全速；弹射速度线性衰减；合并计时倒数
  local dl = hypot(self.dirx, self.diry)
  local ux, uy = 0, 0
  if dl > 0 then ux, uy = self.dirx / dl, self.diry / dl end
  for _, b in ipairs(self.blobs) do
    if b.role == "player" then
      if dl > 0 then move_blob(b, ux, uy, dt, W, H) else b.vx, b.vy = 0, 0 end
      if b.boost_t > 0 then
        b.boost_t = math.max(0, b.boost_t - dt)
        local f = b.boost_t / BOOST_TIME
        b.x = b.x + b.bvx * f * dt
        b.y = b.y + b.bvy * f * dt
        clamp_center(b, W, H)
      end
      if b.merge_t > 0 then b.merge_t = math.max(0, b.merge_t - dt) end
    elseif b.role == "ai" then
      self:think_ai(b, dt)
      local tx, ty = b.tx - b.x, b.ty - b.y
      local d = hypot(tx, ty)
      if d > 0.4 then move_blob(b, tx / d, ty / d, dt, W, H) else b.vx, b.vy = 0, 0 end
    end
  end

  -- 食物：吐出的会飞、会减速（动态，不是瞬移）
  for _, f in ipairs(self.food) do
    if f.vx ~= 0 or f.vy ~= 0 then
      f.x = f.x + f.vx * dt
      f.y = f.y + f.vy * dt
      local k = math.exp(-FOOD_DECAY * dt)
      f.vx, f.vy = f.vx * k, f.vy * k
      if math.abs(f.vx) < 0.5 then f.vx = 0 end
      if math.abs(f.vy) < 0.5 then f.vy = 0 end
      clamp_center(f, W, H)
    end
  end

  -- 吃食物
  for i = #self.food, 1, -1 do
    local f = self.food[i]
    for _, b in ipairs(self.blobs) do
      if hypot(f.x - b.x, f.y - b.y) < b.r + FOOD_R then
        b.r = math.sqrt(b.r * b.r + FOOD_R * FOOD_R * 1.6)
        table.remove(self.food, i)
        if b.role == "player" then self.eaten = self.eaten + 1; events.eat = true end
        break
      end
    end
  end
  while #self.food < FOOD_COUNT do self:drop_food() end

  -- 球吃球（标记删除 + 重建）。**自家细胞不互吃**——它们交给 resolve_own 处理
  local removed = {}
  for i = 1, #self.blobs do
    for j = i + 1, #self.blobs do
      if not removed[i] and not removed[j] then
        local a, b = self.blobs[i], self.blobs[j]
        if not (a.role == "player" and b.role == "player") then
          local big, small, si = a, b, j
          if a.r < b.r then big, small, si = b, a, i end
          if big.r > small.r * EAT_RATIO and
             hypot(big.x - small.x, big.y - small.y) < big.r * 0.95 then
            big.r = math.sqrt(big.r * big.r + small.r * small.r)
            removed[si] = true
            if small.role == "player" then
              events.lost = true                        -- 掉了一个分身
            else
              self.eaten = self.eaten + 1
              events.kill = true
            end
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

  self:resolve_own(dt)

  -- 死亡：所有细胞都没了
  if #self:player_cells() == 0 then
    self.alive = false
    events.player_died = true
  end

  local m = self:mass()
  if m > self.best_m then self.best_m = m end

  local ais = 0
  for _, b in ipairs(self.blobs) do if b.role == "ai" then ais = ais + 1 end end
  if ais == 0 and self.alive then self.won = true; events.won = true end

  return events
end

function Game:ranked()
  local list = {}
  for _, b in ipairs(self.blobs) do list[#list + 1] = b end
  table.sort(list, function(x, y) return x.r > y.r end)
  return list
end

function Game:status()
  local cx, cy = self:centroid()
  return {
    alive = self.alive, won = self.won, time = self.time, eaten = self.eaten,
    size = math.sqrt(self:mass()),          -- 等价单球半径（相机/读数用）
    cells = #self:player_cells(),
    px = cx, py = cy,
    world_w = Game.WORLD_W, world_h = Game.WORLD_H,
    blobs = #self.blobs, food = #self.food,
    score = math.floor(self.eaten * 10 + math.sqrt(self.best_m) * 20),
  }
end

return Game

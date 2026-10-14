-- game.lua —— 球球大作战的规则：生长、吞噬、AI 决策、大地图与持续出球；
-- 玩家与电脑都按"**家（owner）**"组织：一家可有多颗细胞（可分裂 / 吐食 / 合并）。
-- 不读键盘、不画东西、不发声音；单位一律"格"与"秒"。

local Game = {}
Game.__index = Game

Game.WORLD_W, Game.WORLD_H = 360, 220

local FOOD_R = 0.5
local FOOD_COUNT = 220
local MAX_AI = 26
local AI_SPAWN_EVERY = 1.1
local START_AI = 14
local EAT_RATIO = 1.15
local START_R = 1.8

-- 分裂 / 吐食 / 合并（手感旋钮，挂到 ~ 调试台）
Game.SPLIT_MIN = 3.4          -- 半径达到它才能分裂
Game.MAX_CELLS = 16           -- 单"家"细胞数上限
Game.MERGE_DELAY = 10         -- 分裂后多久才可合并（秒）
local SPLIT_BOOST = 30        -- 弹射初速（放慢：向前扑一小段）
local BOOST_TIME = 0.7        -- 弹射速度衰减时间（之后被"聚拢"拉回）
local EJECT_COST = 0.4        -- 每次吐食损失的半径平方 = 吐出食物价值（吃回相等）
local EJECT_MIN = 2.4         -- 半径小于它不许吐
local EJECT_INTERVAL = 0.13
local FOOD_SPEED = 46
local FOOD_DECAY = 3.0

-- 电脑 AI 的策略参数
local AI_SPLIT_CD = 6.0       -- 分裂冷却（秒）
local AI_SPLIT_REACH = 26     -- 猎物进到这个距离才值得"向前扑"
local AI_SPLIT_PREY = 0.5     -- 猎物半径 < 自己×它 才扑（每半个仍吃得下）
local AI_EJECT_CD = 2.5       -- 弃重逃命的冷却
local AI_EJECT_THREAT = 7     -- 威胁近到这个距离才弃重

-- 刺球：大餐，但要够大才能吃、且吃下强制分裂；数量少、绝不生成在球底下
local SPIKE_COUNT = 4
local SPIKE_R = 2.2           -- 吃到它的判定半径
local SPIKE_MIN = 4.0         -- 半径达到它才吃得下
local SPIKE_GAIN = 2.5        -- 吃一颗涨的质量（远多于普通食物 0.4）
local SPIKE_CLEAR = 22        -- 生成时离所有球至少这么远

local function hypot(x, y) return math.sqrt(x * x + y * y) end
local function speed_of(r) return 26.0 / (1 + 0.30 * r) end

-- 只夹球心到世界矩形内：身体可探出边界一部分（否则大球够不到边角小球）
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
  self.best_m = START_R * START_R
  self.blobs = {}
  self.food = {}
  self.spikes = {}
  self.bursts = {}          -- 吃刺球/吐食的"闪烁"特效（给 draw 用）
  self.ai_timer = AI_SPAWN_EVERY
  self.ai_seq = 0
  self.eject_t = 0
  self.dirx, self.diry = 0, 0

  self.blobs[1] = self:new_cell(Game.WORLD_W / 2, Game.WORLD_H / 2, START_R, "player", "p")
  for _ = 1, START_AI do self:spawn_ai() end
  for _ = 1, FOOD_COUNT do self:drop_food() end
  for _ = 1, SPIKE_COUNT do self:spawn_spike() end
  return self
end

function Game:new_cell(x, y, r, role, owner)
  return { x = x, y = y, vx = 0, vy = 0, r = r, role = role, owner = owner,
           boost_t = 0, bvx = 0, bvy = 0, merge_t = 0, think = 0,
           atk_cd = 0, ej_cd = 0, tx = x, ty = y }   -- tx/ty 给默认值：分裂出的 AI 细胞也要用
end

function Game:owner_cells(owner)
  local out = {}
  for _, b in ipairs(self.blobs) do if b.owner == owner then out[#out + 1] = b end end
  return out
end

function Game:player_cells() return self:owner_cells("p") end

-- 某家的总质量 / 质心（相机与读数用）
function Game:owner_mass(owner)
  local m = 0
  for _, b in ipairs(self.blobs) do if b.owner == owner then m = m + b.r * b.r end end
  return m
end

function Game:mass() return self:owner_mass("p") end

function Game:centroid()
  local m, cx, cy = 0, 0, 0
  for _, b in ipairs(self.blobs) do
    if b.owner == "p" then m = m + b.r * b.r; cx = cx + b.x * b.r * b.r; cy = cy + b.y * b.r * b.r end
  end
  if m <= 0 then return Game.WORLD_W / 2, Game.WORLD_H / 2 end
  return cx / m, cy / m
end

-- 排行榜：按**家**聚合（玩家所有细胞合成一行），按总质量降序
function Game:leaderboard()
  local by_owner, order = {}, {}
  for _, b in ipairs(self.blobs) do
    local e = by_owner[b.owner]
    if not e then
      e = { owner = b.owner, role = b.role, hue = b.hue, m = 0 }
      by_owner[b.owner] = e; order[#order + 1] = e
    end
    e.m = e.m + b.r * b.r
  end
  table.sort(order, function(x, y) return x.m > y.m end)
  return order
end

function Game:drop_food()
  self.food[#self.food + 1] = { x = self.rand(2, Game.WORLD_W - 2),
                                y = self.rand(2, Game.WORLD_H - 2), vx = 0, vy = 0 }
end

-- 刺球生成：**绝不落在任何球（含身体范围）底下**——否则"走着走着被迫分裂"没有策略可言
function Game:spawn_spike()
  local bx, by
  for _ = 1, 40 do
    bx, by = self.rand(SPIKE_CLEAR, Game.WORLD_W - SPIKE_CLEAR), self.rand(SPIKE_CLEAR, Game.WORLD_H - SPIKE_CLEAR)
    local ok = true
    for _, b in ipairs(self.blobs) do
      if hypot(bx - b.x, by - b.y) < b.r + SPIKE_CLEAR then ok = false break end
    end
    if ok then break end
  end
  self.spikes[#self.spikes + 1] = { x = bx, y = by }
end

function Game:spawn_ai()
  local px, py = Game.WORLD_W / 2, Game.WORLD_H / 2
  local bx, by
  for _ = 1, 20 do
    bx, by = self.rand(6, Game.WORLD_W - 6), self.rand(6, Game.WORLD_H - 6)
    if hypot(bx - px, by - py) > 45 then break end
  end
  self.ai_seq = self.ai_seq + 1
  local c = self:new_cell(bx, by, 0.8 + self.rand() * 0.9, "ai", "a" .. self.ai_seq)
  c.hue = self.ai_seq
  c.tx, c.ty = self.rand(2, Game.WORLD_W - 2), self.rand(2, Game.WORLD_H - 2)
  self.blobs[#self.blobs + 1] = c
end

function Game:steer(dx, dy)
  self.dirx, self.diry = dx, dy
end

-- 通用：把 owner 的每颗够大的细胞一分为二（玩家按 X、电脑按策略、吃刺球强制都走它）
function Game:split_owner(owner, ux, uy, forced)
  if not self.alive then return 0 end
  local cells = self:owner_cells(owner)
  local room = Game.MAX_CELLS - #cells
  if room <= 0 then return 0 end
  local spawn = {}
  for _, c in ipairs(cells) do
    if room <= 0 then break end
    if c.r >= (forced and (SPIKE_MIN * 0.6) or Game.SPLIT_MIN) then
      c.r = c.r / math.sqrt(2)
      c.merge_t = Game.MERGE_DELAY
      local n = self:new_cell(c.x, c.y, c.r, c.role, owner)
      n.hue = c.hue
      n.bvx, n.bvy = ux * SPLIT_BOOST, uy * SPLIT_BOOST
      n.boost_t = BOOST_TIME
      n.merge_t = Game.MERGE_DELAY
      spawn[#spawn + 1] = n
      room = room - 1
    end
  end
  for _, n in ipairs(spawn) do self.blobs[#self.blobs + 1] = n end
  return #spawn
end

function Game:split()                       -- 玩家 X：朝行进方向
  local dl = hypot(self.dirx, self.diry)
  if dl < 0.01 then return end
  self:split_owner("p", self.dirx / dl, self.diry / dl, false)
end

-- 通用：owner 从每颗够大的细胞朝 (ux,uy) 吐一颗食物
function Game:eject_owner(owner, ux, uy, dt)
  self.eject_t = self.eject_t - dt
  if self.eject_t > 0 then return end
  self.eject_t = EJECT_INTERVAL
  for _, c in ipairs(self:owner_cells(owner)) do
    if c.r >= EJECT_MIN then
      c.r = math.sqrt(math.max(0.01, c.r * c.r - EJECT_COST))
      self.food[#self.food + 1] = {
        x = c.x + ux * (c.r + 1.1), y = c.y + uy * (c.r + 1.1),
        vx = ux * FOOD_SPEED, vy = uy * FOOD_SPEED,
      }
    end
  end
end

function Game:eject(dt)
  local dl = hypot(self.dirx, self.diry)
  if dl < 0.01 then return end
  self:eject_owner("p", self.dirx / dl, self.diry / dl, dt)
end

-- ── 敌人 AI：局势驱动 ─────────────────────────────────────────
-- 见文件头思路：威胁→逃（贴太紧就弃重提速）；猎物→追（小于一半且在扑程内→向前分裂）；
-- 否则觅食/游荡。每颗细胞各自 think；分裂/吐食各有冷却
function Game:think_ai(b, dt)
  if b.atk_cd > 0 then b.atk_cd = b.atk_cd - dt end
  if b.ej_cd > 0 then b.ej_cd = b.ej_cd - dt end
  b.think = b.think - dt
  if b.think > 0 then return end
  b.think = 0.3

  local flee_x, flee_y, threat, near_threat = 0, 0, 0, 0
  local best_d, prey = math.huge, nil
  for _, o in ipairs(self.blobs) do
    if o.owner ~= b.owner then
      local dx, dy, d = o.x - b.x, o.y - b.y, hypot(o.x - b.x, o.y - b.y)
      if o.r > b.r * EAT_RATIO and d < b.r + o.r + 12 then
        threat = threat + 1 / (d + 0.5)
        flee_x, flee_y = flee_x - dx / (d + 0.1), flee_y - dy / (d + 0.1)
        if d < near_threat or near_threat == 0 then near_threat = d end
      elseif b.r > o.r * EAT_RATIO and d < 22 and d < best_d then
        best_d, prey = d, o
      end
    end
  end

  if threat > 0 then
    -- 逃命方向必须归一化（加权和长度随距离变小，直接当目标点会停在原地）
    local fl = hypot(flee_x, flee_y)
    if fl > 0.001 then
      b.tx, b.ty = b.x + flee_x / fl * 24, b.y + flee_y / fl * 24
    else
      b.tx, b.ty = b.x + 24, b.y
    end
    -- 被贴得很近又还背着不少肉 → 吐食减重提速（小=快）。代价是喂了追兵——最后一招
    if near_threat > 0 and near_threat < AI_EJECT_THREAT and b.ej_cd <= 0 and b.r >= EJECT_MIN then
      local dl = hypot(flee_x, flee_y)
      if dl > 0.001 then
        self:eject_owner(b.owner, flee_x / dl, flee_y / dl, 999)  -- 冷却由 ej_cd 控制
      end
      b.ej_cd = AI_EJECT_CD
    end
  elseif prey then
    b.tx, b.ty = prey.x, prey.y
    -- 猎物 < 自己一半、且在扑程内 → 向前分裂扑杀（每半个仍吃得下它）
    if b.atk_cd <= 0 and prey.r < b.r * AI_SPLIT_PREY and best_d < AI_SPLIT_REACH
       and b.r >= Game.SPLIT_MIN then
      local dx, dy = prey.x - b.x, prey.y - b.y
      local dl = hypot(dx, dy)
      if dl > 0.01 then self:split_owner(b.owner, dx / dl, dy / dl, false) end
      b.atk_cd = AI_SPLIT_CD
    end
  elseif hypot(b.tx - b.x, b.ty - b.y) < 3 then
    b.tx, b.ty = self.rand(2, Game.WORLD_W - 2), self.rand(2, Game.WORLD_H - 2)
  end
end

local function move_cell(b, dx, dy, dt, w, h)
  local sp = speed_of(b.r)
  b.vx, b.vy = dx * sp, dy * sp
  b.x = b.x + b.vx * dt
  b.y = b.y + b.vy * dt
  clamp_center(b, w, h)
end

-- 同一家的两颗细胞：到点前"迅速聚拢成贴但不叠"，到点后取消碰撞、相吸合并
local function resolve_pair(a, b, dt)
  local dx, dy = b.x - a.x, b.y - a.y
  local d = hypot(dx, dy)
  if d < 0.0001 then d = 0.0001 end
  local ux, uy = dx / d, dy / d
  local sum = a.r + b.r
  if a.merge_t <= 0 and b.merge_t <= 0 then
    if d < sum * 0.5 then                                  -- 叠够深 → 合并
      local ma, mb = a.r * a.r, b.r * b.r
      a.x = (a.x * ma + b.x * mb) / (ma + mb)
      a.y = (a.y * ma + b.y * mb) / (ma + mb)
      a.r = math.sqrt(ma + mb)
      return true
    end
    local pull = math.min(6 * dt, d * 0.5)                 -- 取消碰撞、相吸
    a.x = a.x + ux * pull; a.y = a.y + uy * pull
    b.x = b.x - ux * pull; b.y = b.y - uy * pull
  elseif d > sum then
    local pull = math.min(9 * dt, (d - sum) * 0.5)         -- 迅速聚拢到贴住为止
    a.x = a.x + ux * pull; a.y = a.y + uy * pull
    b.x = b.x - ux * pull; b.y = b.y - uy * pull
  else
    local push = (sum - d) * 0.5                           -- 贴住/重叠 → 推开（贴而不叠）
    a.x = a.x - ux * push; a.y = a.y - uy * push
    b.x = b.x + ux * push; b.y = b.y + uy * push
  end
  return false
end

function Game:update(dt)
  if not self.alive then return {} end
  self.time = self.time + dt
  local events = {}
  local W, H = Game.WORLD_W, Game.WORLD_H

  -- 出球 / 补刺球
  self.ai_timer = self.ai_timer - dt
  if self.ai_timer <= 0 then
    self.ai_timer = AI_SPAWN_EVERY
    local ais = 0
    for _, b in ipairs(self.blobs) do if b.role == "ai" then ais = ais + 1 end end
    if ais < MAX_AI then self:spawn_ai() end
  end
  while #self.spikes < SPIKE_COUNT do self:spawn_spike() end

  -- 玩家：所有细胞共用行进方向；弹射衰减；合并计时倒数
  local dl = hypot(self.dirx, self.diry)
  local ux, uy = 0, 0
  if dl > 0 then ux, uy = self.dirx / dl, self.diry / dl end
  for _, b in ipairs(self.blobs) do
    if b.role == "player" then
      if dl > 0 then move_cell(b, ux, uy, dt, W, H) else b.vx, b.vy = 0, 0 end
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
      if d > 0.4 then move_cell(b, tx / d, ty / d, dt, W, H) else b.vx, b.vy = 0, 0 end
      if b.boost_t > 0 then
        b.boost_t = math.max(0, b.boost_t - dt)
        local f = b.boost_t / BOOST_TIME
        b.x = b.x + b.bvx * f * dt
        b.y = b.y + b.bvy * f * dt
        clamp_center(b, W, H)
      end
      if b.merge_t > 0 then b.merge_t = math.max(0, b.merge_t - dt) end
    end
  end

  -- 食物与刺球：吐出的会飞、会减速（动态）
  for _, f in ipairs(self.food) do
    if f.vx ~= 0 or f.vy ~= 0 then
      f.x = f.x + f.vx * dt; f.y = f.y + f.vy * dt
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

  -- 吃刺球：需要够大才吃得下；吃下**强制分裂**并涨很多
  for i = #self.spikes, 1, -1 do
    local s = self.spikes[i]
    for _, b in ipairs(self.blobs) do
      if b.r >= SPIKE_MIN and hypot(s.x - b.x, s.y - b.y) < b.r + SPIKE_R then
        b.r = math.sqrt(b.r * b.r + SPIKE_GAIN)
        table.remove(self.spikes, i)
        -- 强制分裂：朝当前朝向（无方向则朝右）扑开
        local dx, dy = b.vx, b.vy
        local dl = hypot(dx, dy)
        if dl < 0.01 then dx, dy, dl = 1, 0, 1 end
        self:split_owner(b.owner, dx / dl, dy / dl, true)
        self.bursts[#self.bursts + 1] = { x = s.x, y = s.y, t = 0.4 }
        if b.role == "player" then events.spike = true end
        break
      end
    end
  end
  for j = #self.bursts, 1, -1 do
    self.bursts[j].t = self.bursts[j].t - dt
    if self.bursts[j].t <= 0 then table.remove(self.bursts, j) end
  end

  -- 两两结算：同家 = 聚拢/碰撞/合并；异家 = 吞噬
  local removed = {}
  for i = 1, #self.blobs do
    for j = i + 1, #self.blobs do
      if not removed[i] and not removed[j] then
        local a, b = self.blobs[i], self.blobs[j]
        if a.owner == b.owner then
          if resolve_pair(a, b, dt) then removed[j] = true end
        else
          local big, small, si = a, b, j
          if a.r < b.r then big, small, si = b, a, i end
          if big.r > small.r * EAT_RATIO and
             hypot(big.x - small.x, big.y - small.y) < big.r * 0.95 then
            big.r = math.sqrt(big.r * big.r + small.r * small.r)
            removed[si] = true
            if small.role == "player" then
              events.lost = true                       -- 掉了一个分身
            else
              events.kill = true
              if big.role == "player" then self.eaten = self.eaten + 1 end
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
    size = math.sqrt(self:mass()), cells = #self:player_cells(),
    px = cx, py = cy, world_w = Game.WORLD_W, world_h = Game.WORLD_H,
    blobs = #self.blobs, food = #self.food, spikes = #self.spikes,
    score = math.floor(self.eaten * 10 + math.sqrt(self.best_m) * 20),
  }
end

return Game

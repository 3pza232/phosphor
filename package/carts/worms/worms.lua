-- worms.lua —— 虫子：血量与状态机。不读键盘、不绘制、不发声
--
-- 一只虫子由上层用"意图"驱动（move / jump），这里只判定"能不能这么做"，
-- 并推进自己的状态：走路、爬坡、跳跃、坠落、受伤、淹死。
-- 坐标用"脚下中心点"（子格），这样站立判定就是"正下方那几格有没有实心"。

local Physics = require("physics")
local Weapons = require("weapons")

local Worms = {}
Worms.__index = Worms

Worms.MAX_HP = 100
Worms.WALK_SPEED = 10      -- 子格/秒（= 5 格/秒）
Worms.JUMP_VY = -9         -- 起跳初速（负值 = 向上）；跳不高，爬台阶够用
Worms.HIT_RADIUS = 3       -- 被弹药命中的判定半径（子格）

local function make(team, x, y)
  return {
    team = team,
    x = x, y = y,               -- 脚下中心（子格）
    vy = 0,
    hp = Worms.MAX_HP,
    alive = true,
    on_ground = true,
    fall_from = nil,
    facing = (team == 1) and 1 or -1,
    angle = 45,                 -- 瞄准角度（度，可以为负 = 朝下打）
    -- power 不在这里定：默认力度属于"操作手感"，由装配层（main.lua 的
    -- DEFAULT_POWER）给，弹药也一样。这里只管虫子的物理状态
    power = nil,
    -- 弹药**按虫各记各的**：同一件武器，这只虫的份额不会被队友用掉
    ammo = Weapons.start_ammo(),
  }
end

-- 部署两队：一队在左三分之一、一队在右三分之一。
-- counts 是 { 我方人数, 敌方人数 }（传一个数字表示两边一样多）。
-- 每个人数都走 terrain:spawn_spot —— 它会**先把脚下压平**再放虫，
-- 所以"随机地形 + 出生即卡死在石头里"这件事不会发生。
function Worms.new(terrain, counts)
  local self = setmetatable({}, Worms)
  self.terrain = terrain
  self.list = {}
  local n = { 4, 4 }
  if type(counts) == "table" then
    n = { counts[1] or 4, counts[2] or 4 }
  elseif type(counts) == "number" then
    n = { counts, counts }
  end
  for team = 1, 2 do
    local span = terrain.W // 3
    for i = 1, n[team] do
      -- 在各自的三分之一里均匀铺开，两两之间留出空地，免得叠在一起
      local step = span // (n[team] + 1)
      local x = (team == 1) and (i * step) or (terrain.W - i * step)
      local gx, gy = terrain:spawn_spot(x)
      if gx then self.list[#self.list + 1] = make(team, gx, gy) end
    end
  end
  return self
end

function Worms:of_team(team)
  local out = {}
  for _, w in ipairs(self.list) do
    if w.alive and w.team == team then out[#out + 1] = w end
  end
  return out
end

-- 该队里排在 after 之后的第一只活虫。回合换手用它，**不是每次都抓第一只**：
-- 一条命从头用到尾的话，队友像不存在，玩家也永远看不到别的虫子在哪。
function Worms:next_of_team(team, after)
  local list = self:of_team(team)
  if #list == 0 then return nil end
  if not after then return list[1] end
  local seen = false
  for _, w in ipairs(list) do
    if seen then return w end
    if w == after then seen = true end
  end
  return list[1]        -- 已经是最后一个（或它已阵亡）→ 绕回第一个
end

function Worms:alive_count(team) return #self:of_team(team) end

-- 脚下三格内有实心就算站得住
function Worms:supported(w)
  local t, x, y = self.terrain, math.floor(w.x), math.floor(w.y + 1)
  return t:solid(x - 1, y) or t:solid(x, y) or t:solid(x + 1, y)
end

-- 走：只在地面上走；前方台阶高出 2 子格以上就停住（爬坡要靠跳）
function Worms:move(w, dir, dt)
  if not w.alive or not w.on_ground then return end
  local nx = w.x + dir * Worms.WALK_SPEED * dt
  if nx < 3 or nx > self.terrain.W - 3 then w.facing = dir return end
  if self.terrain:solid(math.floor(nx), math.floor(w.y)) then
    w.facing = dir
    return
  end
  w.x, w.facing = nx, dir
end

function Worms:jump(w)
  if not w.alive or not w.on_ground then return false end
  w.vy = Worms.JUMP_VY
  w.on_ground = false
  w.fall_from = w.y
  return true
end

-- 重力与落地。返回事件表（landed / drowned / hurt），由上层决定音效等副作用
function Worms:update(dt)
  local events = {}
  for _, w in ipairs(self.list) do
    if w.alive then
      if w.on_ground and not self:supported(w) then
        w.on_ground = false
        w.fall_from = w.y
      end
      if not w.on_ground then
        w.vy = w.vy + Physics.GRAVITY * dt
        w.y = w.y + w.vy * dt
        if w.vy >= 0 and self:supported(w) then
          local dmg = Physics.fall_damage(w.y - (w.fall_from or w.y))
          w.y = math.floor(w.y)
          w.vy, w.on_ground, w.fall_from = 0, true, nil
          if dmg > 0 then
            self:damage(w, dmg)
            events[#events + 1] = { kind = "landed", worm = w, damage = dmg }
          end
        end
      else
        -- 贴地：吸附到地表，上坡下坡时不会浮空
        local _, gy = self.terrain:find_ground(math.floor(w.x), math.floor(w.y + 2))
        if gy then w.y = gy end
      end
      if w.y >= self.terrain.WATER_Y then
        w.hp, w.alive = 0, false
        events[#events + 1] = { kind = "drowned", worm = w }
      end
    end
  end
  return events
end

function Worms:damage(w, amount)
  if not w.alive or amount <= 0 then return end
  w.hp = w.hp - amount
  if w.hp <= 0 then w.hp, w.alive = 0, false end
end

-- 爆炸结算：伤害 + 冲量（把人往外推；推完交给 update 的重力继续算）
function Worms:apply_blast(x, y, radius, damage, events)
  local points = {}
  for _, w in ipairs(self.list) do
    if w.alive then points[#points + 1] = w end
  end
  local hits = Physics.blast(x, y, radius, damage, points, self.terrain)
  for _, h in ipairs(hits) do
    local w = h.point
    self:damage(w, h.damage)
    local dx, dy = w.x - x, w.y - y
    local d = math.max(1, math.sqrt(dx * dx + dy * dy))
    w.x = w.x + dx / d * h.push * 0.5
    w.y = w.y + dy / d * h.push * 0.5
    w.on_ground, w.fall_from = false, w.y
    events[#events + 1] = { kind = "hit", worm = w, damage = h.damage }
  end
  return hits
end

function Worms:team_wiped(team) return self:alive_count(team) == 0 end

return Worms

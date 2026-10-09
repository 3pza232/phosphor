-- ai.lua —— 电脑队：扫描角度×力度 → 用同一份 physics 预演 → 选最优 + 加误差
--
-- 两条硬约束决定了这里的写法：
--   1. 预演必须走**同一份 physics**（连子步都共用），否则 AI 挑中的角度在实弹里不成立；
--      手雷的弹跳也不例外——自己写一套"撞地就停"的近似弹道，算出来的落点是假的。
--   2. 主机有"单次调用不得超过 100 毫秒"的看门狗，几百组候选一次算完会被当场掐掉
--      （cart error: exceeded 100 ms in one call）。所以规划器**可分帧推进**：
--      每帧只算一小批，AI 想 0.2~0.4 秒再开炮，画面不掉帧、也不会触发看门狗。
--
-- 预演时给 Physics.blast 传 nil 地形 —— 否则 AI 每想一次就把地图挖一遍。

local Physics = require("physics")
local Worms = require("worms")
local Weapons = require("weapons")

local AI = {}
local HIT_R2 = Worms.HIT_RADIUS * Worms.HIT_RADIUS

AI.PREVIEW_DT = 1 / 30      -- 预演的时间步（秒）：真正的物理，只是不画画面
AI.PREVIEW_MAX_T = 14       -- 一枚弹药最多预演这么久
AI.BATCH = 20               -- 每帧最多预演多少组（实测远低于 100 毫秒）

-- 难度：瞄准误差（度 / 力度）+ 扫描密度。两遍扫：先粗定区域，再在附近精修
AI.DIFFICULTY = {
  easy = { angle = 6, power = 0.08, a_step = 12, p_step = 0.12, refine = false },
  normal = { angle = 3, power = 0.04, a_step = 10, p_step = 0.1, refine = true },
  hard = { angle = 1, power = 0.015, a_step = 8, p_step = 0.08, refine = true },
}

-- 用真 physics 飞一次，返回命中点与"直接命中"的那只虫
local function preview(shooter, weapon, angle, power, wind, terrain, enemies)
  local keep_a, keep_p = shooter.angle, shooter.power
  shooter.angle, shooter.power = angle, power
  local p = Weapons.fire(weapon, shooter)
  shooter.angle, shooter.power = keep_a, keep_p

  local hit_worm = nil
  local function probe(x, y)
    if x < 1 or x > terrain.W or y < 1 or y > terrain.H then return "out" end
    if terrain:solid(math.floor(x), math.floor(y)) then return "terrain" end
    if y >= terrain.WATER_Y then return "water" end
    for _, e in ipairs(enemies) do
      if e.alive then
        local dx, dy = e.x - x, e.y - y
        if dx * dx + dy * dy <= HIT_R2 then hit_worm = e return "worm", e end
      end
    end
    return nil
  end

  local t = 0
  while t < AI.PREVIEW_MAX_T do
    local kind = Physics.step(p, AI.PREVIEW_DT, wind, probe)
    t = t + AI.PREVIEW_DT
    if kind then return p.x, p.y, hit_worm end
  end
  return p.x, p.y, hit_worm
end

-- 一次候选的评分：能直击最好，其次是尽量靠近；并扣掉自伤与"炸自己脚"
local function score_of(weapon, hit_x, hit_y, hit_enemy, enemies, mine)
  local score = hit_enemy and 120 or 0
  local best = 9999
  for _, e in ipairs(enemies) do
    if e.alive then
      local dx, dy = e.x - hit_x, e.y - hit_y
      best = math.min(best, math.sqrt(dx * dx + dy * dy))
    end
  end
  score = score - best
  -- 自伤：同一套公式，但不动地形（terrain = nil）；ai_mult 只放大集束的"看不见的"
  -- 那几枚子弹药，让 AI 不会把 15 伤害的母弹当成废物
  local hits = Physics.blast(hit_x, hit_y, weapon.radius, weapon.damage, mine, nil)
  for _, h in ipairs(hits) do score = score - h.damage * 0.8 * (weapon.ai_mult or 1) end
  return score
end

-- 规划器：持有候选队列，可以分帧推进
local Planner = {}
Planner.__index = Planner

local function jobs_for(weapon, a0, a1, a_step, p0, p1, p_step)
  local jobs = {}
  for angle = a0, a1, a_step do
    for power = p0, p1, p_step do
      jobs[#jobs + 1] = { weapon, angle, power }
    end
  end
  return jobs
end

-- 开始规划。返回可推进的规划器，或 nil（没有敌人 / 没有可用武器）
function AI.plan_begin(shooter, all_worms, terrain, wind, difficulty, allowed)
  local cfg = AI.DIFFICULTY[difficulty or "normal"]
  local enemies, mine = {}, {}
  for _, w in ipairs(all_worms) do
    if w.alive then
      if w.team == shooter.team then mine[#mine + 1] = w else enemies[#enemies + 1] = w end
    end
  end
  if #enemies == 0 then return nil end

  local jobs = {}
  for _, id in ipairs(allowed or { "bazooka" }) do
    local weapon = Weapons.by_id(id)
    if weapon then
      for _, job in ipairs(jobs_for(weapon, 40, 140, cfg.a_step, 0.25, 1.0, cfg.p_step)) do
        jobs[#jobs + 1] = job
      end
    end
  end
  if #jobs == 0 then return nil end

  return setmetatable({
    shooter = shooter, enemies = enemies, mine = mine,
    terrain = terrain, wind = wind, cfg = cfg,
    jobs = jobs, index = 1, phase = 1, best = nil, done = false,
  }, Planner)
end

-- 推进最多 batch 组预演。返回 true 表示已经算完（可以取结果了）
function Planner:advance(batch)
  batch = batch or AI.BATCH
  local spent = 0
  while self.index <= #self.jobs and spent < batch do
    local job = self.jobs[self.index]
    self.index = self.index + 1
    spent = spent + 1
    local weapon, angle, power = job[1], job[2], job[3]
    local hx, hy, enemy = preview(self.shooter, weapon, angle, power,
                                  self.wind, self.terrain, self.enemies)
    local s = score_of(weapon, hx, hy, enemy, self.enemies, self.mine)
    if not self.best or s > self.best.score then
      self.best = { weapon = weapon, angle = angle, power = power, score = s }
    end
  end

  if self.index > #self.jobs then
    if self.phase == 1 and self.cfg.refine and self.best then
      -- 精修一遍：围着粗扫找到的那一组细看，误差是之后才加的，这里要的是准
      local cfg = self.cfg
      local b = self.best
      self.jobs = jobs_for(b.weapon, b.angle - cfg.a_step, b.angle + cfg.a_step, 2,
                           math.max(0.15, b.power - cfg.p_step),
                           math.min(1.0, b.power + cfg.p_step), 0.02)
      self.index, self.phase = 1, 2
      return false
    end
    self.done = true
  end
  return self.done
end

-- 结果：加瞄准误差。AI 强在"会算"，弱在"手抖"，而不是物理作弊。
-- phos.sys.random 只收整数，所以先把误差换算成"十分之一度 / 千分之一力度"
function Planner:result()
  local b, cfg = self.best, self.cfg
  if not b then return nil end
  local aj, pj = math.floor(cfg.angle * 10), math.floor(cfg.power * 1000)
  return {
    weapon = b.weapon,
    angle = b.angle + phos.sys.random(-aj, aj) / 10,
    power = math.max(0.1, math.min(1.0, b.power + phos.sys.random(-pj, pj) / 1000)),
  }
end

return AI

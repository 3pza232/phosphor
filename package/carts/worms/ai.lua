-- ai.lua —— 电脑队：扫描角度×力度 → 用同一份 physics 预演 → 选最优 + 加误差
--
-- 三条硬约束决定了这里的写法：
--   1. 预演必须走**同一份 physics**（连子步都共用），否则 AI 挑中的角度在实弹里不成立；
--      手雷的弹跳也不例外——自己写一套"撞地就停"的近似弹道，算出来的落点是假的。
--   2. 主机有"单次调用不得超过 100 毫秒"的看门狗，几百组候选一次算完会被当场掐掉。
--      所以规划器**可分帧推进**：每帧只算一小批，想 0.2~0.4 秒再开炮。
--   3. 预演时给 Physics.blast 传 nil 地形——否则 AI 每想一次就把地图挖一遍。
--
-- "想打谁"由武器自己决定：攻击弹瞄敌人，治疗弹瞄**血量偏低的队友**，
-- 两者共用同一套"越近越好 + 直击加分"的判据，所以走位/瞄准逻辑只有一份。
--
-- 结果里额外带出 `near`：最优落点离最近目标还有多远（子格）。
-- 上层用它判断"这一炮到底有没有射击条件"，据此决定是开炮还是先换个位置。

local Physics = require("physics")
local Worms = require("worms")
local Weapons = require("weapons")

local AI = {}
local HIT_R2 = Worms.HIT_RADIUS * Worms.HIT_RADIUS

AI.PREVIEW_DT = 1 / 30      -- 预演的时间步（秒）：真正的物理，只是不画画面
AI.PREVIEW_MAX_T = 14       -- 一枚弹药最多预演这么久
AI.BATCH = 20               -- 每帧最多预演多少组（实测远低于 100 毫秒）
-- 血量不超过这个比例就算"伤员"，值得用治疗弹。
-- 用"不超过"而不是"低于"：本作的伤害值（8/10/25/30/50）经常正好把血打到 50，
-- 卡在严格小于上会让最需要治疗的那只恰好被跳过
AI.WOUNDED_RATIO = 0.5

-- 难度：决定"算得多细""手有多稳""什么时候肯换位置"，但**没有一档是必中**——
-- 越难只是把误差压小、扫描做细、走位更积极，最后一击仍要看风向与地形
--   angle/power      瞄准误差（度 / 力度比例）
--   a_step/p_step    粗扫密度；refine 是否再围着最优解精修一遍
--   good_dist        落点离目标多近才算"打得到"（子格）；够不着就先走位
--   dodge            上一轮被炸到之后，这一轮选择换位置的百分比
--   walk_time        真挪起来走多久（秒）
AI.DIFFICULTY = {
  easy = { angle = 6, power = 0.10, a_step = 14, p_step = 0.15, refine = false,
           good_dist = 14, dodge = 25, walk_time = 0.5 },
  normal = { angle = 3, power = 0.04, a_step = 10, p_step = 0.10, refine = true,
             good_dist = 9, dodge = 55, walk_time = 1.0 },
  hard = { angle = 1, power = 0.015, a_step = 8, p_step = 0.08, refine = true,
           good_dist = 6, dodge = 85, walk_time = 1.6 },
}

local LASER_GOOD = 3        -- 激光射线离目标中心多近算"擦得到"（子格）

-- 用真 physics 飞一次，返回落点与"直接命中"的那只虫
local function preview(shooter, weapon, angle, power, wind, terrain, targets)
  local keep_a, keep_p = shooter.angle, shooter.power
  shooter.angle, shooter.power = angle, power
  local p = Weapons.fire(weapon, shooter)
  shooter.angle, shooter.power = keep_a, keep_p

  local hit_worm = nil
  local function probe(x, y)
    if x < 1 or x > terrain.W or y > terrain.H then return "out" end
    if y < 1 then return nil end
    if terrain:solid(math.floor(x), math.floor(y)) then return "terrain" end
    if y >= terrain.WATER_Y then return "water" end
    for _, t in ipairs(targets) do
      if t.alive then
        local dx, dy = t.x - x, t.y - y
        if dx * dx + dy * dy <= HIT_R2 then hit_worm = t return "worm", t end
      end
    end
    return nil
  end

  local t = 0
  while t < AI.PREVIEW_MAX_T do
    local kind = Physics.step(p, AI.PREVIEW_DT, wind, probe)
    t = t + AI.PREVIEW_DT
    if kind then break end
  end
  return p.x, p.y, hit_worm
end

-- 点到线段的距离：激光不是弹道，只能靠它判断"这条线擦不擦得到目标"
local function ray_distance(ox, oy, dx, dy, len, px, py)
  local vx, vy = px - ox, py - oy
  local t = vx * dx + vy * dy
  if t < 0 then t = 0 elseif t > len then t = len end
  local cx, cy = ox + dx * t, oy + dy * t
  return math.sqrt((px - cx) ^ 2 + (py - cy) ^ 2)
end

-- 激光的评分：射线贴着目标才算好；贴不上就按"差多远"平滑降分
local function laser_score(shooter, weapon, angle, targets)
  local a = math.rad(angle)
  local dx, dy = math.cos(a) * shooter.facing, -math.sin(a)
  local ox, oy = Physics.muzzle_of(shooter)
  local reach = 200
  local near = 9999
  for _, t in ipairs(targets) do
    if t.alive then
      -- 瞄身体中段（脚下往上 4 子格），不然贴着头顶过也算不中
      local d = ray_distance(ox, oy, dx, dy, reach, t.x, t.y - 4)
      if d < near then near = d end
    end
  end
  return (near <= LASER_GOOD) and 90 or (20 - near), near
end

-- 一次候选的评分。要的不是"这一炮打得最爽"，而是**整场仗打下来伤得最多**：
--   1. 主项是这一炮**真能造成的伤害**：用同一份 Physics.blast 在落点上算，
--      半径外的目标自然是 0 分。不能拿"离目标多近"当主项 —— 近不等于疼，
--      火箭筒擦身而过比普通弹贴脸更值钱
--   2. 直击再加一点分：打断走位、把人推下坡这些价值量不出来，但确实存在
--   3. 无限弹（普通炮弹）扣一档：限量弹还有货时，它不该占 AI 的回合。
--      否则"手里有 50 伤的火箭筒，却一直用 10 伤的普通弹磨"，玩家一眼就看穿
--   4. 自伤照旧重罚；散射/集束这类"预演只看得到一枚"的用 ai_mult 放大
-- targets 是"这一炮想打中的东西"（攻击弹 = 敌人，治疗弹 = 伤员），
-- avoid 是"不该炸到的东西"（自己队；治疗弹不需要）
local DAMAGE_W = 3         -- 每点伤害值多少分
local HIT_BONUS = 40       -- 直击额外分
local NEAR_W = 1           -- 每偏离目标 1 子格扣多少分
local NEAR_CAP = 60        -- 偏离扣分上限：没打中时靠它挑"谁离得最近"
local SHELL_PENALTY = 30   -- 无限弹的机会成本（上面第 3 条）
local SELF_W = 0.8         -- 自伤权重

local function score_of(weapon, hit_x, hit_y, hit_enemy, targets, avoid)
  local is_heal = (weapon.heal or 0) > 0
  local near = 9999
  for _, t in ipairs(targets) do
    if t.alive then
      local dx, dy = t.x - hit_x, t.y - hit_y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < near then near = d end
    end
  end

  -- 治疗弹按"回血量"计分（同一把尺子）；其余按落点上的真实爆炸伤害
  local dealt = weapon.heal or 0
  if not is_heal then
    local hits = Physics.blast(hit_x, hit_y, weapon.radius, weapon.damage, targets, nil)
    for _, h in ipairs(hits) do dealt = dealt + h.damage end
  end
  dealt = dealt * (weapon.ai_mult or 1)

  local score = dealt * DAMAGE_W
                + (hit_enemy and HIT_BONUS or 0)
                - math.min(near, NEAR_CAP) * NEAR_W
  if #avoid > 0 and (weapon.damage or 0) > 0 then
    local hits = Physics.blast(hit_x, hit_y, weapon.radius, weapon.damage, avoid, nil)
    for _, h in ipairs(hits) do score = score - h.damage * SELF_W * (weapon.ai_mult or 1) end
  end
  if (weapon.ammo or 0) < 0 then score = score - SHELL_PENALTY end
  return score, near
end

-- 规划器：持有候选队列，可以分帧推进
local Planner = {}
Planner.__index = Planner

local function jobs_for(weapon, a0, a1, a_step, p0, p1, p_step)
  local jobs = {}
  -- 激光只看角度：它走直线、不落不炸，力度对结果没有影响
  local step_p = (weapon.kind == "laser") and 1.0 or p_step
  for angle = a0, a1, a_step do
    for power = p0, p1, step_p do
      jobs[#jobs + 1] = { weapon, angle, power }
    end
  end
  return jobs
end

-- 开始规划。返回可推进的规划器，或 nil（没有目标 / 没有可用武器）
function AI.plan_begin(shooter, all_worms, terrain, wind, difficulty, allowed)
  local cfg = AI.DIFFICULTY[difficulty or "normal"]
  local enemies, mine, wounded = {}, {}, {}
  for _, w in ipairs(all_worms) do
    if w.alive then
      if w.team == shooter.team then
        mine[#mine + 1] = w
        if w.hp <= Worms.MAX_HP * AI.WOUNDED_RATIO then wounded[#wounded + 1] = w end
      else
        enemies[#enemies + 1] = w
      end
    end
  end
  if #enemies == 0 then return nil end

  local jobs = {}
  for _, id in ipairs(allowed or { "bazooka" }) do
    local weapon = Weapons.by_id(id)
    if weapon then
      -- 治疗弹打队友、其余打敌人；两者都用同一套"越近越好"的判据
      local targets = ((weapon.heal or 0) > 0) and wounded or enemies
      if #targets > 0 then
        -- 激光是**射线**，没有抛物线：它的角度可以低到几乎水平（甚至朝下），
        -- 用抛射弹那套 40°~140° 的仰角去扫，射线只会飞上天
        local a0, a1, step = 40, 140, cfg.a_step
        if weapon.kind == "laser" then a0, a1, step = -40, 80, 4 end
        for _, job in ipairs(jobs_for(weapon, a0, a1, step, 0.25, 1.0, cfg.p_step)) do
          jobs[#jobs + 1] = job
        end
      end
    end
  end
  if #jobs == 0 then return nil end

  return setmetatable({
    shooter = shooter, enemies = enemies, mine = mine, wounded = wounded,
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
    local is_heal = (weapon.heal or 0) > 0
    local targets = is_heal and self.wounded or self.enemies
    local avoid = is_heal and {} or self.mine

    local score, near
    if weapon.kind == "laser" then
      score, near = laser_score(self.shooter, weapon, angle, targets)
    else
      local hx, hy, hit = preview(self.shooter, weapon, angle, power,
                                  self.wind, self.terrain, targets)
      score, near = score_of(weapon, hx, hy, hit, targets, avoid)
    end
    if not self.best or score > self.best.score then
      self.best = { weapon = weapon, angle = angle, power = power, score = score, near = near }
    end
  end

  if self.index > #self.jobs then
    if self.phase == 1 and self.cfg.refine and self.best and self.best.weapon.kind ~= "laser" then
      -- 精修一遍：围着粗扫找到的那一组细看，误差是之后才加的，这里要的是准
      local cfg, b = self.cfg, self.best
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
    near = b.near,
  }
end

return AI

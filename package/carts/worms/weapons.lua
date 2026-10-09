-- weapons.lua —— 武器表 + 通用发射器
--
-- 武器是**数据**：改数值不必碰逻辑。平衡原则见 DESIGN.md —— 总破坏面积大致恒定，
-- 所以半径大则单体伤害低。
--
-- 稀有性只有一个旋钮：ammo ——"这只虫子一共能用几次"（-1 = 无限）。
-- **弹药按虫算**，不跟队友共享：同一件武器，你的 5 发不会被队友用掉。
-- 弹药见底时只剩普通炮弹——它无限、够用，但伤不到远处的人。
-- （曾经还有 cooldown 字段与"冷却回合"显示，后来判定成冗余机制删掉了：
--   两套稀有性同时存在，玩家与 AI 都得先搞清"到底哪个在卡我"）
--
-- kind 决定走哪条飞行逻辑：
--   ballistic 标准弹道   grenade 引信 + 弹跳   hitscan 直线命中（霰弹 / 机枪）
--   laser     只烧地形   track 追踪敌人       multi 落点分裂
--   utility   传送（无伤害）

local Physics = require("physics")

local Weapons = {}

-- 普通炮弹排第一：它是"打光了也有得打"的兜底，也是默认选择
Weapons.INFINITE = -1

Weapons.LIST = {
  { id = "shell", name = { zh = "普通炮弹", en = "SHELL" }, short = { zh = "普通", en = "SHELL" },
    kind = "ballistic", damage = 8, radius = 3, wind = 1.0,
    ammo = Weapons.INFINITE },
  { id = "bazooka", name = { zh = "火箭筒", en = "BAZOOKA" }, short = { zh = "火箭", en = "BAZOOKA" },
    kind = "ballistic", damage = 50, radius = 5, wind = 1.0, ammo = 5 },
  { id = "grenade", name = { zh = "手雷", en = "GRENADE" }, short = { zh = "手雷", en = "GRENADE" },
    kind = "grenade", damage = 45, radius = 5, wind = 0.6, fuse = 3.0, ammo = 4 },
  -- hitscan 的伤害只算**直击**：枪打的是直线，想伤人就得瞄准人。
  -- dig 是打在墙上会挖掉多大的洞（霰弹挖一点、机枪不挖），别和 radius 混起来——
  -- radius 是"擦到身边的溅射半径"，直击以外只按它给半步伤害
  { id = "shotgun", name = { zh = "霰弹枪", en = "SHOTGUN" }, short = { zh = "霰弹", en = "SHOTGUN" },
    kind = "hitscan", damage = 25, radius = 3, wind = 0,
    shots = 2, range = 100, dig = 1, spread = 3, ammo = 3 },
  { id = "mg", name = { zh = "机关枪", en = "MACHINE GUN" }, short = { zh = "机枪", en = "MG" },
    kind = "hitscan", damage = 8, radius = 1, wind = 0,
    shots = 6, range = 140, dig = 0, spread = 5, push = 2.5, ammo = 3 },
  { id = "barrel", name = { zh = "燃油桶", en = "FUEL BARREL" }, short = { zh = "燃油", en = "BARREL" },
    kind = "ballistic", damage = 30, radius = 3, wind = 0.3, burn = 3.0, ammo = 2 },
  -- 激光：一条**会飞的光束**。不受重力、速度很高，沿途烧穿地形、伤到碰到的人，
  -- 一路飞到地图边界才停（镜头跟着它，整条路径都看得见）
  { id = "laser", name = { zh = "激光射线", en = "LASER" }, short = { zh = "激光", en = "LASER" },
    kind = "laser", damage = 12, radius = 1, wind = 0,
    speed = 900, width = 1, ammo = 2 },
  { id = "missile", name = { zh = "导弹", en = "MISSILE" }, short = { zh = "导弹", en = "MISSILE" },
    kind = "track", damage = 40, radius = 4, wind = 0, turn_rate = 60, ammo = 2 },
  { id = "cluster", name = { zh = "集束炸弹", en = "CLUSTER" }, short = { zh = "集束", en = "CLUSTER" },
    -- ai_mult 只用于 AI 的**评分**：它预演的是母弹落点，看不到 5 枚子弹药，
    -- 不放大就会被 AI 当成"15 伤害的弱弹"。物理本身没被改动
    kind = "multi", damage = 15, radius = 3, wind = 1.2, splits = 5,
    ai_mult = 3, ammo = 2 },
  { id = "super", name = { zh = "超级弹药", en = "SUPER" }, short = { zh = "超级", en = "SUPER" },
    kind = "ballistic", damage = 90, radius = 9, wind = 0.4, ammo = 1 },
  { id = "teleport", name = { zh = "传送", en = "TELEPORT" }, short = { zh = "传送", en = "TELEPORT" },
    kind = "utility", damage = 0, radius = 0, ammo = 2 },
}

function Weapons.by_id(id)
  for _, w in ipairs(Weapons.LIST) do
    if w.id == id then return w end
  end
  return nil
end

-- 一只虫子的初始弹药：从武器表抄一份。按虫各记各的，不共享
function Weapons.start_ammo()
  local ammo = {}
  for _, w in ipairs(Weapons.LIST) do ammo[w.id] = w.ammo or 1 end
  return ammo
end

-- 还有得打吗？无限（-1）永远算有
function Weapons.has_ammo(worm, weapon)
  if not worm or not worm.ammo then return true end
  local n = worm.ammo[weapon.id]
  if n == nil then return false end
  return n < 0 or n > 0
end

-- 发射：算出枪口的初速与位置，交给 main 每帧推进。
-- 所有弹种共用这一个入口，区别只在表里的 kind 与系数。
function Weapons.fire(w, shooter)
  local vx, vy = Physics.velocity(shooter.angle, shooter.power, shooter.facing)
  local p = Physics.new_projectile(shooter.x + shooter.facing * 3, shooter.y - 6, vx, vy, {
    wind = w.wind or 0,
    fuse = w.fuse,
    bounce_ground = (w.kind == "grenade"),
    no_gravity = (w.kind == "track"),
  })
  p.weapon = w
  p.shooter = shooter
  return p
end

-- 集束：在落点把母弹拆成 count 枚子弹药，朝上半圈散开。
-- 子弹药共用母弹的伤害与半径，但**不带 splits 字段** —— 否则每枚落点又分裂一次，
-- 指数增长，一炮就把地图清空
function Weapons.split(spec, x, y, count)
  local sub = {
    id = spec.id, name = spec.name, kind = "ballistic",
    damage = spec.damage, radius = spec.radius, wind = spec.wind,
  }
  local out = {}
  for i = 1, count do
    local ang = math.rad(phos.sys.random(25, 155))
    local spd = phos.sys.random(6, 11)
    -- 左右交替给初速，免得五枚都往同一边飞
    local side = (i % 2 == 0) and 1 or -1
    local q = Physics.new_projectile(x, y - 2,
                                     math.cos(ang) * spd * side,
                                     -math.sin(ang) * spd,
                                     { wind = spec.wind or 0, fuse = 2.0 })
    q.weapon = sub
    out[#out + 1] = q
  end
  return out
end

-- 追踪弹的转向：朝最近敌人慢慢掰，转弯速率有限，所以可以被甩掉
function Weapons.steer(p, target, dt)
  local turn = math.rad(p.weapon.turn_rate or 60) * dt
  local cur = math.atan(p.vy, p.vx)
  local want = math.atan(target.y - p.y, target.x - p.x)
  local diff = (want - cur + math.pi) % (2 * math.pi) - math.pi
  if diff > turn then diff = turn elseif diff < -turn then diff = -turn end
  local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
  local a = cur + diff
  p.vx, p.vy = speed * math.cos(a), speed * math.sin(a)
end

return Weapons

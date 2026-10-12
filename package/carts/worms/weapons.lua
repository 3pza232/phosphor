-- weapons.lua —— 武器表 + 通用发射器
--
-- 武器是**数据**：改数值不必碰逻辑。改之前先看这份模型（三条）：
--
--   1. 每只虫的"总输出预算"大致相等（约 200 点期望伤害）：`ammo × 单发期望 ≈ 200`。
--      所以单发越强，ammo 越少 —— 不存在"又强又管够"的武器
--   2. 单发期望按**真实命中率**折算，不按全中算：散射弹通常只中两三枚、
--      集束弹只在敌人扎堆时才值钱。AI 用同一把尺子估（见 ai.lua 的 score_of）
--   3. 普通炮弹**不参与**这份预算：它是兜底，无限但单发很弱。
--      它的职责是"打光了也有得打"，不是"和主力弹抢回合"
--
-- 稀有性只有一个旋钮：ammo ——"这只虫子一共能用几次"（-1 = 无限）。
-- **弹药按虫算**，不跟队友共享：同一件武器，你的 5 发不会被队友用掉。
-- 空投补给一箱给几发，由 supply 给（默认 1；霰弹/机枪这类弱弹给 2）。
--
-- kind 决定走哪条飞行逻辑（**实弹怎么飞**）：
--   ballistic 标准弹道        grenade 引信 + 弹跳      spread 多枚炮弹散射
--   laser     会飞的光束      track 追踪敌人          multi 落点分裂
--   utility   传送（无伤害）
--
-- 另外三个字段是给 **AI** 看的（见 ai.lua：它按这三件事装配，不看 id）：
--   plan   怎么瞄：arc 抛物线角度×力度 / ray 直线只挑角度
--   effect 命中后世界怎么变：blast 爆炸 / dig 只挖地形（不伤人）/ heal 回血 /
--          mound 长地形并埋人 / strike 唤来天上那束光柱 / beam 烧穿射线
--   ai     电脑用不用：throw 参战 / self 只对自己用（传送）/ false 明确不用
-- 加一件新武器**不必动 AI**：这三项能从现有取值里组合出来就行；只有当它带来全新的
-- 瞄准维度或全新的世界变化时，才去 ai.lua 的 PLANS / EFFECTS 里加一个函数

local Physics = require("physics")

local Weapons = {}

-- 侧栏武器格只有 9 列宽（一格 = 图标 + 短名 + 余弹），所以 en 的 short 一律压到
-- 6 列以内：中文短名是 2 字（4 列）天然够用，英文照抄全名就会把余弹挤出格子
--
-- 普通炮弹排第一：它是"打光了也有得打"的兜底，也是默认选择
Weapons.INFINITE = -1

Weapons.LIST = {
  { id = "shell", name = { zh = "普通炮弹", en = "SHELL" }, short = { zh = "普通", en = "SHELL" },
    kind = "ballistic", plan = "arc", effect = "blast", ai = "throw",
    damage = 10, radius = 3, wind = 1.0,
    ammo = Weapons.INFINITE },
  { id = "bazooka", name = { zh = "火箭筒", en = "BAZOOKA" }, short = { zh = "火箭", en = "ROCKET" },
    kind = "ballistic", plan = "arc", effect = "blast", ai = "throw",
    damage = 50, radius = 5, wind = 1.0, ammo = 4 },
  { id = "grenade", name = { zh = "手雷", en = "GRENADE" }, short = { zh = "手雷", en = "NADE" },
    kind = "grenade", plan = "arc", effect = "blast", ai = "throw",
    damage = 45, radius = 5, wind = 0.6, fuse = 3.0, ammo = 4 },
  -- 散射系：**多枚普通炮弹**按总散射角打出去（有抛物线、受风，不是瞬时射线）。
  -- 平衡点就在命中率上：全中很值钱，散开后通常只中两三枚，所以单发期望只能按
  -- "两三枚"折算（ai_mult 就是给 AI 用的这个折扣）
  -- 霰弹：5 枚 11 伤、10° 总散射 —— 敢靠近才有全中
  { id = "shotgun", name = { zh = "霰弹枪", en = "SHOTGUN" }, short = { zh = "霰弹", en = "SHOT" },
    kind = "spread", plan = "arc", effect = "blast", ai = "throw",
    shells = 5, spread = 10, damage = 11, radius = 3, wind = 1.0,
    ammo = 3, ai_mult = 3, supply = 2 },
  -- 机枪：同一套散射角度，但**连发**——burst 是每发之间的间隔（秒）。
  -- 8 枚小威力炮弹挤在 8° 内，边打边推进，压制与推人用
  { id = "mg", name = { zh = "机关枪", en = "MACHINE GUN" }, short = { zh = "机枪", en = "MG" },
    kind = "spread", plan = "arc", effect = "blast", ai = "throw",
    shells = 8, spread = 8, burst = 0.1, damage = 8, radius = 1, wind = 1.0,
    ammo = 3, ai_mult = 3, supply = 2 },
  -- 治疗弹：打中**自己队**的单位回血（敌人治敌人、队友治队友），打在对面身上什么也不发生。
  -- 不带伤害、不挖地形——它是"道具"，不是武器。回 60 是照默认 100 血给的：
  -- 一发能顶住一轮集火，但救不回已被打残两次的人
  { id = "heal", name = { zh = "治疗弹", en = "MEDIC SHELL" }, short = { zh = "治疗", en = "MEDIC" },
    kind = "ballistic", plan = "arc", effect = "heal", ai = "throw",
    heal = 60, damage = 0, radius = 4, wind = 1.0, ammo = 3 },
  -- 地形弹：不伤人不挖地，落点**长出一块圆形地形**（半径 10 子格 ≈ 5 个字符格高）。
  -- 用法是造掩体、垫高脚、或者干脆把对面的直线通路堵死
  { id = "terrain", name = { zh = "地形弹", en = "TERRAIN SHELL" },
    short = { zh = "地形", en = "MOUND" },
    kind = "ballistic", plan = "arc", effect = "mound", ai = "throw",
    raise = 10, damage = 0, radius = 0, wind = 1.0, ammo = 2 },
  -- 地消弹：**只挖地形、不伤人**（effect=dig：无伤害、无冲量）。破坏半径与超级弹相当，
  -- 用来清出通路、拆掩体，或在被地形埋住时把自己挖出来。掏空敌人脚下的土让它塌落 / 落水，
  -- 那是地形与重力造成的后果，不是这一弹的"伤害"——所以它连 0 伤害的爆炸冲量都不带
  { id = "digger", name = { zh = "地消弹", en = "DIRT BOMB" }, short = { zh = "地消", en = "DIRT" },
    kind = "ballistic", plan = "arc", effect = "dig", ai = "throw",
    damage = 0, radius = 9, wind = 0.4, ammo = 2 },
  -- 天基炮：落点先标记 2 秒，再从天而降一束粗光柱持续 3 秒，每 0.5 秒结算一次伤害。
  -- 它打的是**位置**而不是人——逼对面离开掩体、或者断掉一条必经之路
  { id = "orbital", name = { zh = "天基炮", en = "ORBITAL" }, short = { zh = "天基", en = "ORBIT" },
    kind = "ballistic", plan = "arc", effect = "strike", ai = "throw",
    wind = 1.0, damage = 0, radius = 0, ammo = 2,
    -- 下落分两档（子格/秒）：穿空气快（"从天而降"看得见），**碰到土就急剧减速** ——
    -- 不减速的话它会在光柱持续时间里一路钻穿整张地图。宽度是画与挖共用的那一对列边界
    orbital = { delay = 2.0, life = 3.0, tick = 0.5, damage = 18, width = 6,
                descend = 90, descend_dig = 4 } },
  { id = "barrel", name = { zh = "燃油桶", en = "FUEL BARREL" }, short = { zh = "燃油", en = "BARREL" },
    kind = "ballistic", plan = "arc", effect = "blast", ai = "throw",
    damage = 35, radius = 3, wind = 0.3, burn = 3.0, ammo = 2 },
  -- 激光：一条**会飞的光束**。不受重力、速度很高，沿途烧穿地形、伤到碰到的人，
  -- 一路飞到地图边界才停（镜头跟着它，整条路径都看得见）
  { id = "laser", name = { zh = "激光射线", en = "LASER" }, short = { zh = "激光", en = "LASER" },
    kind = "laser", plan = "ray", effect = "beam", ai = "throw",
    damage = 22, radius = 1, wind = 0,
    speed = 900, width = 1, ammo = 5 },
  { id = "missile", name = { zh = "导弹", en = "MISSILE" }, short = { zh = "导弹", en = "HOMING" },
    -- 追踪弹暂不给 AI：它的飞行要靠"边飞边转向"，这套预演（打一发看落点）算不出真实弹道，
    -- 硬塞进来只会算出假成绩。想让它参战，就得在 ai.lua 的 PLANS 里加一个"会跟的预演"
    kind = "track", ai = false, damage = 45, radius = 4, wind = 0, turn_rate = 60, ammo = 2 },
  { id = "cluster", name = { zh = "集束炸弹", en = "CLUSTER" }, short = { zh = "集束", en = "BOMBS" },
    -- ai_mult 只用于 AI 的**评分**：它预演的是母弹落点，看不到 5 枚子弹药，
    -- 不放大就会被 AI 当成"15 伤害的弱弹"。它与物理无关（伤害就是表里的 damage）
    kind = "multi", plan = "arc", effect = "blast", ai = "throw",
    damage = 18, radius = 3, wind = 1.2, splits = 5,
    ai_mult = 3, ammo = 2 },
  { id = "super", name = { zh = "超级弹药", en = "SUPER" }, short = { zh = "超级", en = "SUPER" },
    kind = "ballistic", plan = "arc", effect = "blast", ai = "throw",
    damage = 100, radius = 9, wind = 0.4, ammo = 1 },
  -- 传送只对**自己**用（换个位置），所以声明 self：它不进**攻击候选**（没有"往哪传更好"的评分）。
  -- 但被地形**埋住**时 main.lua 会显式拿它脱困 —— 能穿过地形换到别处，是"埋住还能跑"的手段
  { id = "teleport", name = { zh = "传送", en = "TELEPORT" }, short = { zh = "传送", en = "WARP" },
    kind = "utility", ai = "self", damage = 0, radius = 0, ammo = 2 },
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
  local mx, my = Physics.muzzle_of(shooter)
  local p = Physics.new_projectile(mx, my, vx, vy, {
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

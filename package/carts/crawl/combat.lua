-- combat.lua —— 战斗公式（DESIGN §5.3）与升级表。
--
-- 命中/伤害/暴击**双方共用一套**，取整全部显式，保证同种子逐位一致。
-- 这里不读键盘、不绘制、不发声音，也不直接改玩家对象——升级只算出"该改哪些值"，
-- 由 world 落账。

local Combat = {}

Combat.HIT_BASE, Combat.HIT_SLOPE, Combat.HIT_MIN, Combat.HIT_MAX = 0.55, 0.04, 0.15, 0.95
Combat.CRIT = 0.08

-- 有效属性：基础 + 装备加成。攻击方没有 weapon 字段时为 0（怪物走这条）。
function Combat.eff_atk(e)
  return (e.atk or 0) + ((e.weapon and e.weapon.bonus) or 0)
end

function Combat.eff_def(e)
  return (e.def or 0) + ((e.armor and e.armor.bonus) or 0)
end

function Combat.hit_chance(A, D)
  local c = Combat.HIT_BASE + Combat.HIT_SLOPE * (A - D)
  if c < Combat.HIT_MIN then c = Combat.HIT_MIN end
  if c > Combat.HIT_MAX then c = Combat.HIT_MAX end
  return c
end

-- 掷一次攻击：返回 (命中?, 伤害, 是否暴击)。
-- 暴击在**减防之前**乘 2，所以高防也躲不过暴击的穿透（§5.3）。
function Combat.roll(A, D, rng)
  if rng.float() >= Combat.hit_chance(A, D) then
    return false, 0, false
  end
  local base = rng.int(math.ceil(A * 0.75), math.max(math.ceil(A * 0.75), A))
  local crit = rng.float() < Combat.CRIT
  local dmg = crit and base * 2 or base
  return true, math.max(1, dmg - D), crit
end

-- 累计 XP 阈值（§5.2 表）。12 级起每级 +220，封顶 15。
Combat.LEVEL_XP = { 0, 16, 42, 82, 140, 215, 310, 425, 560, 720, 900 }
Combat.MAX_LEVEL = 15

function Combat.xp_for(level)
  if level <= 11 then return Combat.LEVEL_XP[level] or 900 end
  return 900 + (level - 11) * 220
end

-- 每升一级的奖励（§5.2）：max_hp +6、atk +2、def +1、回复 8 HP。
-- 只返回"本次涨了哪些、涨了几级"，由 world 应用到玩家并写日志——公式与状态解耦。
function Combat.gain_levels(player)
  local gained = 0
  while player.level < Combat.MAX_LEVEL and player.xp >= Combat.xp_for(player.level + 1) do
    player.level = player.level + 1
    player.max_hp = player.max_hp + 6
    player.atk = player.atk + 2
    player.def = player.def + 1
    player.hp = math.min(player.max_hp, player.hp + 8)
    gained = gained + 1
  end
  return gained
end

-- 击杀奖励的经验与金币（§5.3）。金币由 world 落成地面金币堆。
function Combat.kill_reward(victim, rng, drop_mult)
  local xp = victim.xp or 0
  local gold = rng.int(victim.gold_min or 0, math.max(victim.gold_min or 0, victim.gold_max or 0))
  gold = math.floor(gold * (drop_mult or 1) + 0.5)
  return xp, gold
end

return Combat

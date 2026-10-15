-- monsters.lua —— 敌人图鉴（数据驱动，DESIGN §6）与实例构造。
--
-- 这里只有**数据与工厂**，不含任何决策：行为在 ai.lua，结算在 world/combat。
-- 数值集中在这一张表，调平衡只动这里。颜色写的是**色板槽位名**（gray/blue/…），
-- 由绘制层查 phos.color 得到真实色值——换主题即换配色。

local Monsters = {}

-- 字段说明：
--   dmin/dmax  出现深度区间；weight 类型池权重（§6）
--   flags: erratic 乱走 / phase 穿墙 / split 死亡分裂 / ranged 远射距离 /
--          flee_at 血量分数低于它则逃 / drain 命中玩家额外吸油 / boss 守望者
Monsters.LIST = {
  { id = "rat",      name = { zh = "巨鼠",   en = "GIANT RAT" },
    glyph = "r", color = "gray",    hp = 6,  atk = 3,  def = 0, xp = 4,   gold_min = 1,  gold_max = 3,   speed = 100, dmin = 1, dmax = 3,  weight = 10 },
  { id = "bat",      name = { zh = "洞穴蝠", en = "CAVE BAT" },
    glyph = "b", color = "blue",    hp = 5,  atk = 4,  def = 1, xp = 6,   gold_min = 0,  gold_max = 2,   speed = 150, dmin = 2, dmax = 5,  weight = 9,  erratic = true },
  { id = "goblin",   name = { zh = "哥布林", en = "GOBLIN" },
    glyph = "g", color = "green",   hp = 11, atk = 5,  def = 1, xp = 9,   gold_min = 3,  gold_max = 8,   speed = 100, dmin = 2, dmax = 6,  weight = 9,  flee_at = 0.25 },
  { id = "skeleton", name = { zh = "骷髅",   en = "SKELETON" },
    glyph = "s", color = "white",   hp = 15, atk = 6,  def = 3, xp = 13,  gold_min = 2,  gold_max = 6,   speed = 100, dmin = 3, dmax = 7,  weight = 8 },
  { id = "orc",      name = { zh = "兽人",   en = "ORC" },
    glyph = "o", color = "orange",  hp = 22, atk = 8,  def = 3, xp = 18,  gold_min = 6,  gold_max = 14,  speed = 100, dmin = 4, dmax = 8,  weight = 7 },
  { id = "wraith",   name = { zh = "怨灵",   en = "WRAITH" },
    glyph = "w", color = "purple",  hp = 13, atk = 9,  def = 2, xp = 22,  gold_min = 5,  gold_max = 10,  speed = 70,  dmin = 5, dmax = 9,  weight = 5,  phase = true, drain = 5 },
  { id = "slime",    name = { zh = "软泥",   en = "SLIME" },
    glyph = "m", color = "magenta", hp = 18, atk = 5,  def = 5, xp = 16,  gold_min = 3,  gold_max = 9,   speed = 60,  dmin = 3, dmax = 8,  weight = 6,  split = true },
  { id = "cultist",  name = { zh = "邪教徒", en = "CULTIST" },
    glyph = "C", color = "red",     hp = 16, atk = 7,  def = 2, xp = 24,  gold_min = 8,  gold_max = 16,  speed = 90,  dmin = 5, dmax = 9,  weight = 5,  ranged = 5 },
  { id = "golem",    name = { zh = "石魔像", en = "GOLEM" },
    glyph = "G", color = "gray",    hp = 42, atk = 12, def = 8, xp = 48,  gold_min = 15, gold_max = 30,  speed = 55,  dmin = 7, dmax = 10, weight = 3 },
  { id = "warden",   name = { zh = "守望者", en = "WARDEN" },
    glyph = "W", color = "yellow",  hp = 95, atk = 14, def = 6, xp = 220, gold_min = 80, gold_max = 120, speed = 110, dmin = 10, dmax = 10, weight = 0, boss = true, summon = true, enrage = true },
}

local by_id = {}
for _, s in ipairs(Monsters.LIST) do by_id[s.id] = s end
function Monsters.spec(id) return by_id[id] end

-- 深度池：只含"出现区间覆盖 depth"且非 Boss 的类型
function Monsters.pool(depth)
  local out = {}
  for _, s in ipairs(Monsters.LIST) do
    if not s.boss and s.dmin <= depth and depth <= s.dmax then out[#out + 1] = s end
  end
  return out
end

-- 从深度池按权重挑一类；池空时退回最浅的 rat，保证永远有得挑
function Monsters.pick(depth, rng)
  local pool = Monsters.pool(depth)
  if #pool == 0 then return by_id.rat end
  local items = {}
  for _, s in ipairs(pool) do items[#items + 1] = { w = s.weight, spec = s } end
  local chosen = rng.weighted(items)
  return chosen and chosen.spec or pool[1]
end

-- 构造实例。hp_mult 是可调难度旋钮（DESIGN §20），默认 1。
function Monsters.make(spec, x, y, hp_mult)
  local hp = math.max(1, math.floor(spec.hp * (hp_mult or 1) + 0.5))
  return {
    id = spec.id, spec = spec, name = spec.name,
    glyph = spec.glyph, color = spec.color,
    x = x, y = y, hp = hp, max_hp = hp,
    atk = spec.atk, def = spec.def, speed = spec.speed,
    xp = spec.xp, gold_min = spec.gold_min, gold_max = spec.gold_max,
    energy = 0, awake = false, lost = 0, known_x = nil, known_y = nil,
    erratic = spec.erratic, phase = spec.phase, split = spec.split,
    ranged = spec.ranged, flee_at = spec.flee_at, drain = spec.drain,
    boss = spec.boss, summon = spec.summon, enrage = spec.enrage,
  }
end

-- 小软泥：分裂产物（父体上限的一半、ATK−1、XP/金币减半，且不再分裂，§6）
function Monsters.make_slimelet(x, y)
  local base = by_id.slime
  local m = Monsters.make(base, x, y)
  m.id, m.is_slimelet = "slime", true
  m.max_hp = math.max(1, math.floor(base.hp / 2))
  m.hp = m.max_hp
  m.atk = base.atk - 1
  m.xp = math.floor(base.xp / 2)
  m.gold_min = math.floor(base.gold_min / 2)
  m.gold_max = math.max(m.gold_min, math.floor(base.gold_max / 2))
  m.split = false
  return m
end

return Monsters

-- items.lua —— 物品 / 装备 / 胜负道具（数据驱动，DESIGN §9）与掉落权重。
--
-- 只有数据与挑选辅助：效果结算、拾取、换装都在 world.lua。这样"加一件物品"
-- 与"改它的效果"是两件事，互不牵动。颜色同样写色板槽位名。

local Items = {}

-- 消耗品（进背包，最多 8 格）。kind 决定 world 里怎么结算效果。
-- desc 是给背包信息窗看的**效果说明**（双语）：为什么写在这里而不是 world.lua——
-- 说明是"物品的属性"，跟着物品走；数值需与 world:use_item 的结算保持一致。
Items.CONSUMABLES = {
  { id = "oil",    name = { zh = "灯油瓶",   en = "OIL FLASK" },  glyph = "!", color = "yellow", kind = "oil",
    desc = { zh = "倒空油瓶，灯油 +50（上限 100）。", en = "Refill the lantern (+50 fuel)." } },
  { id = "potion", name = { zh = "治疗药水", en = "POTION" },     glyph = "!", color = "red",    kind = "potion",
    desc = { zh = "恢复 15 点生命。", en = "Restore 15 HP." } },
  { id = "ration", name = { zh = "干粮",     en = "RATIONS" },    glyph = "%", color = "orange", kind = "ration",
    desc = { zh = "恢复 6 点生命与 15 灯油。", en = "Restore 6 HP. +15 fuel." } },
  { id = "blink",  name = { zh = "闪现卷轴", en = "BLINK" },      glyph = "?", color = "cyan",   kind = "blink",
    desc = { zh = "随机传送到本层他处（不落到怪物身上）。", en = "Blink to a random empty tile." } },
  { id = "shock",  name = { zh = "冲击卷轴", en = "SHOCKWAVE" },  glyph = "?", color = "orange", kind = "shock",
    desc = { zh = "对视野内所有怪物造成 10 点伤害。", en = "Hit every visible foe for 10." } },
  { id = "map",    name = { zh = "探图卷轴", en = "MAPPING" },    glyph = "?", color = "white",  kind = "map",
    desc = { zh = "揭示本层全部地图。", en = "Reveal the floor map." } },
  { id = "flame",  name = { zh = "烈焰卷轴", en = "FLAME" },      glyph = "?", color = "red",    kind = "flame",
    desc = { zh = "对最近的可见怪物造成 18 点伤害。", en = "Burn the nearest foe for 18." } },
}

-- 消耗品相对权重（§9.3）
Items.WEIGHTS = { oil = 30, potion = 30, ration = 15, blink = 8, shock = 8, map = 5, flame = 4 }

-- 装备（不留背包，拾取即按加成比较后自动换装，§9.2）。bonus 越大越强。
-- desc 供信息窗展示"用途"；加成与适用深度由 bonus / depth 字段派生，不重复写进文案。
Items.EQUIPMENT = {
  { id = "dagger",     kind = "weapon", name = { zh = "匕首",   en = "DAGGER" },     glyph = "/", color = "white", bonus = 2,  depth = 1,
    desc = { zh = "轻便短刃，前期自保的起步武器。", en = "A light blade for defence." } },
  { id = "shortsword", kind = "weapon", name = { zh = "短剑",   en = "SHORTSWORD" }, glyph = "/", color = "white", bonus = 4,  depth = 3,
    desc = { zh = "均衡的进阶武器。", en = "A balanced blade." } },
  { id = "warhammer",  kind = "weapon", name = { zh = "战锤",   en = "WARHAMMER" },  glyph = "/", color = "white", bonus = 7,  depth = 5,
    desc = { zh = "沉重而凶猛的破甲利器。", en = "A heavy, brutal crusher." } },
  { id = "runeblade",  kind = "weapon", name = { zh = "符文剑", en = "RUNE BLADE" }, glyph = "/", color = "white", bonus = 10, depth = 8,
    desc = { zh = "刻满符文的顶级利刃。", en = "A top-tier blade carved with runes." } },
  { id = "leather",    kind = "armor",  name = { zh = "皮甲",   en = "LEATHER" },    glyph = "[", color = "gray",  bonus = 1,  depth = 1,
    desc = { zh = "轻软的基础护甲。", en = "Light, basic protection." } },
  { id = "chain",      kind = "armor",  name = { zh = "锁甲",   en = "CHAINMAIL" },  glyph = "[", color = "gray",  bonus = 3,  depth = 3,
    desc = { zh = "环环相扣的金属护甲。", en = "Interlocked metal rings." } },
  { id = "plate",      kind = "armor",  name = { zh = "板甲",   en = "PLATE" },      glyph = "[", color = "gray",  bonus = 5,  depth = 6,
    desc = { zh = "厚重的全身板甲。", en = "Heavy full-body plate." } },
  { id = "aegis",      kind = "armor",  name = { zh = "神盾",   en = "AEGIS" },      glyph = "[", color = "gray",  bonus = 8,  depth = 8,
    desc = { zh = "传说中的顶级护甲。", en = "Legendary top-tier protection." } },
}

-- 胜负道具：拾取即通关（§9.4）。闪烁由绘制层按 turn 做，不在这里。
Items.HEART = { id = "heart", name = { zh = "磷之心", en = "PHOSPHOR HEART" }, glyph = "*", color = "yellow",
  desc = { zh = "地牢深处的胜负之物，拾取即通关。", en = "The prize of the dungeon; taking it wins the run." } }

local by_id = {}
for _, s in ipairs(Items.CONSUMABLES) do by_id[s.id] = s end
for _, s in ipairs(Items.EQUIPMENT) do by_id[s.id] = s end
by_id.heart = Items.HEART
function Items.spec(id) return by_id[id] end

-- 按权重挑一件消耗品
function Items.pick_consumable(rng)
  local items = {}
  for _, s in ipairs(Items.CONSUMABLES) do
    items[#items + 1] = { w = Items.WEIGHTS[s.id] or 1, spec = s }
  end
  local chosen = rng.weighted(items)
  return chosen and chosen.spec or Items.CONSUMABLES[1]
end

-- 解锁深度 ≤ depth 的装备池（Boss 掉落取"最高档"用它过滤）
function Items.pool(depth)
  local out = {}
  for _, s in ipairs(Items.EQUIPMENT) do
    if s.depth <= depth then out[#out + 1] = s end
  end
  return out
end

function Items.pick_equipment(depth, rng)
  local pool = Items.pool(depth)
  if #pool == 0 then return nil end
  return pool[rng.int(1, #pool)]
end

-- Boss 必掉：最高档装备（runeblade / aegis / plate）里随机一件
function Items.top_tier(rng)
  local pool = {}
  for _, s in ipairs(Items.EQUIPMENT) do
    if s.id == "runeblade" or s.id == "aegis" or s.id == "plate" then pool[#pool + 1] = s end
  end
  return pool[rng.int(1, #pool)]
end

return Items

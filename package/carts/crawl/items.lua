-- items.lua —— 物品 / 装备 / 胜负道具（数据驱动，DESIGN §9）与掉落权重。
--
-- 只有数据与挑选辅助：效果结算、拾取、换装都在 world.lua。这样"加一件物品"
-- 与"改它的效果"是两件事，互不牵动。颜色同样写色板槽位名。

local Items = {}

-- 消耗品（进背包，最多 8 格）。kind 决定 world 里怎么结算效果。
Items.CONSUMABLES = {
  { id = "oil",    name = { zh = "灯油瓶",   en = "OIL FLASK" },  glyph = "!", color = "yellow", kind = "oil" },
  { id = "potion", name = { zh = "治疗药水", en = "POTION" },     glyph = "!", color = "red",    kind = "potion" },
  { id = "ration", name = { zh = "干粮",     en = "RATIONS" },    glyph = "%", color = "orange", kind = "ration" },
  { id = "blink",  name = { zh = "闪现卷轴", en = "BLINK" },      glyph = "?", color = "cyan",   kind = "blink" },
  { id = "shock",  name = { zh = "冲击卷轴", en = "SHOCKWAVE" },  glyph = "?", color = "orange", kind = "shock" },
  { id = "map",    name = { zh = "探图卷轴", en = "MAPPING" },    glyph = "?", color = "white",  kind = "map" },
  { id = "flame",  name = { zh = "烈焰卷轴", en = "FLAME" },      glyph = "?", color = "red",    kind = "flame" },
}

-- 消耗品相对权重（§9.3）
Items.WEIGHTS = { oil = 30, potion = 30, ration = 15, blink = 8, shock = 8, map = 5, flame = 4 }

-- 装备（不留背包，拾取即按加成比较后自动换装，§9.2）。bonus 越大越强。
Items.EQUIPMENT = {
  { id = "dagger",     kind = "weapon", name = { zh = "匕首",   en = "DAGGER" },     glyph = "/", color = "white", bonus = 2,  depth = 1 },
  { id = "shortsword", kind = "weapon", name = { zh = "短剑",   en = "SHORTSWORD" }, glyph = "/", color = "white", bonus = 4,  depth = 3 },
  { id = "warhammer",  kind = "weapon", name = { zh = "战锤",   en = "WARHAMMER" },  glyph = "/", color = "white", bonus = 7,  depth = 5 },
  { id = "runeblade",  kind = "weapon", name = { zh = "符文剑", en = "RUNE BLADE" }, glyph = "/", color = "white", bonus = 10, depth = 8 },
  { id = "leather",    kind = "armor",  name = { zh = "皮甲",   en = "LEATHER" },    glyph = "[", color = "gray",  bonus = 1,  depth = 1 },
  { id = "chain",      kind = "armor",  name = { zh = "锁甲",   en = "CHAINMAIL" },  glyph = "[", color = "gray",  bonus = 3,  depth = 3 },
  { id = "plate",      kind = "armor",  name = { zh = "板甲",   en = "PLATE" },      glyph = "[", color = "gray",  bonus = 5,  depth = 6 },
  { id = "aegis",      kind = "armor",  name = { zh = "神盾",   en = "AEGIS" },      glyph = "[", color = "gray",  bonus = 8,  depth = 8 },
}

-- 胜负道具：拾取即通关（§9.4）。闪烁由绘制层按 turn 做，不在这里。
Items.HEART = { id = "heart", name = { zh = "磷之心", en = "PHOSPHOR HEART" }, glyph = "*", color = "yellow" }

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

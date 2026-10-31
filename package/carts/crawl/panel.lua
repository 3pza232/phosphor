-- panel.lua —— 右侧栏（DESIGN §12.2）。
--
-- 只读状态：HP / 灯油条 + 光照 / 攻防 / 等级与经验 / 金币 / 装备 / 深度与最高纪录 /
-- 背包 8 格 / 底部键位。声明式组件：对齐/裁剪/宽度由引擎负责。
local Panel = {}

local Text = {
  zh = { hp = "生命", fuel = "灯油", light = "光照", atk = "攻击", def = "防御",
         lv = "等级", gold = "金币", weapon = "武器", armor = "护甲",
         depth = "深度", best = "最高", pack = "背包", empty = "空",
         none_w = "空手", none_a = "布衣", keys = "键位", down = "下楼", take = "拾取",
         move = "方向键 移动/攻击", help = "帮助" },
  en = { hp = "HP", fuel = "FUEL", light = "LIGHT", atk = "ATK", def = "DEF",
         lv = "LEVEL", gold = "GOLD", weapon = "WEAPON", armor = "ARMOR",
         depth = "DEPTH", best = "BEST", pack = "PACK", empty = "-",
         none_w = "BARE", none_a = "CLOTH", keys = "KEYS", down = "DOWN", take = "TAKE",
         move = "ARROWS move/attack", help = "HELP" },
}
local SLOT_LETTER = { "a", "b", "c", "d", "e", "f", "g", "h" }
local function L() return phos.lang.dict(Text) end
local function KEY(name) return "[" .. phos.input.key_name(name) .. "]" end

function Panel.draw(world, cart)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local t = L()
  local p = world.p
  local hf = p.max_hp > 0 and p.hp / p.max_hp or 0
  local hp_fg = hf > 0.5 and "green" or (hf > 0.25 and "yellow" or "red")
  local ff = p.fuel / 100
  local fuel_fg
  if p.fuel == 0 then
    fuel_fg = ((world.turn % 20) < 10) and "red" or "dark_gray"
  else
    fuel_fg = ff > 0.5 and "cyan" or (ff > 0.2 and "yellow" or "red")
  end

  local atk = math.floor(world.p.atk + (p.weapon and p.weapon.bonus or 0))
  local def = math.floor(world.p.def + (p.armor and p.armor.bonus or 0))
  local wn = p.weapon and phos.lang.pick(p.weapon.name) or t.none_w
  local an = p.armor and phos.lang.pick(p.armor.name) or t.none_a

  local rows = {
    { kind = "text", text = cart.name or "CRAWL", accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = t.hp, value = tostring(p.hp) .. "/" .. tostring(p.max_hp), label_w = 6 },
    { kind = "bar", ratio = hf, fg = hp_fg },
    { kind = "stat", text = t.fuel, value = tostring(p.fuel), label_w = 6 },
    { kind = "bar", ratio = ff, fg = fuel_fg },
    { kind = "text", text = t.light .. " " .. tostring(world.radius or 0) },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = t.atk, value = tostring(atk), label_w = 6 },
    { kind = "stat", text = t.def, value = tostring(def), label_w = 6 },
    { kind = "stat", text = t.lv, value = tostring(p.level) .. "/15", label_w = 6 },
    { kind = "bar", ratio = world:xp_progress(), fg = "magenta" },
    { kind = "stat", text = t.gold, value = tostring(p.gold), label_w = 6, fg = "yellow" },
    { kind = "text", text = t.weapon .. " " .. wn, fg = p.weapon and "white" or "dark_gray" },
    { kind = "text", text = t.armor .. " " .. an, fg = p.armor and "white" or "dark_gray" },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = t.depth, value = tostring(world.depth) .. "/10", label_w = 6 },
    { kind = "stat", text = t.best, value = tostring(world.best_score), label_w = 6 },
    { kind = "text", text = t.pack, dim = true },
  }
  for i = 1, 8 do
    local spec = p.inv[i]
    if spec then
      rows[#rows + 1] = { kind = "text",
                          text = SLOT_LETTER[i] .. ") " .. spec.glyph .. " " .. phos.lang.pick(spec.name),
                          fg = spec.color or "white" }
    else
      rows[#rows + 1] = { kind = "text", text = SLOT_LETTER[i] .. ") " .. t.empty, dim = true }
    end
  end
  rows[#rows + 1] = { kind = "spacer", grow = 1 }
  rows[#rows + 1] = { kind = "text", text = t.move, dim = true }
  rows[#rows + 1] = { kind = "text", text = KEY("y") .. " " .. t.down, dim = true }
  rows[#rows + 1] = { kind = "text", text = KEY("a") .. " " .. t.take .. "  " .. KEY("x") .. " " .. t.pack,
                      dim = true }
  rows[#rows + 1] = { kind = "text", text = KEY("h") .. " " .. t.help, dim = true }

  phos.ui.render{
    screen = "panel",
    surface = "panel",
    input = false,
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 0,
    children = rows,
  }
end

return Panel

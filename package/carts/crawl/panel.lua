-- panel.lua —— 右侧栏（DESIGN §12.2）。
--
-- 只读状态：HP / 灯油条 + 光照半径 / 攻防 / 等级与经验 / 金币 / 装备 /
-- 深度与最高纪录 / 背包 8 格 / 底部键位。颜色一律取主题色板。
-- 坐标为**面板局部**；定宽文案一律过 phos.text.fit，绝不写死列号（汉字占 2 列）。

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
local function slot_color(C, name) return C[name] or C.white end

-- 一条实心条：n 格填色 + 其余暗格。颜色由调用方给（血条/油条各有分档）。
local function bar(P, C, x, y, w, frac, col)
  local n = math.floor(math.max(0, math.min(1, frac)) * w + 0.5)
  P.print(x, y, string.rep("=", n), col)
  P.print(x + n, y, string.rep("-", w - n), C.dark_gray)
end

-- 血条配色：高绿 / 中黄 / 低红。油条另有一套（高青 / 中黄 / 低红，归零闪烁）。
local function hp_color(C, frac)
  if frac > 0.5 then return C.green elseif frac > 0.25 then return C.yellow else return C.red end
end
local function fuel_color(C, frac, fuel, turn)
  if fuel == 0 then
    return ((turn % 20) < 10) and C.red or C.dark_gray
  end
  if frac > 0.5 then return C.cyan elseif frac > 0.2 then return C.yellow else return C.red end
end

function Panel.draw(world, cart)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end
  local t = L()
  local p = world.p
  local iw = pw - 2

  P.clear()
  P.print(1, 1, phos.text.fit(cart.name or "CRAWL", iw), C.yellow)
  P.print(1, 2, string.rep("-", iw), C.dark_gray)

  -- HP
  local hf = p.max_hp > 0 and p.hp / p.max_hp or 0
  P.print(1, 4, phos.text.pad(t.hp, iw - 4), C.gray)
  P.print(pw - 4, 4, phos.text.pad_left(tostring(p.hp), 3), C.white)
  bar(P, C, 1, 5, iw, hf, hp_color(C, hf))

  -- 灯油 + 光照半径
  local ff = p.fuel / 100
  P.print(1, 7, phos.text.pad(t.fuel, iw - 4), C.gray)
  P.print(pw - 4, 7, phos.text.pad_left(tostring(p.fuel), 3), C.white)
  bar(P, C, 1, 8, iw, ff, fuel_color(C, ff, p.fuel, world.turn))
  P.print(1, 9, phos.text.pad(t.light .. " " .. tostring(world.radius or 0), iw), C.white)

  -- 攻/防/等级
  P.print(1, 11, phos.text.pad(t.atk .. " " .. tostring(math.floor(world.p.atk + (p.weapon and p.weapon.bonus or 0))), iw // 2), C.white)
  P.print(1 + iw // 2, 11, phos.text.pad(t.def .. " " .. tostring(math.floor(world.p.def + (p.armor and p.armor.bonus or 0))), iw - iw // 2), C.white)
  P.print(1, 12, phos.text.pad(t.lv .. " " .. tostring(p.level) .. "/15", iw), C.white)
  bar(P, C, 1, 13, iw, world:xp_progress(), C.magenta)

  -- 金币
  P.print(1, 15, phos.text.pad(t.gold .. " " .. tostring(p.gold), iw), C.yellow)

  -- 装备（缺省"空手 / 布衣"）
  local wn = p.weapon and phos.lang.pick(p.weapon.name) or t.none_w
  local an = p.armor and phos.lang.pick(p.armor.name) or t.none_a
  P.print(1, 17, phos.text.fit(t.weapon .. " " .. wn, iw), p.weapon and C.white or C.dark_gray)
  P.print(1, 18, phos.text.fit(t.armor .. " " .. an, iw), p.armor and C.white or C.dark_gray)

  -- 深度 / 最高纪录
  P.print(1, 20, phos.text.pad(t.depth .. " " .. tostring(world.depth) .. "/10", iw), C.gray)
  P.print(1, 21, phos.text.fit(t.best .. " " .. tostring(world.best_score), iw), C.white)

  -- 背包（8 格）
  P.print(1, 23, t.pack, C.gray)
  for i = 1, 8 do
    local y = 23 + i
    local spec = p.inv[i]
    if spec then
      local line = SLOT_LETTER[i] .. ") " .. spec.glyph .. " " .. phos.lang.pick(spec.name)
      P.print(1, y, phos.text.fit(line, iw), slot_color(C, spec.color))
    else
      P.print(1, y, phos.text.fit(SLOT_LETTER[i] .. ") " .. t.empty, iw), C.dark_gray)
    end
  end

  -- 底部键位（详细键位都在这里；游戏区底部不再单独压一行。窄栏里每行最多两键，定宽一律过 fit）
  local kn = phos.input.key_name
  P.print(1, ph - 4, phos.text.fit(t.move, iw), C.dark_gray)
  P.print(1, ph - 3, phos.text.fit(string.format("[%s] %s", kn("y"), t.down), iw), C.dark_gray)
  P.print(1, ph - 2, phos.text.fit(string.format("[%s] %s  [%s] %s", kn("a"), t.take, kn("x"), t.pack), iw), C.dark_gray)
  P.print(1, ph - 1, phos.text.fit(string.format("[%s] %s", kn("h"), t.help), iw), C.dark_gray)
end

return Panel

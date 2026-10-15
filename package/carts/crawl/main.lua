-- main.lua —— 入口：装配模块、把输入翻成"意图"、把状态画出来（DESIGN §11/§16）。
--
-- 规则不在这一层：视角调度、战斗、AI 都在各自模块里。这里只做三件事——
--   * 输入 → world 的方法调用（一次按键 = 一个回合动作）
--   * 事件 → 音效（world 只返回事件表，不发声）
--   * 世界 / 顶栏 / 日志 / 侧栏 / 浮窗 / 结算屏的绘制编排
-- 颜色一律取主题色板；坐标以 phos.screen.playfield() 为准。

local World = require("world")
local Panel = require("panel")
local Hud = require("hud")
local Sfx = require("sfx")

-- 界面文案（中英两列，取值走 phos.lang；缺 en 回落中文）
local Text = {
  zh = {
    over = "你倒下了。", won = "你握住了磷之心，地牢在身后崩塌。",
    again = "按 %s 重开", score = "得分", depth = "深度", best = "最高纪录", turn = "回合",
    inv_title = "背包", inv_empty = "（空）", inv_hint = "↑↓ 选择   [%s] 使用   [%s] 关闭",
    help_title = "角色与帮助", hp = "生命", atk = "攻击", def = "防御", gold = "金币",
    fuel = "灯油", light = "光照", equip = "装备", seed = "种子", none_w = "空手", none_a = "布衣",
    keys_head = "操作", keys = {
      { "方向键", "移动 / 撞向怪物即攻击" },
      { "空格", "等待一回合" },
      { "%s", "拾取脚下物品" },
      { "%s", "背包" },
      { "%s", "下楼（站在 > 上）" },
      { "%s", "本帮助" },
      { "Esc", "返回卡带架（主机保留）" },
    },
    close = "[%s] 关闭",
  },
  en = {
    over = "YOU HAVE FALLEN.", won = "You claimed the Phosphor Heart; the dungeon crumbles.",
    again = "press %s to restart", score = "SCORE", depth = "DEPTH", best = "BEST", turn = "TURN",
    inv_title = "PACK", inv_empty = "(empty)", inv_hint = "↑↓ select   [%s] use   [%s] close",
    help_title = "CHARACTER & HELP", hp = "HP", atk = "ATK", def = "DEF", gold = "GOLD",
    fuel = "FUEL", light = "LIGHT", equip = "GEAR", seed = "SEED", none_w = "BARE", none_a = "CLOTH",
    keys_head = "CONTROLS", keys = {
      { "ARROWS", "move / bump to attack" },
      { "SPACE", "wait one turn" },
      { "%s", "pick up item at feet" },
      { "%s", "pack" },
      { "%s", "descend (on >)" },
      { "%s", "this help" },
      { "Esc", "back to shelf (host)" },
    },
    close = "[%s] close",
  },
}
local function L() return phos.lang.dict(Text) end

local cart = {}
local world
local best_score, best_depth, runs = 0, 0, 0
local modal = "none"      -- none / inv / help
local inv_sel = 0         -- 背包选择（0 基，phos.ui.nav 同约定）
local reported = false    -- 本局是否已结算过（防重复写盘）

-- ---------- 生命周期 ----------

local function register_debug()
  phos.debug.number({ zh = "怪物生命倍率", en = "Monster HP x" },
    function() return World.HP_MULT end, function(v) World.HP_MULT = v end,
    { min = 0.2, max = 3.0, step = 0.1 })
  phos.debug.number({ zh = "玩家攻击倍率", en = "Player ATK x" },
    function() return World.ATK_MULT end, function(v) World.ATK_MULT = v end,
    { min = 0.2, max = 3.0, step = 0.1 })
  phos.debug.number({ zh = "掉落金币倍率", en = "Gold drop x" },
    function() return World.DROP_MULT end, function(v) World.DROP_MULT = v end,
    { min = 0.2, max = 5.0, step = 0.1 })
end

-- 起一局新游戏。种子**用完即写盘**（便于复盘），但不主动 phos.sys.seed——
-- 这样主机 `--seed N` 仍能决定整局的随机序列（DESIGN §15）。
local function new_run()
  local seed = phos.sys.random(1, 999999)
  phos.save.write("last_seed", tostring(seed))
  world = World.new({ seed = seed, best_score = best_score, best_depth = best_depth })
  modal, inv_sel, reported = "none", 0, false
end

function init()
  cart = phos.cart.info()
  best_score = tonumber(phos.save.read("best_score") or "0") or 0
  best_depth = tonumber(phos.save.read("best_depth") or "0") or 0
  runs = (tonumber(phos.save.read("runs") or "0") or 0) + 1
  phos.save.write("runs", tostring(runs))
  register_debug()
  new_run()

  -- 首进卡带的玩法提示（可选资源；缺了就跳过）
  local lang = phos.sys.language()
  local motd = phos.assets.text("assets/motd." .. lang .. ".txt") or phos.assets.text("assets/motd.txt")
  if motd then
    local lines = {}
    for line in motd:gmatch("[^\r\n]+") do lines[#lines + 1] = line end
    for i = #lines, 1, -1 do world:say(lines[i], "cyan") end
  end

  phos.audio.music(require("music"))
end

-- 结算：只在刷新纪录时写盘（不做每帧 IO）
local function settle()
  local sc = world:score()
  if sc > best_score then
    best_score = sc
    phos.save.write("best_score", tostring(sc))
  end
  local d = world.depth
  if world.won then d = 10 end
  if d > best_depth then
    best_depth = d
    phos.save.write("best_depth", tostring(d))
  end
  world.best_score = best_score
  world.best_depth = best_depth
end

local function flush()
  Sfx.play_all(world:take_events())
end

local function in_play() return world.alive and not world.won end

-- 背包浮窗：↑↓ 选择，[A] 使用，[B]/[X] 关闭
local function update_inv()
  local n = #world.p.inv
  if n == 0 then
    if phos.input.pressed("b") or phos.input.pressed("x") then modal = "none" end
    return
  end
  local idx, action = phos.ui.nav(n, math.min(inv_sel, n - 1))
  inv_sel = idx
  if action == "confirm" then
    world:use_item(inv_sel + 1)
    if #world.p.inv == 0 then modal = "none" end
  elseif action == "cancel" or phos.input.pressed("x") then
    modal = "none"
  end
end

function update(dt)
  if not world.alive then
    flush()
    if not reported then reported = true; settle() end
    if phos.input.pressed("a") then new_run() end
    return
  end
  if world.won then
    flush()
    if not reported then reported = true; settle() end
    if phos.input.pressed("a") then new_run() end
    return
  end

  if modal == "help" then
    if phos.input.pressed("b") or phos.input.pressed("h") then modal = "none" end
    flush()
    return
  end
  if modal == "inv" then
    update_inv()
    flush()
    return
  end

  -- 输入 → 意图（一个动作一个回合；每次动作前确认局面仍可玩）
  if in_play() and phos.input.pressed("left") then world:move(-1, 0) end
  if in_play() and phos.input.pressed("right") then world:move(1, 0) end
  if in_play() and phos.input.pressed("up") then world:move(0, -1) end
  if in_play() and phos.input.pressed("down") then world:move(0, 1) end
  if in_play() and phos.input.pressed("space") then world:wait() end
  if in_play() and phos.input.pressed("y") then world:descend() end
  if in_play() and phos.input.pressed("a") then world:pickup() end
  if in_play() and phos.input.pressed("x") then modal = "inv"; inv_sel = 0 end
  if in_play() and phos.input.pressed("h") then modal = "help" end

  flush()
end

-- ---------- 绘制 ----------

local function draw_world(S, C)
  local px, py = S.playfield()
  local ox, oy = px + 2, py + 2
  local map = world.map

  for my = 0, map.h - 1 do
    for mx = 0, map.w - 1 do
      local tile = map.tiles[my][mx]
      -- 未探索不画；已探索但当前不可见用暗灰记忆色（§7.2）。地板不能因为"非墙"就画出来。
      if world:visible(mx, my) or map:explored_at(mx, my) then
        local vis = world:visible(mx, my)
        local ch, col
        if tile == 0 then ch, col = "#", C.gray
        elseif tile == 1 then ch, col = ".", C.gray
        elseif tile == 2 then ch, col = "+", C.orange
        else ch, col = ">", C.cyan end
        if not vis then col = C.dark_gray end          -- 记忆地形：暗灰
        S.put(ox + mx, oy + my, ch, col)
      end
    end
  end

  -- 只画"当前可见"的实体（记忆里的怪物/物品不画，§7.2）
  for _, g in ipairs(world.gold) do
    if world:visible(g.x, g.y) then S.put(ox + g.x, oy + g.y, "$", C.yellow) end
  end
  for _, it in ipairs(world.items) do
    if world:visible(it.x, it.y) then
      if it.kind == "heart" then
        local blink = (world.turn % 20) < 10
        S.put(ox + it.x, oy + it.y, "*", blink and C.white or C.yellow)
      else
        S.put(ox + it.x, oy + it.y, it.def.glyph, C[it.def.color] or C.white)
      end
    end
  end
  for _, m in ipairs(world.monsters) do
    if world:visible(m.x, m.y) then
      S.put(ox + m.x, oy + m.y, m.glyph, C[m.color] or C.white)
    end
  end
  S.put(ox + world.p.x, oy + world.p.y, "@", C.cyan)
end

-- 浮窗在**游戏区**里居中：侧栏不算进游戏画面（拿整个内容区居中会偏到侧栏上）。
local function centered(bw, bh)
  local _, _, pw, ph = phos.screen.playfield()
  return math.floor((pw - bw) / 2), math.floor((ph - bh) / 2)
end

local function draw_inventory(S, C)
  local t = L()
  local bw, bh = 34, 14
  local bx, by = centered(bw, bh)
  local r = Hud.plate(bx, by, bw, bh, t.inv_title)
  local letters = "abcdefgh"
  if #world.p.inv == 0 then
    r:print(2, 3, t.inv_empty, C.dark_gray)
  end
  for i = 0, 7 do
    local spec = world.p.inv[i + 1]
    local y = 2 + i
    local marker = (i == inv_sel) and ">" or " "
    if spec then
      local name = phos.lang.pick(spec.name)
      local line = string.format("%s %s) %s %s", marker, letters:sub(i + 1, i + 1), spec.glyph, name)
      r:print(2, y, phos.text.fit(line, bw - 4), C[spec.color] or C.white)
    else
      r:print(2, y, string.format("%s %s) -", marker, letters:sub(i + 1, i + 1)), C.dark_gray)
    end
  end
  local kn = phos.input.key_name
  r:print(2, bh - 2, phos.text.fit(string.format(t.inv_hint, kn("a"), kn("b")), bw - 4), C.dark_gray)
end

local function draw_help(S, C)
  local t = L()
  local bw, bh = 46, 20
  local bx, by = centered(bw, bh)
  local r = Hud.plate(bx, by, bw, bh, t.help_title)
  local p = world.p
  local kn = phos.input.key_name
  local y = 2
  r:print(2, y, string.format("%s %d/%d    %s %d    %s %d", t.hp, p.hp, p.max_hp, t.fuel, p.fuel, t.gold, p.gold), C.white); y = y + 1
  r:print(2, y, string.format("%s %d    %s %d    %s %d", t.atk,
    math.floor(world.p.atk + (p.weapon and p.weapon.bonus or 0)), t.def,
    math.floor(world.p.def + (p.armor and p.armor.bonus or 0)), t.light, world.radius or 0), C.white); y = y + 1
  local wn = p.weapon and phos.lang.pick(p.weapon.name) or t.none_w
  local an = p.armor and phos.lang.pick(p.armor.name) or t.none_a
  r:print(2, y, phos.text.fit(t.equip .. "  " .. wn .. " / " .. an, bw - 4), C.gray); y = y + 2
  r:print(2, y, t.keys_head, C.yellow); y = y + 1
  local keyargs = { kn("a"), kn("x"), kn("y"), kn("h") }
  local ai = 1
  for _, row in ipairs(t.keys) do
    local label = row[1]
    if label:find("%%s") then label = string.format(label, keyargs[ai]); ai = ai + 1 end
    r:print(2, y, phos.text.fit(phos.text.pad(label, 8) .. " " .. row[2], bw - 4), C.white)
    y = y + 1
  end
  r:print(2, bh - 2, phos.text.fit(string.format(t.close, kn("b")), bw - 4), C.dark_gray)
end

local function draw_end(S, C, won)
  local t = L()
  local bw, bh = 40, 8
  local bx, by = centered(bw, bh)
  local r = Hud.plate(bx, by, bw, bh, "")
  local title = won and t.won or t.over
  r:print(2, 1, phos.text.fit(title, bw - 4), won and C.green or C.red)
  r:print(2, 3, string.format("%s %d    %s %d/10    %s %d", t.score, world:score(),
    t.depth, world.depth, t.turn, world.turn), C.white)
  r:print(2, 4, string.format("%s %d", t.best, best_score), C.yellow)
  r:print(2, bh - 2, string.format(t.again, phos.input.key_name("a")), C.cyan)
end

function draw()
  local C, S = phos.color, phos.screen
  S.clear()
  draw_world(S, C)
  Hud.draw_top(S, C, { cart = cart, world = world })
  Hud.draw_rules(S, C)
  Hud.draw_log(S, C, { world = world })
  Panel.draw(world, cart)

  if modal == "inv" then draw_inventory(S, C)
  elseif modal == "help" then draw_help(S, C) end

  if not world.alive then draw_end(S, C, false)
  elseif world.won then draw_end(S, C, true) end
end

-- agent / 自测观察口（DESIGN §14.2）
function debug_state()
  local d = world:debug()
  d.modal = modal
  d.best_score = best_score
  d.best_depth = best_depth
  d.runs = runs
  return d
end

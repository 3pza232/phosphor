-- main.lua —— CHOMP 入口：模块装配 + 输入转发 + 绘制
--
-- 分工（见 docs/devkit.md）：game.lua 只认规则；这里把键盘翻译成玩法意图
-- （game:turn），再把玩法状态画出来。迷宫 61x37 铺满内容区，键位提示在侧栏底部。

local Game = require("game")
local Panel = require("panel")
local Sfx = require("sfx")
local Music = require("music")

local Text = {
  zh = {
    tagline = "吃光豆子，别被咬到",
    ready = "准备…",
    paused = "暂停",
    cleared = "过关！",
    again = "按 %s 重新开始",
    record = "新纪录",
  },
  en = {
    tagline = "clear the dots, don't get bitten",
    ready = "READY…",
    paused = "PAUSED",
    cleared = "LEVEL CLEAR!",
    again = "press %s to start again",
    record = "NEW RECORD",
  },
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

-- 迷宫铺满内容区：x 从 0 起（61 列），纵向留出标题行与状态行
local OX = 0
local OY = 4
local WALL_EDGE, WALL_INNER = "█", "▓"
local DOT_GLYPH, POWER_GLYPH, FRUIT_GLYPH = "·", "●", "♥"
local GHOST_GLYPH, EATEN_GLYPH = "▲", "◦"
local PLAYER_GLYPH = { "●", "◐", "●", "◑" }   -- 张合的嘴
local GHOST_COLOR = { blinky = "red", pinky = "magenta", inky = "cyan", clyde = "orange" }

local game
local cart = {}
local paused, reported, flash = false, false, 0

local function save_best()
  if phos.save.available() then phos.save.write("best", tostring(game.best)) end
end

local function restart()
  game:reset_run()
  paused, reported = false, false
  phos.audio.paused(false)
end

function init()
  cart = phos.cart.info()
  game = Game.new()
  local saved = phos.save.read("best")
  if saved then game.best = tonumber(saved) or 0 end
  phos.audio.music(Music)
end

function update(dt)
  flash = flash + dt

  if game.state == "over" then
    if not reported then
      reported = true
      save_best()
    end
    if phos.input.pressed("start") then restart() end
    return
  end

  if phos.input.pressed("start") then
    paused = not paused
    phos.audio.paused(paused)
  end
  if phos.input.pressed("select") then restart() end
  if paused then return end

  -- 输入 → 意图：这里只回答"哪个键按下了"，能不能转向由规则判定
  if phos.input.pressed("left") then game:turn(-1, 0) end
  if phos.input.pressed("right") then game:turn(1, 0) end
  if phos.input.pressed("up") then game:turn(0, -1) end
  if phos.input.pressed("down") then game:turn(0, 1) end

  local events = game:update(dt)
  if events.eat then Sfx.chomp(game.player.chomp) end
  if events.power then Sfx.power() end
  if events.ghost then Sfx.ghost() end
  if events.bonus or events.fruit then Sfx.bonus() end
  if events.death then Sfx.death() end
  if events.cleared then Sfx.cleared() end
  if events.gameover then Sfx.gameover() end
  if game.score > game.best then game.best = game.score end
end

-- 顶栏：左边卡带名，右边记分（当前分与最高分并排，越过最高分时闪一下）
local function draw_top(S, C, t)
  S.print(0, 1, cart.name or "CHOMP", C.yellow)
  S.print(2 + phos.text.width(cart.name or "CHOMP"), 1, "· " .. t.tagline, C.dark_gray)

  local score = string.format("%06d", game.score)
  local best = string.format("%06d", game.best)
  local beat = game.score >= game.best and game.score > 0
  local label = "HI " .. best .. "  " .. score
  local x = Game.W - phos.text.width(label)
  S.print(x, 1, label, beat and ((flash % 0.6 < 0.3) and C.white or C.yellow) or C.gray)
end

local function draw_rule(S, C)
  for x = 0, Game.W do
    S.put(x, 2, "·", (x % 2 == 0) and C.dark_gray or C.black)
  end
end

local function draw_maze(S, C)
  for r = 1, Game.H do
    for c = 1, Game.W do
      local x, y = OX + c - 1, OY + r - 1
      local ch = game.grid[r][c]
      if ch == "." then
        S.put(x, y, DOT_GLYPH, C.gray)
      elseif ch == "o" then
        -- 能量豆缓慢呼吸：一亮一灭，提示"这是好东西"
        S.put(x, y, POWER_GLYPH, (flash % 0.7 < 0.45) and C.white or C.yellow)
      elseif Game:is_wall(r, c) then
        -- 外框实心、内部中灰块：迷宫因此有厚度，而不是一堆散点
        local edge = (r == 1 or r == Game.H or c == 1 or c == Game.W)
        S.put(x, y, edge and WALL_EDGE or WALL_INNER, C.purple)
      end
    end
  end
end

local function draw_actors(S, C)
  if game.fruit then
    S.put(OX + game.fruit.c - 1, OY + game.fruit.r - 1, FRUIT_GLYPH, C.red)
  end

  for _, g in ipairs(game.ghosts) do
    local x, y = OX + g.c - 1, OY + g.r - 1
    if not g.eaten then
      local col
      if game.fright_timer > 0 then
        -- 快结束时闪白：给玩家一个"该收手了"的信号
        local blink = game.fright_timer < 2 and flash % 0.4 < 0.2
        col = blink and C.white or C.blue
      else
        col = C[GHOST_COLOR[g.name]] or C.red
      end
      S.put(x, y, GHOST_GLYPH, col)
    end
  end

  local p = game.player
  if p.alive and game.state ~= "dying" then
    S.put(OX + p.c - 1, OY + p.r - 1, PLAYER_GLYPH[p.chomp + 1], C.yellow)
  end
end

local function draw_status(S, C, t)
  local mid = OX + Game.W // 2
  local msg
  if paused then
    msg = t.paused
  elseif game.state == "ready" then
    msg = t.ready
  elseif game.state == "clear" then
    msg = t.cleared
  elseif game.state == "over" then
    msg = string.format(t.again, phos.input.key_name("start"))
  end
  if msg then S.print(mid - phos.text.width(msg) // 2, OY + Game.H + 2, msg, C.white) end
end

function draw()
  local C, S = phos.color, phos.screen
  local t = L()
  S.clear()
  draw_top(S, C, t)
  draw_rule(S, C)
  draw_maze(S, C)
  draw_actors(S, C)
  draw_status(S, C, t)
  Panel.draw(game, t)
end

-- agent 观察入口：主机在 state.query 时会把这里返回的表一并带上
function debug_state()
  local status = game:status()
  status.paused = paused
  status.best = game.best
  return status
end

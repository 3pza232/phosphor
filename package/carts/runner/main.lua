-- main.lua —— RUNNER 入口：模块装配 + 输入转发 + 绘制
--
-- 分工（见 docs/devkit.md）：game.lua 只认规则，高度都以"离地面多少格"记账；
-- 这里把格子映射到屏幕（GROUND 是地面线所在行），并负责全部画法。
--
-- 可玩宽度注意：phos.screen.size() 宽 80，但声明了侧栏后右侧 panel.size() 列
-- 会被侧栏盖住——障碍若从那底下冒出来就是"贴脸"。所以世界宽度按 80 - 侧栏 算。

local Game = require("game")
local Panel = require("panel")
local Sfx = require("sfx")
local Music = require("music")

local Text = {
  zh = {
    ready = "准备…", paused = "暂停", again = "按 %s 重来",
    day = "白天", night = "夜里",
  },
  en = {
    ready = "READY…", paused = "PAUSED", again = "press %s to try again",
    day = "day", night = "night",
  },
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

local GROUND = 30                   -- 地面线所在行（0 基）
-- 小恐龙：7 宽 4 高，'#' 实心、'.' 透明。剪影由"头+吻（右上）、背、尾（左）、两条腿"构成；
-- 蹲下另画一张压低前伸的。颜色映射的键必须是单字节字符（见 game.lua 的说明）
local RUNNER_ART = {
  { "...####", "..#####", ".#####.", ".#..#.." },   -- 跑帧 1
  { "...####", "..#####", ".#####.", ".#...#." },   -- 跑帧 2
}
-- 蹲下只有**一行**：含义是"趴下之后背上什么也没有"。这是刻意的视觉契约，画法要跟它对齐：
--   贴地翼龙（下排就在地面上）会压住这一行 → 看上去"趴着也过不去"，只能跳
--   高位翼龙（整只抬高一格）正好从这一行上面掠过 → 看上去"趴着能过、站着才碰"
-- 画成两行高就两头都不像：趴下去仍与翼龙贴着，"能不能过"只能靠撞一次去猜
local DUCK_ART = { "#######" }

local game
local cart = {}
local view_w = 62                   -- 可玩宽度（内容区减去侧栏），init 里按实际量
local paused, reported, flash, scroll = false, false, 0, 0

local function palette(C)
  if game.night then
    return { ink = C.cyan, ground = C.blue, dune = C.dark_gray, pebble = C.blue }
  end
  return { ink = C.green, ground = C.orange, dune = C.dark_gray, pebble = C.orange }
end

local function save_best()
  if phos.save.available() then phos.save.write("best", tostring(game.best)) end
end

local function restart()
  game:reset_run()
  paused, reported, scroll = false, false, 0
  phos.audio.paused(false)
end

function init()
  cart = phos.cart.info()
  local sw = phos.screen.size()
  view_w = sw - phos.panel.size()
  game = Game.new(view_w)
  -- 把本卡带的可调常数交给 `~` 调试台（见 phos.debug.number）
  for _, t in ipairs(Game.tunables()) do
    phos.debug.number(t.name, t.get, t.set, { min = t.min, max = t.max, step = t.step })
  end
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

  -- 输入 → 意图：跳是"按住更高、松手更矮"，所以按下与松开各管一半
  if phos.input.pressed("up") or phos.input.pressed("a") then
    if game:jump() then Sfx.jump() end
  end
  if phos.input.released("up") or phos.input.released("a") then
    game:release_jump()
  end
  game:hold_down(phos.input.down("down"))   -- 地面上是蹲，空中是急速下落

  local events = game:update(dt)
  if events.land then Sfx.land() end
  if events.milestone then Sfx.milestone() end
  if events.stage then Sfx.stage(events.stage) end
  if events.death then Sfx.death() end
  if events.gameover then Sfx.gameover() end
  if game.score > game.best then game.best = math.floor(game.score) end
  scroll = scroll + game.speed * dt
end

-- 天空：白天的太阳与流云、夜里的月亮与星空，都慢慢向后飘（比地面慢）
local function draw_sky(S, C, P)
  local phase = math.floor(scroll * 0.3)
  if game.night then
    for i = 0, 26 do
      local x = (i * 23 + phase * 3) % (view_w - 2) + 1
      local y = 2 + (i * 7) % 16
      S.put(x, y, (i % 3 == 0) and "*" or "·", (i % 4 == 0) and C.white or C.dark_gray)
    end
    S.put(view_w - 10, 4, "◐", C.gray)
  else
    S.put(view_w - 10, 4, "●", C.yellow)
    for i = 0, 4 do
      local x = (i * 21 + phase * 2) % (view_w - 10) + 2
      local y = 5 + (i * 6) % 12
      S.put(x, y, "▄▀▄", C.white)
      S.put(x, y + 1, "▀▀▀", C.gray)
    end
  end
  -- 远山：只画波峰附近，几段断开的山尖比连成长条更像远景
  for x = 0, view_w - 1 do
    local wave = math.sin((x + scroll * 0.15) * 0.09)
    if wave > 0.9 then S.put(x, GROUND - 6, "▄", P.dune) end
    if wave > 0.8 then S.put(x, GROUND - 5, "▄", P.dune) end
    if wave > 0.6 then S.put(x, GROUND - 4, "▄", P.dune) end
  end
end

-- 地面与沙地：地面线之上干净（跑者要站在这里），之下铺沙、碎石与几块石头
local function draw_ground(S, C, P)
  for x = 0, view_w - 1 do
    S.put(x, GROUND, "▔", P.ground)
  end
  local phase = math.floor(scroll)
  local span = view_w - 1
  for i = 0, 42 do
    local x = ((i * 11 - phase) % span + span) % span
    local depth = 1 + (i * 5) % 12
    local glyph = (i % 5 == 0) and "░" or ((i % 2 == 0) and "." or ",")
    S.put(x, GROUND + depth, glyph, P.pebble)
  end
  for i = 0, 3 do
    local x = ((i * 37 - phase) % (span - 4) + (span - 4)) % (span - 4) + 2
    S.put(x, GROUND + 6 + i * 2, "◆", P.dune)
  end
end

-- 画字符画：'.' 是透明格，其余格子铺一块实心方块并上色。
-- 不用 phos.ui.sprite 是因为它把字符画里的字符**原样写上去**：想得到实心像素就得用 '█'，
-- 而它的颜色映射以单字节字符为键，'█' 查不到表 → 退化成风格色。自己画两个要求都满足。
local function draw_art(S, x, y, rows, color)
  for r = 1, #rows do
    local row = rows[r]
    for c = 1, #row do
      if row:sub(c, c) ~= "." then S.put(x + c - 1, y + r - 1, "█", color) end
    end
  end
end

local function draw_runner(S, C)
  local run = game.runner
  local lift = math.floor(run.lift)
  if run.ducking then
    draw_art(S, Game.RUNNER_X, GROUND - lift - #DUCK_ART, DUCK_ART, C.white)
  else
    local frame = (math.floor(run.stride * 2) % 2) + 1
    draw_art(S, Game.RUNNER_X, GROUND - lift - #RUNNER_ART[frame], RUNNER_ART[frame], C.white)
  end
end

local function draw_obstacles(S, C, P)
  for _, o in ipairs(game.obstacles) do
    local x = math.floor(o.x + 0.5)
    if x > -4 and x < view_w + 2 then
      local color = o.bird and C.gray or P.ink
      draw_art(S, x, GROUND - o.lift - #o.shape, o.shape, color)
    end
  end
end

-- 记分牌：当前分与最高分并排；越过最高分时闪一下
local function draw_score(S, C, t)
  local label = "HI " .. string.format("%05d", game.best) .. "   " ..
                string.format("%05d", math.floor(game.score))
  local beat = game.score > 0 and game.score >= game.best
  local color = (beat and (flash % 0.6 < 0.3)) and C.white or C.gray
  S.print(view_w - 1 - phos.text.width(label), 1, label, color)
  S.print(0, 1, game.night and t.night or t.day, C.dark_gray)
end

local function draw_state(S, C, t)
  local msg
  if paused then
    msg = t.paused
  elseif game.state == "ready" then
    msg = t.ready
  elseif game.state == "over" then
    msg = string.format(t.again, phos.input.key_name("start"))
  end
  if msg then S.print(view_w // 2 - phos.text.width(msg) // 2, 20, msg, C.white) end
end

function draw()
  local C, S = phos.color, phos.screen
  local t = L()
  local P = palette(C)
  S.clear()
  draw_sky(S, C, P)
  draw_ground(S, C, P)
  draw_obstacles(S, C, P)
  draw_runner(S, C)
  draw_score(S, C, t)
  draw_state(S, C, t)
  Panel.draw(game, t)
end

-- agent 观察入口：主机在 state.query 时会把这里返回的表一并带上
function debug_state()
  local status = game:status()
  status.paused = paused
  status.view_w = view_w
  return status
end

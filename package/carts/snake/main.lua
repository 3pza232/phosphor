-- main.lua —— 卡带入口：模块装配 + 输入转发 + 画面绘制
--
-- 结构（同目录下各司其职，便于单人维护也便于被 mod 单独替换）：
--   music.lua   曲式化记谱（约两分钟循环）
--   sfx.lua     音效
--   scores.lua  历史分数（存档）
--   game.lua    玩法状态机（不碰输入/绘制/音频/存档）
--   panel.lua   侧栏渲染
--
-- 本文件只做"粘合"两件事：把键盘**翻译成玩法意图**（game:turn），
-- 把玩法状态**画到屏幕上**（场地、蛇、食物、结束浮层、状态条）。
-- 方向键移动，撞墙或撞自己结束，Enter 重开

local Game = require("game")
local Panel = require("panel")
local Scores = require("scores")
local Sfx = require("sfx")
local Music = require("music")

-- 界面文案：跟随机器的界面语言（新增语言只需加一列，取值一律走 L()）
local Text = {
  zh = {over = "游戏结束", restart = "按 %s 重开"},
  en = {over = "GAME OVER", restart = "press %s to restart"},
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

local game

function init()
  Scores.load()
  game = Game.new()
  phos.audio.music(Music)  -- 开机即播放本卡带的音乐
end

function update(dt)
  if not game.alive then
    -- 结束画面：Enter 重开。哪个键重开属于输入层，玩法模块不认这个键
    if phos.input.pressed("start") then
      game:reset()
      Sfx.start()
    end
    return
  end

  -- 输入 → 意图：方向键只翻译方向，180 度掉头由游戏规则自己挡
  if phos.input.pressed("left")  then game:turn(-1, 0) end
  if phos.input.pressed("right") then game:turn(1, 0) end
  if phos.input.pressed("up")    then game:turn(0, -1) end
  if phos.input.pressed("down")  then game:turn(0, 1) end

  local events = game:update(dt)
  if events.eaten then Sfx.eat() end
  if events.died then
    Scores.add(game.score)
    Sfx.die()
  end
end

function draw()
  local C, S = phos.color, phos.screen
  S.clear()

  -- 场地边框：交给主机组件层，保持与系统界面同风格
  phos.ui.frame(Game.ARENA.x, Game.ARENA.y, Game.ARENA.w + 2, Game.ARENA.h + 2, "")

  local ox, oy = Game.ARENA.x + 1, Game.ARENA.y + 1
  S.put(ox + game.food[1], oy + game.food[2], "O", C.red)

  for i, seg in ipairs(game.body) do
    S.put(ox + seg[1], oy + seg[2],
          i == 1 and "@" or "o",
          i == 1 and C.green or C.cyan)
  end

  if not game.alive then
    local cx = Game.ARENA.x + Game.ARENA.w // 2
    local cy = Game.ARENA.y + Game.ARENA.h // 2
    local over = L().over
    local restart = string.format(L().restart, phos.input.key_name("start"))
    S.print(cx - phos.text.width(over) // 2, cy, over, C.red)
    S.print(cx - phos.text.width(restart) // 2, cy + 2, restart, C.gray)
  end

  Panel.draw(game, Scores)

  -- 底部状态条：与 LIFE 同一套做法——先画一个框，读数写在框里。
  -- 直接写在场地边框那一行会把边框吃掉，所以给它自己的框（ASCII 遥测，
  -- 供 agent 直接解析，不必从中文面板里反推）
  local state = game.alive and "RUNNING" or "OVER"
  phos.ui.frame(Game.ARENA.x, Game.ARENA.y + Game.ARENA.h + 1, Game.ARENA.w + 2, 3, "")
  S.print(Game.ARENA.x + 2, Game.ARENA.y + Game.ARENA.h + 2,
          string.format("SCORE %d | LEN %d | %s", game.score, game:length(), state), C.gray)
end

-- agent 观测入口（可选约定）：主机在 state.query 时会把这里返回的表一并带上，
-- 让 agent 直接读到玩法状态，而不必从字符画面里反推
function debug_state()
  return {
    score = game.score,
    alive = game.alive,
    length = game:length(),
    dir_x = game.dx, dir_y = game.dy,
    head_x = game.body[1][1], head_y = game.body[1][2],
    food_x = game.food[1], food_y = game.food[2],
    arena_w = Game.ARENA.w, arena_h = Game.ARENA.h,
    best = Scores.best(),
  }
end

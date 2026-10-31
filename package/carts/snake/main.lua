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
local board

-- agent 观测：字段可以是函数，主机在 state.query 时求值——不必维护手写快照。
-- （等价于旧的 debug_state()，但这张表不会与真实状态脱节）
local function observe_state()
  phos.observe{
    score = function() return game.score end,
    alive = function() return game.alive end,
    length = function() return game:length() end,
    dir_x = function() return game.dx end,
    dir_y = function() return game.dy end,
    head_x = function() return game.body[1][1] end,
    head_y = function() return game.body[1][2] end,
    food_x = function() return game.food[1] end,
    food_y = function() return game.food[2] end,
    arena_w = Game.ARENA.w,
    arena_h = Game.ARENA.h,
    best = function() return board:best() end,
  }
end
  -- phos.score：排行榜（排序/截断/存档键都由引擎负责）

function init()
  game = Game.new()
  board = phos.score.new{ max = 5, key = "scores" }
  phos.audio.music(Music)  -- 开机即播放本卡带的音乐
  -- 把"移动间隔"放进调试台的可调篮子：`~` 面板里拖滑条就能实时改速度
  phos.debug.number({ zh = "移动间隔", en = "Move interval" },
                    function() return game.move_interval end,
                    function(v) game.move_interval = v end,
                    { min = 0.03, max = 0.30, step = 0.005 })
  observe_state()
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
    if game.score > 0 then board:add(game.score) end   -- 0 分不入榜（引擎接受 0，这里按玩法过滤）
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

  Panel.draw(game, board)

  -- 底部状态条：与 LIFE 同一套做法——先画一个框，读数写在框里。
  -- 直接写在场地边框那一行会把边框吃掉，所以给它自己的框（ASCII 遥测，
  -- 供 agent 直接解析，不必从中文面板里反推）
  local state = game.alive and "RUNNING" or "OVER"
  phos.ui.frame(Game.ARENA.x, Game.ARENA.y + Game.ARENA.h + 1, Game.ARENA.w + 2, 3, "")
  S.print(Game.ARENA.x + 2, Game.ARENA.y + Game.ARENA.h + 2,
          string.format("SCORE %d | LEN %d | %s", game.score, game:length(), state), C.gray)
end


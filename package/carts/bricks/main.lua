-- main.lua —— 打砖块（卡带入口：装配模块 + 生命周期粘合）
--
-- 操作（键位与键盘一一对应，提示文字用 phos.input.key_name 生成）：
--   左右      移动挡板
--   A         发射（球停在挡板上时）/ 重开（游戏结束后）
--   Enter     暂停 / 继续（卡带自己的暂停，不影响主机菜单）
--   Shift     重新开始
--   Esc       主机暂停菜单（卡带看不到）

local Game = require("game")
local Panel = require("panel")
local Sfx = require("sfx")

-- 界面文案：跟随机器的界面语言。新增语言只需加一列，取值处一律走 L()
local Text = {
  zh = {paused = "已暂停", over = "游戏结束 - 按 %s 重开", record = "新纪录 %d",
        cleared = "过关", ready = "按 %s 发射"},
  en = {paused = "PAUSED", over = "GAME OVER - press %s to restart", record = "NEW RECORD %d",
        cleared = "CLEARED", ready = "press %s to launch"},
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end
local Music = require("music")

local game
local board           -- 排行榜（引擎负责排序/截断/存档键）
local reported        -- 本局是否已提交过纪录

local function report_score()
  if reported then return end
  reported = true
  local before = board:best()
  board:add(game.score)
  if game.score > 0 and board:best() > before then
    phos.sys.log(string.format("new record: %d", game.score))
  end
end

local function restart()
  phos.scene.clear()
  game:restart()
  reported = false
end

-- 暂停浮窗交给场景栈：pause_world 冻结世界、audio_pause 暂停音频，出栈自动恢复
local function pause_update(dt)
  if phos.input.pressed("start") or phos.input.pressed("b") then
    phos.scene.pop()
  elseif phos.input.pressed("select") then
    phos.scene.clear()
    restart()
  end
end

local function pause_draw()
  local words = phos.lang.shared()
  phos.ui.render{
    screen = "pause", rect = { x = 22, y = 14, w = 36, h = 10 },
    kind = "box", title = words.paused, border = "single", opaque = true, bg = "black",
    children = {
      { kind = "stat", text = words.score, value = phos.text.score(game.score), label_w = 7 },
      { kind = "stat", text = words.best, value = phos.text.score(board:best()), label_w = 7 },
      { kind = "divider", fg = "dark_gray" },
      { kind = "hint", items = { phos.input.key_name("start"), "resume",
                                 phos.input.key_name("select"), "restart" } },
    },
  }
end

function init()
  board = phos.score.new{ max = 1, key = "best" }
  game = Game.new()
  -- 把本卡带的可调常数交给 `~` 调试台（见 phos.debug.number）
  for _, t in ipairs(Game.tunables()) do
    phos.debug.number(t.name, t.get, t.set, { min = t.min, max = t.max, step = t.step })
  end
  reported = false
  phos.audio.music(Music)
  phos.observe{
    score = function() return game.score end,
    best = function() return board:best() end,
    lives = function() return game.lives end,
    level = function() return game.level end,
    state = function() return game.state end,
    paused = function() return phos.scene.depth() > 0 end,
    bricks_left = function() return game.bricks_left end,
    paddle_x = function() return math.floor(game.paddle_x) end,
    ball_x = function() return math.floor(game.ball_x + 0.5) end,
    ball_y = function() return math.floor(game.ball_y + 0.5) end,
    field_w = Game.W,
    field_h = Game.H,
  }
end

function update(dt)
  if phos.input.pressed("start") and phos.scene.depth() == 0 then
    phos.scene.push{
      id = "pause", modal = true, pause_world = true, audio_pause = true,
      update = pause_update, draw = pause_draw,
    }
  end

  if phos.input.pressed("select") then restart() end

  if phos.input.down("left") then game:move_paddle(-1, dt) end
  if phos.input.down("right") then game:move_paddle(1, dt) end

  if phos.input.pressed("a") then
    if game.state == "gameover" then
      restart()
    elseif game:launch() then
      Sfx.launch()
    end
  end

  local events = game:update(dt)
  if events.paddle then Sfx.paddle() end
  if events.wall then Sfx.wall() end
  if events.brick then Sfx.brick(events.brick) end
  if events.cleared then Sfx.cleared() end
  if events.dead then Sfx.dead() end
  if events.gameover then
    Sfx.gameover()
    report_score()
  end
end

function draw()
  local C, S = phos.color, phos.screen
  S.clear()

  -- 场地边框与标题
  phos.ui.frame(Game.OX - 1, Game.OY - 1, Game.W + 2, Game.H + 2, "BRICKS")

  -- 砖块：每块 3 字符宽，颜色由档位决定
  for row = 0, Game.BRICK_ROWS - 1 do
    for col = 0, Game.BRICK_COLS - 1 do
      local tier = game.bricks[row * Game.BRICK_COLS + col + 1]
      if tier then
        local bx = Game.OX + col * Game.BRICK_STRIDE
        local by = Game.OY + row
        S.fill(bx, by, Game.BRICK_W, 1, "#", C[game:color_of(tier)] or C.white)
      end
    end
  end

  -- 挡板
  local px = Game.OX + math.floor(game.paddle_x + 0.5)
  S.fill(px, Game.OY + Game.PADDLE_ROW, Game.PADDLE_W, 1, "=", C.cyan)

  -- 球
  S.put(Game.OX + math.floor(game.ball_x + 0.5), Game.OY + math.floor(game.ball_y + 0.5), "o",
        C.white)

  -- 中央提示（暂停优先：否则在 ready 状态按暂停会看不出任何变化）
  local mid = math.floor(Game.H / 2) + Game.OY
  local launch_key = phos.input.key_name("a")
  if game.state == "gameover" then
    phos.ui.center_text(mid, string.format(L().over, launch_key))
    if board:best() <= game.score then
      phos.ui.center_text(mid + 2, string.format(L().record, game.score))
    end
  elseif game.state == "cleared" then
    phos.ui.center_text(mid, L().cleared)
  elseif game.state == "ready" then
    phos.ui.center_text(mid, string.format(L().ready, launch_key))
  end

  -- 底部状态读数：状态 / 关卡 / 挡板 / 球 / 球速（与 LIFE 的 GEN-POP 行同一套做法）。
  -- 关卡也放这里，是为了让它可被断言：面板上那份是中文界面文案，会随界面语言变
  local status = string.upper(game.state)
  S.print(Game.OX, Game.OY + Game.H + 1,
          string.format("%s | LV %d | PAD %d | BALL %d,%d | SPD %d", status, game.level,
                        math.floor(game.paddle_x + 0.5), math.floor(game.ball_x + 0.5),
                        math.floor(game.ball_y + 0.5), math.floor(game:ball_speed() + 0.5)), C.gray)

  Panel.draw({
    score = game.score,
    best = board:best(),
    lives = game.lives,
    level = game.level,
    time = game.time,
    bricks_left = game.bricks_left,
  })
end

-- 观测在 init 里用 phos.observe 声明（字段为函数，查询时求值）

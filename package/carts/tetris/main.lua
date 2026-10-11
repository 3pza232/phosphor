-- TETRIS —— 俄罗斯方块（卡带入口：装配模块 + 分层绘制）
--
-- 操作（提示文字用 phos.input.key_name 生成，与键盘一一对应）：
--   左右      移动（按住会连发）
--   上 / X    顺时针旋转      Z   逆时针旋转
--   下        加速下落
--   Space     硬降（直接落底）
--   Enter     暂停 / 继续        Shift  重新开始
--   Esc       主机暂停菜单（卡带看不到）
--
-- 这份卡带用**图层**把三件互不相干的事分开（见 docs/api-reference.md 的 phos.layer）：
--   底层     井、已落定的方块、落点投影 —— 就是不分层的卡带也会有的那一层
--   piece    正在下落的方块：它不必知道底下堆成什么样
--   fx       消行闪光 / 硬降拖尾 / 加分浮字：**只写字形**，压在世界上，底下透得出来
--   overlay  暂停 / 结束的浮窗：整块铺底板，把井挡住
-- 层每帧由主机清成透明，所以"这一帧不画它"就等于它消失，不必自己擦

local Game = require("game")
local Panel = require("panel")
local Sfx = require("sfx")
local Scores = require("scores")
local Music = require("music")

-- 界面文案：跟随机器的界面语言（新增语言加一列即可）
local Text = {
  zh = {paused = "已暂停", over = "游戏结束", restart = "按 %s 重开",
        score = "得分 %d", record = "新纪录 %d", resume = "按 %s 继续",
        level = "等级", lines = "行数"},
  en = {paused = "PAUSED", over = "GAME OVER", restart = "press %s to restart",
        score = "SCORE %d", record = "NEW RECORD %d", resume = "press %s to resume",
        level = "LEVEL", lines = "LINES"},
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

-- 一格方块画成 BLOCK×BLOCK 个字符。内容区是 62×45 字符，1 格 1 字符的话井只占
-- 10×20、在屏幕中间空荡荡一小块；铺成 2×2 之后井是 20×40，高度基本吃满。
-- 棋盘坐标仍是 game.lua 里的 10×20 —— 放大只发生在画的时候
local BLOCK = 2

-- 井内区左上角。井框画在它外面一圈（22×42），底下还留两行写等级与提示
local WELL_X, WELL_Y = 21, 2

-- 消行闪光 / 加分浮字的存在时长（秒）
local FLOAT_TIME = 0.9

local game
local paused, reported
local r_piece, r_fx, r_overlay
local floats = {}          -- 加分浮字：{ text, x, y, t }
local repeat_timer = 0
local trail = nil          -- 硬降拖尾：{ x, from, to, t }

local function report_score()
  if reported then return end
  reported = true
  if Scores.submit(game.score) then phos.sys.log(string.format("new record: %d", game.score)) end
end

function init()
  Scores.load()
  game = Game.new()
  paused, reported = false, false
  floats, trail, repeat_timer = {}, nil, 0

  -- 取用分层的全部成本：建层 + 把绘制区域锚定到层
  phos.layer.create("piece", { z = 10 })      -- 下落中的方块
  phos.layer.create("fx", { z = 20 })         -- 特效（只写字形，透出下层）
  phos.layer.create("overlay", { z = 30 })    -- 浮窗（整块不透明）
  local _, _, pw, ph = phos.screen.playfield()
  r_piece = phos.ui.region(WELL_X, WELL_Y, Game.W * BLOCK, Game.H * BLOCK, { layer = "piece" })
  r_fx = phos.ui.region(0, 0, pw, ph, { layer = "fx" })
  r_overlay = phos.ui.region(WELL_X - 2, WELL_Y + 14, 24, 8, { layer = "overlay" })

  phos.audio.music(Music)
end

-- 左右移动：点按走一格，按住先慢后快。连发的"快慢"直接取主机的按住时长，
-- 不必自己存延迟（这也是 phos.input.duration 存在的理由）
local function move_repeat(dt, key, dir)
  if not phos.input.down(key) then
    -- 松开就把计时清零：留着的"欠账"会在下一次点按时一次性补成几十格，
    -- 方块直接被甩到墙上
    repeat_timer = 0
    return
  end
  if phos.input.pressed(key) then
    if game:move(dir) then Sfx.move() end
    return
  end
  repeat_timer = repeat_timer + dt
  local gap = math.max(0.035, 0.16 - phos.input.duration(key) * 0.25)
  while repeat_timer >= gap do
    repeat_timer = repeat_timer - gap
    if game:move(dir) then Sfx.move() end
  end
end

local function add_float(text, x, y)
  floats[#floats + 1] = { text = text, x = x, y = y, t = FLOAT_TIME }
end

local function play(ev)
  if ev.locked then Sfx.lock() end
  if ev.cleared and ev.cleared > 0 then
    Sfx.clear(ev.cleared)
    -- 消行的那几行在井里闪一下，进账浮在井上方。
    -- 乘等级要乘在**数字**上：写成 string.format(...) * level 的话，乘法会作用在字符串上
    -- 并把它变成 number，而 print 只收字符串（传数字会当场报错）
    local gain = (({ 0, 100, 300, 500, 800 })[ev.cleared] or 800) * game.level
    add_float(string.format("+%d", gain), WELL_X + Game.W - 4, WELL_Y + 8)
  end
  if ev.levelup then Sfx.levelup() end
  if ev.gameover then
    Sfx.gameover()
    report_score()
  end
end

function update(dt)
  if phos.input.pressed("start") then
    paused = not paused
    phos.audio.beep(paused and 300 or 700, 0.05, { wave = "square", volume = 0.18 })
  end
  if phos.input.pressed("select") then
    game:restart()
    paused, reported = false, false
    floats, trail = {}, nil
  end

  -- 浮字与拖尾按真实时间衰减：暂停时也让它走完，免得残在画面上
  for i = #floats, 1, -1 do
    floats[i].t = floats[i].t - dt
    floats[i].y = floats[i].y - dt * 4
    if floats[i].t <= 0 then table.remove(floats, i) end
  end
  if trail then
    trail.t = trail.t - dt
    if trail.t <= 0 then trail = nil end
  end

  if paused then return end

  if game.state == "gameover" then
    if phos.input.pressed("a") then
      game:restart()
      reported = false
      floats, trail = {}, nil
    end
    return
  end

  move_repeat(dt, "left", -1)
  move_repeat(dt, "right", 1)
  if phos.input.pressed("up") or phos.input.pressed("x") then
    if game:rotate(1) then Sfx.rotate() end
  end
  if phos.input.pressed("z") then
    if game:rotate(-1) then Sfx.rotate() end
  end

  game.soft = phos.input.down("down")
  if phos.input.pressed("space") and game.piece then
    -- 落点与列号要在落底**之前**记下：硬降会把这一块写进棋盘、并把下一块换上来
    local from_y, trail_x = game.piece.y, WELL_X + (game.piece.x - 1) * BLOCK
    local dist, cleared = game:hard_drop()
    if dist > 0 then
      trail = { x = trail_x, from = from_y, to = from_y + dist, t = 0.18 }
      Sfx.hard_drop()
    end
    play({ locked = true, cleared = cleared, gameover = game.state == "gameover" })
    return
  end

  play(game:update(dt))
end

-- 把一个棋盘格铺成 BLOCK×BLOCK 个字符。px, py 是这一格**左上角的字符坐标**：
-- 底层写的是内容区绝对坐标，层里写的是区域局部坐标。
-- 两个入口分得清清楚楚：区域必须用冒号调用（`r:put`）—— 把方法当函数传（`r.put`）
-- 会丢掉 self，运行时报 "expected userdata"
local function blit_screen(px, py, ch, color, bg)
  for dy = 0, BLOCK - 1 do
    for dx = 0, BLOCK - 1 do phos.screen.put(px + dx, py + dy, ch, color, bg) end
  end
end

local function blit_region(r, px, py, ch, color, bg)
  for dy = 0, BLOCK - 1 do
    for dx = 0, BLOCK - 1 do r:put(px + dx, py + dy, ch, color, bg) end
  end
end

-- 底层：井框 + 已落定的方块 + 落点投影
local function draw_world()
  local C = phos.color
  phos.screen.clear(C.dark_gray, C.rgb(10, 12, 22))
  phos.ui.frame(WELL_X - 1, WELL_Y - 1, Game.W * BLOCK + 2, Game.H * BLOCK + 2, "TETRIS")

  for y = 1, Game.H do
    for x = 1, Game.W do
      local kind = game.board[y][x]
      if kind then
        local color = C[Game.color_key(kind)]
        blit_screen(WELL_X + (x - 1) * BLOCK, WELL_Y + (y - 1) * BLOCK, "#", color, color)
      end
    end
  end

  -- 落点投影：只写字形、不铺底，于是压在井底却不遮住已堆好的方块
  if game.state == "falling" and game.piece then
    local ghost = game:ghost_y()
    for _, c in ipairs(game.piece.cells) do
      local bx, by = game.piece.x + c[1] - 1, ghost + c[2] - 1
      if by ~= game.piece.y + c[2] - 1 then
        blit_screen(WELL_X + (bx - 1) * BLOCK, WELL_Y + (by - 1) * BLOCK, "+", C.dark_gray)
      end
    end
  end

  -- 井下的两行：等级与行数（侧栏也有，但眼睛盯在井上时不必扭头）＋ 重开提示
  local foot = WELL_Y + Game.H * BLOCK + 1
  phos.screen.print(WELL_X - 1, foot,
                    string.format("%s %d   %s %d", L().level, game.level, L().lines, game.lines),
                    C.gray)
  phos.screen.print(WELL_X - 1, foot + 1,
                    L().restart:format(phos.input.key_name("select")), C.dark_gray)
end

-- piece 层：正在下落的方块（它不知道自己底下堆成什么样）
local function draw_piece()
  if game.state ~= "falling" or not game.piece then return end
  local C = phos.color
  local color = C[Game.color_key(game.piece.kind)]
  for _, c in ipairs(game.piece.cells) do
    -- 区域锚在井内区，所以局部坐标就是"棋盘坐标（0 起）× BLOCK"，不加密盘偏移
    blit_region(r_piece, (game.piece.x + c[1] - 2) * BLOCK,
                (game.piece.y + c[2] - 2) * BLOCK, "#", color, color)
  end
end

-- fx 层：消行闪光、硬降拖尾、加分浮字。**只写字形**，所以底下照样看得见
local function draw_fx()
  local C = phos.color
  if game.state == "clearing" then
    local blink = math.floor(game.clear_timer * 30) % 2 == 0
    for _, row in ipairs(game.clear_rows) do
      -- 一行方块占两条字符行，闪光就铺两条：只铺一条会看着像道夹缝
      for dy = 0, BLOCK - 1 do
        r_fx:print(WELL_X, WELL_Y + (row - 1) * BLOCK + dy,
                   string.rep(blink and "=" or "-", Game.W * BLOCK),
                   blink and C.white or C.cyan)
      end
    end
  end
  if trail then
    -- 拖尾记的是**绝对列号**：硬降之后方块已经换人，现算会画错列
    for y = trail.from, trail.to do
      for dy = 0, BLOCK - 1 do
        r_fx:print(trail.x, WELL_Y + (y - 1) * BLOCK + dy, string.rep("|", BLOCK), C.dark_gray)
      end
    end
  end
  for _, f in ipairs(floats) do
    r_fx:print(math.floor(f.x), math.floor(f.y), f.text, C.yellow)
  end
end

-- overlay 层：暂停与结束的浮窗。**底板要自己铺** —— `frame` 只画边框，不碰格内，
-- 只调它的结果是井里的方块从窗口里透出来，面板与游戏画面糊成一片。
-- 铺底板用 `clear`（恒写底色 → 整块不透明），于是这一块真的把世界挡住了
local function draw_overlay()
  local C = phos.color
  if paused then
    r_overlay:clear(C.gray, C.dark_gray)
    r_overlay:frame(L().paused)
    r_overlay:print(2, 3, string.format(L().score, game.score), C.white)
    r_overlay:print(2, 5, L().resume:format(phos.input.key_name("start")), C.cyan)
  elseif game.state == "gameover" then
    r_overlay:clear(C.gray, C.dark_gray)
    r_overlay:frame(L().over)
    r_overlay:print(2, 3, string.format(L().score, game.score), C.white)
    if game.score >= Scores.best() and game.score > 0 then
      r_overlay:print(2, 5, string.format(L().record, game.score), C.yellow)
    end
    r_overlay:print(2, 6, L().restart:format(phos.input.key_name("a")), C.cyan)
  end
end

function draw()
  draw_world()      -- 底层：照旧写 phos.screen
  draw_piece()      -- 层：下落中的方块
  draw_fx()         -- 层：特效（不透明处盖住，透明处透出）
  draw_overlay()    -- 层：浮窗（整块挡住）

  Panel.draw({
    score = game.score, best = math.max(Scores.best(), game.score),
    level = game.level, lines = game.lines, next_kind = game.next_kind,
  })
end

-- agent / 自测观察口：棋盘逐行、当前块与下一块、等级分数都报出来。
-- 棋盘用字符串数组（每行 W 个字符：`.` 空 / 字母 = 已落定的那块），
-- agent 想算"这块该放哪"不必去读画面反推
function debug_state()
  local rows = {}
  for y = 1, Game.H do
    local line = {}
    for x = 1, Game.W do line[x] = game.board[y][x] or "." end
    rows[y] = table.concat(line)
  end
  -- 当前块连**四个格子的方框坐标**一起报：旋转与踢墙都会挪方块，
  -- 只报 kind + x/y 的调用方还得自己推形状与朝向，推错了就白算
  local piece = nil
  if game.piece then
    local cells = {}
    for i, c in ipairs(game.piece.cells) do cells[i] = { c[1], c[2] } end
    piece = { kind = game.piece.kind, x = game.piece.x, y = game.piece.y,
              cells = cells, ghost_y = game:ghost_y() }
  end
  return {
    state = game.state,
    paused = paused and 1 or 0,
    score = game.score,
    best = math.max(Scores.best(), game.score),
    level = game.level,
    lines = game.lines,
    next_kind = game.next_kind,
    piece = piece,
    board = rows,
    layers = #phos.layer.order(),
  }
end

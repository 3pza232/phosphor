-- LIFE —— 康威生命游戏（卡带入口：装配模块 + 生命周期粘合）
--
-- 操作（键位与 keyboard 一一对应，见 phos.input.key_name）：
--   方向键   移动光标
--   A        切换光标处的细胞（画图）
--   B        在光标处盖上当前图案
--   Y        切换图案
--   X        单步一代（暂停时用）
--   Enter    运行 / 暂停
--   Shift    清空棋盘
--   Esc      主机暂停菜单（卡带看不到）

local Board = require("board")
local Patterns = require("patterns")
local Panel = require("panel")
local Music = require("music")

-- 界面文案：跟随机器的界面语言（新增语言只需加一列）
local Text = {zh = {zone = "第 7 区"}, en = {zone = "ZONE 7"}}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

-- 棋盘在内容区中的位置：留出边框与顶部标题
local OX, OY = 2, 3
local SOUP_DENSITY = 28     -- 初始随机汤密度（%）
local GENERATION_TIME = 0.12  -- 每代用时（秒），约 8 代/秒

local board
local cursor_x, cursor_y
local pattern_index
local running
local tick

local function stamp_at_cursor()
  local pattern = Patterns.get(pattern_index)
  if not pattern then return end
  board:stamp(pattern.rows, cursor_x, cursor_y)
end

function init()
  Patterns.load()
  board = Board.new(Board.W, Board.H)
  board:soup(SOUP_DENSITY)
  cursor_x, cursor_y = math.floor(Board.W / 2), math.floor(Board.H / 2)
  pattern_index = 1
  running = true
  tick = 0
  phos.audio.music(Music)  -- 缓慢环境音（主机在换卡/拔卡时会自动停）
end

function update(dt)
  -- 光标
  if phos.input.pressed("left") then cursor_x = (cursor_x - 1) % Board.W end
  if phos.input.pressed("right") then cursor_x = (cursor_x + 1) % Board.W end
  if phos.input.pressed("up") then cursor_y = (cursor_y - 1) % Board.H end
  if phos.input.pressed("down") then cursor_y = (cursor_y + 1) % Board.H end

  if phos.input.pressed("a") then
    board:poke(cursor_x, cursor_y)
    phos.audio.beep(660, 0.03, { wave = "square", volume = 0.18 })
  end
  if phos.input.pressed("b") then
    stamp_at_cursor()
    phos.audio.beep(330, 0.08, { wave = "triangle", volume = 0.22, sweep = 520 })
  end
  if phos.input.pressed("y") then
    pattern_index = pattern_index + 1
    if pattern_index > Patterns.count() then pattern_index = 1 end
    phos.audio.beep(520, 0.03, { wave = "square", volume = 0.16 })
  end
  if phos.input.pressed("select") then
    board:clear()
    phos.audio.beep(120, 0.12, { wave = "noise", volume = 0.2 })
  end
  if phos.input.pressed("start") then
    running = not running
    phos.audio.beep(running and 880 or 440, 0.06, { wave = "square", volume = 0.2 })
  end

  -- 单步：暂停时按 X 推进一代
  if phos.input.pressed("x") then
    running = false
    board:step()
    phos.audio.beep(740, 0.03, { wave = "square", volume = 0.16 })
  end

  if running then
    tick = tick + dt
    while tick >= GENERATION_TIME do
      tick = tick - GENERATION_TIME
      board:step()
    end
  else
    tick = 0
  end
end

function draw()
  local C, S = phos.color, phos.screen
  S.clear()

  -- 棋盘边框（与系统界面同套原语）
  phos.ui.frame(OX - 1, OY - 1, Board.W + 2, Board.H + 2, L().zone)

  for y = 0, Board.H - 1 do
    for x = 0, Board.W - 1 do
      local alive = board:get(x, y)
      if alive then
        S.put(OX + x, OY + y, "#", C.green)
      elseif x % 8 == 0 and y % 4 == 0 then
        S.put(OX + x, OY + y, ".", C.dark_gray)  -- 稀疏网格点，便于观察位移
      end
    end
  end

  -- 光标：暂停时高亮显示，运行中只在棋盘边缘给个指示
  local cx, cy = OX + cursor_x, OY + cursor_y
  if not running then
    local ch = board:get(cursor_x, cursor_y) and "#" or "+"
    S.put(cx, cy, ch, C.black, C.yellow)
  else
    S.put(OX + cursor_x, OY - 1, "v", C.yellow)
    S.put(OX - 2, cy, ">", C.yellow)
  end

  phos.ui.frame(OX - 1, OY + Board.H + 0, Board.W + 2, 4, "")
  S.print(OX + 1, OY + Board.H + 1,
          string.format("%s | GEN %d | POP %d | %s", running and "RUNNING" or "PAUSED",
                        board.generation, board.population, Patterns.label(Patterns.get(pattern_index))),
          running and C.green or C.orange)

  Panel.draw({
    generation = board.generation,
    population = board.population,
    running = running,
    pattern = Patterns.label(Patterns.get(pattern_index)),
    cursor_x = cursor_x,
    cursor_y = cursor_y,
  })
end

function debug_state()
  return {
    generation = board.generation,
    population = board.population,
    running = running,
    cursor_x = cursor_x,
    cursor_y = cursor_y,
    grid_w = Board.W,
    grid_h = Board.H,
    patterns = Patterns.count(),
    soup_density = SOUP_DENSITY,
    cell_0_0 = board:get(0, 0),
  }
end

-- game.lua —— 俄罗斯方块：棋盘与规则。只管状态怎么变，不碰画面。
--
-- 井是 10×20，坐标 (x, y)：x 从 1 起（左→右），y 从 1 起（**上→下**）——
-- 与屏幕同一个方向约定，于是"画一格"就是 put(x, y)，不必再翻一次。

local Game = {}

Game.W, Game.H = 10, 20

-- 消行闪光的时长（秒）。它同时是"行还在但已判定消掉"的那一小段
local CLEAR_TIME = 0.22
local GRAVITY_SCALE = 1.0  -- 下落速度的可调旋钮：>1 更快、<1 更慢（`~` 调试台）

-- 七种方块。每种给四个格子在 **4×4 方框**里的偏移，旋转就是整体转 90°
-- （(x,y) → (5-y, x)）：比每种朝向各写一张表省事，也不会写漏。
-- O 在方框里居中，因此旋转天然不变——这正是它该有的样子。
-- color 写的是 phos.color 里的名字，绘制时现取：主题换了颜色跟着换
local PIECES = {
  I = { color = "cyan",   cells = { { 1, 2 }, { 2, 2 }, { 3, 2 }, { 4, 2 } } },
  O = { color = "yellow", cells = { { 2, 2 }, { 3, 2 }, { 2, 3 }, { 3, 3 } } },
  T = { color = "purple", cells = { { 2, 2 }, { 1, 3 }, { 2, 3 }, { 3, 3 } } },
  S = { color = "green",  cells = { { 2, 2 }, { 3, 2 }, { 1, 3 }, { 2, 3 } } },
  Z = { color = "red",    cells = { { 1, 2 }, { 2, 2 }, { 2, 3 }, { 3, 3 } } },
  J = { color = "blue",   cells = { { 1, 2 }, { 1, 3 }, { 2, 3 }, { 3, 3 } } },
  L = { color = "orange", cells = { { 3, 2 }, { 1, 3 }, { 2, 3 }, { 3, 3 } } },
}

-- 消行得分：一次消 1~4 行。乘当前等级
local CLEAR_SCORE = { 0, 100, 300, 500, 800 }

function Game.color_key(kind) return PIECES[kind] and PIECES[kind].color or "white" end
function Game.cells(kind) return PIECES[kind] and PIECES[kind].cells or {} end

local function empty_row()
  local row = {}
  for x = 1, Game.W do row[x] = false end
  return row
end

function Game.new()
  local self = setmetatable({}, { __index = Game })
  self:restart()
  return self
end

function Game:restart()
  self.board = {}
  for y = 1, Game.H do self.board[y] = empty_row() end
  self.score, self.lines, self.level = 0, 0, 1
  self.state = "falling"          -- falling / clearing / gameover
  self.clear_rows, self.clear_timer = {}, 0
  self.drop_timer = 0
  self.soft = false               -- 按住"下"：重力加速（由入口每帧设置）
  self.bag = {}
  self.piece = nil
  self.next_kind = self:take()
  self:spawn()
end

-- 七袋随机：每七个一轮各来一次，避免"连着五个 S"那种气人的运气。
-- 洗牌走主机的随机源（phos.sys.random），所以同种子跑的两次完全一样
function Game:take()
  if #self.bag == 0 then
    local pool = { "I", "O", "T", "S", "Z", "J", "L" }
    for i = #pool, 2, -1 do
      local j = phos.sys.random(1, i)
      pool[i], pool[j] = pool[j], pool[i]
    end
    self.bag = pool
  end
  return table.remove(self.bag)
end

function Game:spawn()
  local kind = self.next_kind
  self.next_kind = self:take()
  local cells = {}
  for i, c in ipairs(PIECES[kind].cells) do cells[i] = { c[1], c[2] } end
  self.piece = { kind = kind, cells = cells, x = 4, y = 1 }
  if not self:fits(cells, self.piece.x, self.piece.y) then self.state = "gameover" end
end

function Game:fits(cells, ox, oy)
  for _, c in ipairs(cells) do
    local x, y = ox + c[1] - 1, oy + c[2] - 1
    if x < 1 or x > Game.W or y > Game.H then return false end
    if y >= 1 and self.board[y][x] then return false end
  end
  return true
end

function Game:move(dx)
  if self.state ~= "falling" then return false end
  if not self:fits(self.piece.cells, self.piece.x + dx, self.piece.y) then return false end
  self.piece.x = self.piece.x + dx
  return true
end

function Game:rotate(dir)
  if self.state ~= "falling" then return false end
  local spun = {}
  for i, c in ipairs(self.piece.cells) do
    -- 顺时针 (x,y) → (5-y, x)；逆时针 → (y, 5-x)。屏幕 y 向下，所以这两条才是"顺/逆"
    spun[i] = dir > 0 and { 5 - c[2], c[1] } or { c[2], 5 - c[1] }
  end
  -- 踢墙：原位试起，再左右各让一格、两格。够用且便宜——
  -- SRS 那张完整踢墙表对一台"一格一根摇杆"的机器太重了
  for _, dx in ipairs({ 0, -1, 1, -2, 2 }) do
    if self:fits(spun, self.piece.x + dx, self.piece.y) then
      self.piece.cells, self.piece.x = spun, self.piece.x + dx
      return true
    end
  end
  return false
end

function Game:step_down()
  if not self:fits(self.piece.cells, self.piece.x, self.piece.y + 1) then return false end
  self.piece.y = self.piece.y + 1
  return true
end

-- 落点投影：从当前位置一直落到不能再落。画出它，玩家才知道这一块会落在哪
function Game:ghost_y()
  if not self.piece then return 1 end
  local y = self.piece.y
  while self:fits(self.piece.cells, self.piece.x, y + 1) do y = y + 1 end
  return y
end

function Game:drop_interval()
  return math.max(0.05, (0.75 - (self.level - 1) * 0.06) / GRAVITY_SCALE)
end

-- 落定：写进棋盘、判定满行。返回消掉的行数
function Game:lock()
  for _, c in ipairs(self.piece.cells) do
    local x, y = self.piece.x + c[1] - 1, self.piece.y + c[2] - 1
    if x >= 1 and x <= Game.W and y >= 1 and y <= Game.H then
      self.board[y][x] = self.piece.kind
    end
  end
  self.piece = nil

  local full = {}
  for y = 1, Game.H do
    local filled = true
    for x = 1, Game.W do
      if not self.board[y][x] then filled = false break end
    end
    if filled then full[#full + 1] = y end
  end

  if #full > 0 then
    self.clear_rows, self.clear_timer, self.state = full, CLEAR_TIME, "clearing"
    return #full
  end
  self:spawn()
  return 0
end

function Game:finish_clear()
  local count = #self.clear_rows
  table.sort(self.clear_rows)
  for i = count, 1, -1 do table.remove(self.board, self.clear_rows[i]) end
  for _ = 1, count do table.insert(self.board, 1, empty_row()) end

  self.score = self.score + (CLEAR_SCORE[count] or 800) * self.level
  self.lines = self.lines + count
  local level = 1 + math.floor(self.lines / 10)
  local levelup = level > self.level
  self.level = level

  self.clear_rows = {}
  -- 先回到下落的常态，再 spawn：spawn 只有在出生点被占时才会把状态改成 gameover。
  -- 漏掉这一句的后果很具体——状态停在 clearing，于是每帧都再来一次"消行"，
  -- 每帧都换一块新方块，牌局当场散架
  self.state = "falling"
  self:spawn()
  return count, levelup
end

function Game:hard_drop()
  local dist = 0
  while self:step_down() do dist = dist + 1 end
  self.score = self.score + dist * 2   -- 硬降给分，鼓励快点下决定
  local cleared = self:lock()
  return dist, cleared
end

-- 每帧推进。返回本帧发生的事，入口拿它去播音效/记分
function Game:update(dt)
  local ev = {}
  if self.state == "clearing" then
    self.clear_timer = self.clear_timer - dt
    if self.clear_timer <= 0 then
      local cleared, levelup = self:finish_clear()
      ev.cleared, ev.levelup = cleared, levelup
      ev.gameover = (self.state == "gameover")
    end
    return ev
  end
  if self.state ~= "falling" then return ev end

  local interval = self:drop_interval()
  self.drop_timer = self.drop_timer + dt * (self.soft and 12 or 1)
  while self.drop_timer >= interval do
    self.drop_timer = self.drop_timer - interval
    if self:step_down() then
      ev.dropped = true
    else
      ev.cleared = self:lock()
      ev.locked = true
      ev.gameover = (self.state == "gameover")
      break
    end
  end
  return ev
end

-- 可调参数（`~` 调试台，见 phos.debug.number）
function Game.tunables()
  return {
    { name = { zh = "重力倍率", en = "Gravity scale" }, get = function() return GRAVITY_SCALE end,
      set = function(v) GRAVITY_SCALE = v end, min = 0.25, max = 4.0, step = 0.05 },
  }
end

return Game

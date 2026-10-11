-- board.lua —— 棋盘：康威生命游戏的规则与状态（不碰音频 / 存档 / 输入）
--
-- 环面拓扑（左右上下相连）：ASCII 棋盘上的图案不会撞墙死掉，
-- 滑翔机会绕回另一侧，长时间观察也不会退化成静止块。

local Board = {}
Board.__index = Board

Board.W, Board.H = 56, 38

function Board.new(w, h)
  local self = setmetatable({}, Board)
  self.w = w or Board.W
  self.h = h or Board.H
  self.cells = {}
  self.next = {}
  for i = 1, self.w * self.h do
    self.cells[i] = false
    self.next[i] = false
  end
  self.generation = 0
  self.population = 0
  return self
end

function Board:index(x, y)
  -- x/y 为 0 基局部坐标，自动环面折叠
  local wx = (x % self.w + self.w) % self.w
  local wy = (y % self.h + self.h) % self.h
  return wy * self.w + wx + 1
end

function Board:get(x, y) return self.cells[self:index(x, y)] end

function Board:set(x, y, alive) self.cells[self:index(x, y)] = alive and true or false end

function Board:poke(x, y)
  local alive = not self:get(x, y)
  self:set(x, y, alive)
  self:refresh()
  return alive
end

function Board:clear()
  for i = 1, self.w * self.h do self.cells[i] = false end
  self.generation = 0
  self.population = 0
end

function Board:refresh()
  local count = 0
  for i = 1, self.w * self.h do
    if self.cells[i] then count = count + 1 end
  end
  self.population = count
end

-- 随机汤：density 为 0..100 的存活百分比
function Board:soup(density)
  for i = 1, self.w * self.h do
    self.cells[i] = phos.sys.random(0, 99) < density
  end
  self.generation = 0
  self:refresh()
end

-- 把一串字符画图案贴到以 (cx, cy) 为中心的位置
function Board:stamp(rows, cx, cy)
  local h = #rows
  local w = 0
  for _, row in ipairs(rows) do
    if #row > w then w = #row end
  end
  local ox = cx - math.floor(w / 2)
  local oy = cy - math.floor(h / 2)
  for y = 1, h do
    local row = rows[y]
    for x = 1, #row do
      local ch = string.sub(row, x, x)
      if ch == "#" or ch == "O" then self:set(ox + x - 1, oy + y - 1, true) end
    end
  end
  self:refresh()
  return w, h
end

-- 推进一代（B3/S23）
function Board:step()
  local w, h = self.w, self.h
  local next_cells = self.next
  for y = 0, h - 1 do
    for x = 0, w - 1 do
      local n = 0
      if self:get(x - 1, y - 1) then n = n + 1 end
      if self:get(x, y - 1) then n = n + 1 end
      if self:get(x + 1, y - 1) then n = n + 1 end
      if self:get(x - 1, y) then n = n + 1 end
      if self:get(x + 1, y) then n = n + 1 end
      if self:get(x - 1, y + 1) then n = n + 1 end
      if self:get(x, y + 1) then n = n + 1 end
      if self:get(x + 1, y + 1) then n = n + 1 end

      local alive = self:get(x, y)
      local survives = alive and (n == 2 or n == 3) or (not alive and n == 3)
      next_cells[y * w + x + 1] = survives
    end
  end
  self.cells, self.next = self.next, self.cells
  self.generation = self.generation + 1
  self:refresh()
  return self.population
end

return Board

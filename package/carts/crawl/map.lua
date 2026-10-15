-- map.lua —— 单屏地牢的生成与查询（DESIGN §3）。
--
-- 只用一块 54×36 的网格（一屏画得下、无相机），负责：
--   房间投点 → 生成树连接（保证连通、无死路迷宫感）→ 门 / 柱子装饰 →
--   出生点 / 楼梯 / 随机地板查询。
--
-- **只产出"地块"**：怪物与物品的**内容**由 world.lua 通过 random_floor 放上去，
-- 这样地图模块换一套生成算法也不会牵动玩法。一切随机走传进来的 rng（同种子可复现）。

local Map = {}

Map.W, Map.H = 54, 36

-- 地形编号（§3.4）。用整数比较、字形留给绘制层查表。
Map.WALL, Map.FLOOR, Map.DOOR, Map.STAIR = 0, 1, 2, 3

local GLYPH = { [Map.WALL] = "#", [Map.FLOOR] = ".", [Map.DOOR] = "+", [Map.STAIR] = ">" }
function Map.glyph(t) return GLYPH[t] or " " end

local M = {}
M.__index = M

-- 房间矩形**含自身墙**：可走内部是 (x+1..x+w-2, y+1..y+h-2)。
-- 于是"房间不相接"只需保证两个外框外扩 1 后不相交，墙自然留在两房之间。
local function make_room(x, y, w, h)
  return {
    x = x, y = y, w = w, h = h,
    cx = x + math.floor(w / 2), cy = y + math.floor(h / 2),
  }
end

function Map.new(depth, rng)
  local m = setmetatable({}, M)
  m.depth = depth
  m.w, m.h = Map.W, Map.H
  m.tiles, m.explored = {}, {}
  for y = 0, m.h - 1 do
    local row, exp = {}, {}
    for x = 0, m.w - 1 do row[x], exp[x] = Map.WALL, false end
    m.tiles[y], m.explored[y] = row, exp
  end
  m.rooms = {}
  m.boss = nil
  m.spawn = { x = 0, y = 0 }
  m.stairs = { x = 0, y = 0 }
  m:_generate(depth, rng)
  return m
end

-- ---------- 生成 ----------

-- 两个矩形各自外扩 1 格后不相交 = 房间（含自身墙）之间至少留 1 格。
local function separated(x, y, w, h, r)
  return x >= r.x + r.w + 1 or x + w + 1 <= r.x
      or y >= r.y + r.h + 1 or y + h + 1 <= r.y
end

function M:_fits(x, y, w, h)
  -- Boss 房不进 self.rooms（出生房要另选），但仍要占位：普通房不能压在它上面，
  -- 否则会凿穿 13×11 的 Boss 房、把守望者房和出生房揉在一起。
  if self.boss and not separated(x, y, w, h, self.boss) then return false end
  for _, r in ipairs(self.rooms) do
    if not separated(x, y, w, h, r) then return false end
  end
  return true
end

function M:_carve_room(r)
  for y = r.y + 1, r.y + r.h - 2 do
    for x = r.x + 1, r.x + r.w - 2 do
      self.tiles[y][x] = Map.FLOOR
    end
  end
end

-- 柱子：25% 概率在房内撒 1~4 根单格柱（避开中心，留给出生/楼梯），让房间不是空盒子
function M:_pillars(r, rng)
  if not rng.chance(0.25) then return end
  for _ = 1, rng.int(1, 4) do
    local px = rng.int(r.x + 1, r.x + r.w - 2)
    local py = rng.int(r.y + 1, r.y + r.h - 2)
    if not (px == r.cx and py == r.cy) then
      self.tiles[py][px] = Map.WALL
    end
  end
end

function M:_floor(x, y)
  if x >= 0 and x < self.w and y >= 0 and y < self.h and self.tiles[y][x] == Map.WALL then
    self.tiles[y][x] = Map.FLOOR
  end
end

function M:_carve_h(x0, x1, y, widen)
  for x = math.min(x0, x1), math.max(x0, x1) do
    self:_floor(x, y)
    if widen then self:_floor(x, y + 1) end
  end
end

function M:_carve_v(y0, y1, x, widen)
  for y = math.min(y0, y1), math.max(y0, y1) do
    self:_floor(x, y)
    if widen then self:_floor(x + 1, y) end
  end
end

-- 生成树连接：第 i 个房间连到"已连通集合里离它最近的那个"，形成无环连通图。
-- 无环是关键——有环的走廊会变成迷宫，玩家要靠记忆乱撞；树状连接让"探索"线性可读。
function M:_connect(rng)
  local all = {}
  if self.boss then all[#all + 1] = self.boss end
  for _, r in ipairs(self.rooms) do all[#all + 1] = r end
  if #all == 0 then return end
  local tree = { 1 }
  for i = 2, #all do
    local ri = all[i]
    local best, bestd
    for _, j in ipairs(tree) do
      local rj = all[j]
      local dx, dy = ri.cx - rj.cx, ri.cy - rj.cy
      local d = dx * dx + dy * dy
      if not bestd or d < bestd then best, bestd = j, d end
    end
    local rj = all[best]
    local widen = rng.chance(0.08)          -- 8% 加宽为并排两格，增加视觉层次
    if rng.int(0, 1) == 1 then              -- L 形：横→纵 或 纵→横
      self:_carve_h(rj.cx, ri.cx, rj.cy, widen)
      self:_carve_v(rj.cy, ri.cy, ri.cx, widen)
    else
      self:_carve_v(rj.cy, ri.cy, rj.cx, widen)
      self:_carve_h(rj.cx, ri.cx, ri.cy, widen)
    end
    tree[#tree + 1] = i
  end
end

-- 门：走廊接入房间处（房间外框上被挖成地板的格）35% 概率标记为门。
-- 门仍可通行、不挡视线，纯外观/日志用（§3.4）。
function M:_doors(rng)
  for _, r in ipairs(self.rooms) do
    local ring = {}
    for x = r.x, r.x + r.w - 1 do
      ring[#ring + 1] = { x, r.y }
      ring[#ring + 1] = { x, r.y + r.h - 1 }
    end
    for y = r.y + 1, r.y + r.h - 2 do
      ring[#ring + 1] = { r.x, y }
      ring[#ring + 1] = { r.x + r.w - 1, y }
    end
    for _, c in ipairs(ring) do
      if self.tiles[c[2]][c[1]] == Map.FLOOR and rng.chance(0.35) then
        self.tiles[c[2]][c[1]] = Map.DOOR
      end
    end
  end
end

function M:_generate(depth, rng)
  local boss = (depth == 10)
  -- Boss 房**先放**（大 13×11），但不进 rooms：出生点要用"第 1 个普通房"，
  -- 让守望者房与出生房分开（否则会开局就跟 Boss 贴脸）
  if boss then
    local bw, bh = 13, 11
    local bx = rng.int(1, self.w - bw - 2)
    local by = rng.int(1, self.h - bh - 2)
    self.boss = make_room(bx, by, bw, bh)
    self:_carve_room(self.boss)
    self:_pillars(self.boss, rng)
  end

  local target = math.min(15, math.max(8, rng.int(8, 13) + math.floor(depth / 3)))
  local want_normal = boss and (target - 1) or target
  -- 每房最多 40 次投点（总上限自然 ≈ target×40 = 600）
  for _ = 1, want_normal do
    for _ = 1, 40 do
      local w = rng.int(5, 11)
      local h = rng.int(4, 9)
      local x = rng.int(1, self.w - w - 2)
      local y = rng.int(1, self.h - h - 2)
      if self:_fits(x, y, w, h) then
        local r = make_room(x, y, w, h)
        self.rooms[#self.rooms + 1] = r
        self:_carve_room(r)
        self:_pillars(r, rng)
        break
      end
    end
  end

  -- 一个普通房都没放下（极罕见）：硬塞一个小房，保证有出生点
  if #self.rooms == 0 then
    local r = make_room(2, 2, 7, 6)
    self.rooms[1] = r
    self:_carve_room(r)
  end

  self:_connect(rng)
  self:_doors(rng)
  self:_place_key(depth, rng)
end

function M:_place_key(depth, rng)
  local start = self.rooms[1]
  self.spawn = { x = start.cx, y = start.cy }
  -- 出生点绝不能落在柱子上
  self.tiles[self.spawn.y][self.spawn.x] = Map.FLOOR

  if depth == 10 and self.boss then
    -- 最深层：楼梯只作标记（已无路可下），放到 Boss 房内一端，中心留给守望者
    self.stairs = { x = math.min(self.boss.x + self.boss.w - 2, self.boss.cx + 3), y = self.boss.cy }
  else
    -- 离起点欧氏距离最远的房间中心
    local best, bestd
    for _, r in ipairs(self.rooms) do
      local dx, dy = r.cx - self.spawn.x, r.cy - self.spawn.y
      local d = dx * dx + dy * dy
      if not bestd or d > bestd then best, bestd = r, d end
    end
    self.stairs = { x = best.cx, y = best.cy }
  end
  self.tiles[self.stairs.y][self.stairs.x] = Map.STAIR
end

-- ---------- 查询 ----------

function M:in_bounds(x, y) return x >= 0 and y >= 0 and x < self.w and y < self.h end

function M:at(x, y)
  if self:in_bounds(x, y) then return self.tiles[y][x] end
  return Map.WALL
end

function M:walkable(x, y) return self:at(x, y) ~= Map.WALL end
function M:blocks_sight(x, y) return self:at(x, y) == Map.WALL end
function M:explored_at(x, y) return self:in_bounds(x, y) and self.explored[y][x] end

function M:reveal_all()
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do self.explored[y][x] = true end
  end
end

function M:explored_count()
  local n = 0
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do if self.explored[y][x] then n = n + 1 end end
  end
  return n
end

-- 随机取一块"房间内的地板"（生成树保证连通，所以可达）：
--   opts.occupied(x,y) 为真则跳过；opts.from + opts.min_dist 限制离某点的距离
function M:random_floor(rng, opts)
  opts = opts or {}
  local pool = self.rooms
  if #pool == 0 then return nil end
  local md2 = (opts.min_dist or 0) ^ 2
  for _ = 1, 240 do
    local r = pool[rng.int(1, #pool)]
    local x = rng.int(r.x + 1, r.x + r.w - 2)
    local y = rng.int(r.y + 1, r.y + r.h - 2)
    if self.tiles[y][x] == Map.FLOOR
       and not (opts.occupied and opts.occupied(x, y))
       and (not opts.from or ((x - opts.from.x) ^ 2 + (y - opts.from.y) ^ 2) > md2) then
      return x, y
    end
  end
  return nil
end

return Map

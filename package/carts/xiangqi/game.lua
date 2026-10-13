-- game.lua —— 中国象棋规则。不读键盘、不画东西、不发声音。
-- 棋盘 9 列（文件 f=0..8）× 10 行（r=0..9）。红方在下（r=9）先行，黑方在上（r=0）。
-- 走法、将军、将死的判定都收在这里；AI 也在这里（规则的一部分）。

local Game = {}
Game.__index = Game

local FW, FH = 9, 10
local RED, BLACK = "r", "b"
local VALUE = { K = 10000, R = 9, N = 4, C = 4.5, B = 2, A = 2, P = 1 }

local function in_board(f, r) return f >= 0 and f < FW and r >= 0 and r < FH end
local function foe(s) return s == RED and BLACK or RED end
local function in_palace(f, r, s)
  if f < 3 or f > 5 then return false end
  if s == BLACK then return r >= 0 and r <= 2 end
  return r >= 7 and r <= 9
end
local function crossed(r, s) return (s == RED and r <= 4) or (s == BLACK and r >= 5) end

function Game.new(rand)
  local self = setmetatable({}, Game)
  self.rand = rand or function() return 0.5 end
  self.player_side, self.ai_side = RED, BLACK
  self.turn = RED               -- 红先
  self.over, self.winner = false, nil
  self.sel = nil                -- 选中：{ f, r, moves }
  self.log = {}                 -- 棋谱（每步一条字符串）
  self.captured = { r = {}, b = {} }
  self.ai_timer = 0
  self.board = {}
  for r = 0, FH - 1 do
    self.board[r] = {}
  end
  local back = { "R", "N", "B", "A", "K", "A", "B", "N", "R" }
  for f = 0, 8 do
    self.board[0][f] = { t = back[f + 1], s = BLACK }
    self.board[9][f] = { t = back[f + 1], s = RED }
  end
  for _, f in ipairs({ 1, 7 }) do
    self.board[2][f] = { t = "C", s = BLACK }
    self.board[7][f] = { t = "C", s = RED }
  end
  for f = 0, 8, 2 do
    self.board[3][f] = { t = "P", s = BLACK }
    self.board[6][f] = { t = "P", s = RED }
  end
  return self
end

function Game:piece(f, r) return self.board[r] and self.board[r][f] or nil end

-- 某格棋子的**伪合法**走法（不检查走完是否被将军）；返回 { f, r } 目标列表
function Game:moves_at(f, r)
  local p = self:piece(f, r)
  local out = {}
  if not p then return out end
  local s = p.s
  local function free(tf, tr)
    if not in_board(tf, tr) then return false end
    local q = self:piece(tf, tr)
    return (not q) or q.s ~= s
  end

  if p.t == "K" then
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local tf, tr = f + d[1], r + d[2]
      if in_palace(tf, tr, s) and free(tf, tr) then out[#out + 1] = { f = tf, r = tr } end
    end
  elseif p.t == "A" then
    for _, d in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
      local tf, tr = f + d[1], r + d[2]
      if in_palace(tf, tr, s) and free(tf, tr) then out[#out + 1] = { f = tf, r = tr } end
    end
  elseif p.t == "B" then
    for _, d in ipairs({ { 2, 2 }, { 2, -2 }, { -2, 2 }, { -2, -2 } }) do
      local tf, tr = f + d[1], r + d[2]
      local stay = (s == RED and tr >= 5) or (s == BLACK and tr <= 4)   -- 象不过河
      if in_board(tf, tr) and stay and free(tf, tr) and not self:piece(f + d[1] / 2, r + d[2] / 2)
      then
        out[#out + 1] = { f = tf, r = tr }   -- 象眼必须空
      end
    end
  elseif p.t == "N" then
    local moves = {
      { 2, 1, 1, 0 }, { 2, -1, 1, 0 }, { -2, 1, -1, 0 }, { -2, -1, -1, 0 },
      { 1, 2, 0, 1 }, { -1, 2, 0, 1 }, { 1, -2, 0, -1 }, { -1, -2, 0, -1 },
    }
    for _, m in ipairs(moves) do
      if free(f + m[1], r + m[2]) and not self:piece(f + m[3], r + m[4]) then
        out[#out + 1] = { f = f + m[1], r = r + m[2] }   -- 马腿必须空
      end
    end
  elseif p.t == "R" or p.t == "C" then
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local tf, tr = f + d[1], r + d[2]
      local jumped = false
      while in_board(tf, tr) do
        local q = self:piece(tf, tr)
        if p.t == "R" then
          if not q then
            out[#out + 1] = { f = tf, r = tr }
          else
            if q.s ~= s then out[#out + 1] = { f = tf, r = tr } end
            break
          end
        else -- 炮：隔一子打
          if not jumped then
            if not q then out[#out + 1] = { f = tf, r = tr } else jumped = true end
          elseif q then
            if q.s ~= s then out[#out + 1] = { f = tf, r = tr } end
            break
          end
        end
        tf, tr = tf + d[1], tr + d[2]
      end
    end
  elseif p.t == "P" then
    local fwd = (s == RED) and -1 or 1
    if free(f, r + fwd) then out[#out + 1] = { f = f, r = r + fwd } end
    if crossed(r, s) then
      if free(f - 1, r) then out[#out + 1] = { f = f - 1, r = r } end
      if free(f + 1, r) then out[#out + 1] = { f = f + 1, r = r } end
    end
  end
  return out
end

function Game:find_king(s)
  for r = 0, FH - 1 do
    for f = 0, FW - 1 do
      local p = self.board[r][f]
      if p and p.t == "K" and p.s == s then return f, r end
    end
  end
  return nil
end

-- 某方是否被将军（含"将帅照面"）
function Game:in_check(s)
  local kf, kr = self:find_king(s)
  if not kf then return true end   -- 将已被吃：视为被将（不该发生，兜底）
  for r = 0, FH - 1 do
    for f = 0, FW - 1 do
      local p = self.board[r][f]
      if p and p.s == foe(s) then
        for _, m in ipairs(self:moves_at(f, r)) do
          if m.f == kf and m.r == kr then return true end
        end
      end
    end
  end
  -- 照面：两将同列、中间无子
  local ekf, ekr = self:find_king(foe(s))
  if ekf and ekf == kf then
    local clear = true
    for rr = math.min(kr, ekr) + 1, math.max(kr, ekr) - 1 do
      if self:piece(kf, rr) then clear = false break end
    end
    if clear then return true end
  end
  return false
end

-- 某格棋子的**合法**走法（走完不能留己方被将军）
function Game:legal_at(f, r)
  local p = self:piece(f, r)
  local out = {}
  if not p then return out end
  for _, m in ipairs(self:moves_at(f, r)) do
    local cap = self:piece(m.f, m.r)
    self.board[m.r][m.f] = p
    self.board[r][f] = nil
    if not self:in_check(p.s) then out[#out + 1] = m end
    self.board[r][f] = p
    self.board[m.r][m.f] = cap
  end
  return out
end

function Game:all_legal(s)
  local out = {}
  for r = 0, FH - 1 do
    for f = 0, FW - 1 do
      local p = self.board[r][f]
      if p and p.s == s then
        for _, m in ipairs(self:legal_at(f, r)) do
          out[#out + 1] = { f = f, r = r, tf = m.f, tr = m.r }
        end
      end
    end
  end
  return out
end

local NAMES = { r = { R = "車", N = "馬", B = "相", A = "仕", K = "帥", C = "炮", P = "兵" },
                b = { R = "車", N = "馬", B = "象", A = "士", K = "將", C = "砲", P = "卒" } }
local FILE_CN = { "1", "2", "3", "4", "5", "6", "7", "8", "9" }

function Game:name_of(p) return NAMES[p.s][p.t] end

function Game:do_move(f, r, tf, tr)
  local p = self:piece(f, r)
  local cap = self:piece(tf, tr)
  self.board[tr][tf] = p
  self.board[r][f] = nil
  if cap then self.captured[cap.s][#self.captured[cap.s] + 1] = cap end
  local who = (p.s == RED) and "紅" or "黑"
  self.log[#self.log + 1] = string.format("%s %s %d,%d-%d,%d", who, NAMES[p.s][p.t],
                                          f + 1, r + 1, tf + 1, tr + 1)
  self.last = { f = f, r = r, tf = tf, tr = tr }
  self.sel = nil
  self.turn = foe(self.turn)
  if self.turn == self.ai_side then self.ai_timer = 0.6 end
  if #self:all_legal(self.turn) == 0 then
    self.over, self.winner = true, foe(self.turn)   -- 无子可走即负（将死或困毙）
  end
  return cap
end

-- 玩家点选：选中 / 落子 / 换选 / 取消
function Game:choose(f, r)
  if self.over or self.turn ~= self.player_side then return "none" end
  if self.sel then
    for _, m in ipairs(self.sel.moves) do
      if m.f == f and m.r == r then
        self:do_move(self.sel.f, self.sel.r, f, r)
        return "moved"
      end
    end
    local p = self:piece(f, r)
    if p and p.s == self.player_side then
      self.sel = { f = f, r = r, moves = self:legal_at(f, r) }
      return "selected"
    end
    self.sel = nil
    return "cancel"
  end
  local p = self:piece(f, r)
  if p and p.s == self.player_side then
    self.sel = { f = f, r = r, moves = self:legal_at(f, r) }
    return "selected"
  end
  return "none"
end

function Game:cancel()
  self.sel = nil
end

-- 目标格是否被 by 方任意棋子威胁（AI 估险用；只看一步几何，不做深算）
function Game:attacked(f, r, by)
  for rr = 0, FH - 1 do
    for ff = 0, FW - 1 do
      local p = self.board[rr][ff]
      if p and p.s == by then
        for _, m in ipairs(self:moves_at(ff, rr)) do
          if m.f == f and m.r == r then return true end
        end
      end
    end
  end
  return false
end

-- 简单 AI：一步贪心——吃子得分、被打回扣、轻微随机。够下"陪练"级。
function Game:pick_ai_move()
  local s = self.ai_side
  local best, best_score = nil, -math.huge
  for _, mv in ipairs(self:all_legal(s)) do
    local p = self:piece(mv.f, mv.r)
    local cap = self:piece(mv.tf, mv.tr)
    local gain = cap and VALUE[cap.t] or 0
    -- 试探：走完后这枚子是否落在对方火力下
    self.board[mv.tr][mv.tf] = p
    self.board[mv.r][mv.f] = nil
    local risk = self:attacked(mv.tf, mv.tr, self.player_side) and VALUE[p.t] * 0.85 or 0
    self.board[mv.r][mv.f] = p
    self.board[mv.tr][mv.tf] = cap
    local score = gain - risk + self.rand() * 0.3
    if score > best_score then best_score, best = score, mv end
  end
  return best
end

function Game:update(dt)
  local events = {}
  if self.over then return events end
  if self.turn == self.ai_side then
    self.ai_timer = self.ai_timer - dt
    if self.ai_timer <= 0 then
      local mv = self:pick_ai_move()
      if mv then
        self:do_move(mv.f, mv.r, mv.tf, mv.tr)
        events.ai_moved = true
      end
    end
  end
  return events
end

function Game:status()
  return {
    turn = self.turn, over = self.over, winner = self.winner,
    in_check = (not self.over) and self:in_check(self.turn) or false,
    moves = #self.log, sel = self.sel and (self.sel.f .. "," .. self.sel.r) or "",
  }
end

return Game

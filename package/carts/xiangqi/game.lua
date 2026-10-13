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

function Game.new(rand, now)
  local self = setmetatable({}, Game)
  self.rand = rand or function() return 0.5 end
  self.now = now                       -- 计时函数（测 AI 思考耗时；缺省不用）
  self.nodes = 0
  self.think_ms = 0
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

local DIRS4 = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }
local DIRS4D = { { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }
local KNIGHT = { { 1, 2 }, { 2, 1 }, { -1, 2 }, { -2, 1 }, { 1, -2 }, { 2, -1 }, { -1, -2 }, { -2, -1 } }

function Game:king_pos(s) return self:find_king(s) end   -- 供调试

-- 被将军判定：从将/帅向外**射线**看，不枚举敌方所有走法——搜索里每步都要调，必须够快
function Game:in_check(s)
  local kf, kr = self:find_king(s)
  if not kf then return true end
  local e = foe(s)
  local function at(f, r)
    if f < 0 or f >= FW or r < 0 or r >= FH then return nil end
    return self.board[r][f]
  end
  -- 车 / 炮 / 将：四方向射线
  for _, d in ipairs(DIRS4) do
    local x, y, screen = kf + d[1], kr + d[2], false
    while x >= 0 and x < FW and y >= 0 and y < FH do
      local p = self.board[y][x]
      if p then
        if not screen then
          if p.s == e and p.t == "R" then return true end
          if p.s == e and p.t == "K" then
            if math.abs(x - kf) + math.abs(y - kr) == 1 then return true end  -- 贴脸
            if d[1] == 0 then return true end                                -- 同列将帅照面
          end
          screen = true
        else
          if p.s == e and p.t == "C" then return true end
          break
        end
      end
      x, y = x + d[1], y + d[2]
    end
  end
  -- 马（查马腿）
  for _, m in ipairs(KNIGHT) do
    local p = at(kf + m[1], kr + m[2])
    if p and p.s == e and p.t == "N" then
      local legf = kf + (math.abs(m[1]) == 2 and m[1] / 2 or m[1])
      local legr = kr + (math.abs(m[2]) == 2 and m[2] / 2 or m[2])
      if not at(legf, legr) then return true end
    end
  end
  -- 兵/卒：正面一步；过河后可侧向
  local fp = at(kf, kr + (e == RED and 1 or -1))
  if fp and fp.s == e and fp.t == "P" then return true end
  if crossed(kr, e) then
    for _, dx in ipairs({ -1, 1 }) do
      local sp = at(kf + dx, kr)
      if sp and sp.s == e and sp.t == "P" then return true end
    end
  end
  -- 士（相邻斜）
  for _, d in ipairs(DIRS4D) do
    local p = at(kf + d[1], kr + d[2])
    if p and p.s == e and p.t == "A" then return true end
  end
  -- 相（两格斜 + 象眼）
  for _, d in ipairs({ { 2, 2 }, { 2, -2 }, { -2, 2 }, { -2, -2 } }) do
    local p = at(kf + d[1], kr + d[2])
    if p and p.s == e and p.t == "B" and not at(kf + d[1] / 2, kr + d[2] / 2) then return true end
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

-- 目标格是否被 by 方任意棋子威胁（简单攻击判定，供走子排序/评估用）
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

-- ── AI：alpha-beta 搜索 ──────────────────────────────────────────────
-- 候选搜索深度与节点上限：节点上限夹住单帧耗时（主机的看门狗是 100ms/调用）
local AI_DEPTH = 3
local NODE_BUDGET = 3000

-- 局面评估（黑方视角，AI 执黑）：子力 + 少量位置奖励
local function evaluate(self)
  local score = 0
  for r = 0, FH - 1 do
    for f = 0, FW - 1 do
      local p = self.board[r][f]
      if p then
        local v = VALUE[p.t]
        if p.t == "P" and crossed(r, p.s) then v = v + 0.8 end          -- 兵过河
        if (p.t == "N" or p.t == "C") then v = v + (4 - math.abs(f - 4)) * 0.08 end
        score = score + (p.s == BLACK and v or -v)
      end
    end
  end
  return score
end

local search      -- 前置声明（递归）

-- 某方的**伪合法**走法（不查走完是否被将）。搜索用它换取速度：将没了即判被将死，
-- 于是"送将"的走法会被下一步"吃将"的巨大分值排除——只在根节点做严格合法性过滤。
local function pseudo_moves(self, side)
  local out = {}
  for r = 0, FH - 1 do
    for f = 0, FW - 1 do
      local p = self.board[r][f]
      if p and p.s == side then
        for _, m in ipairs(self:moves_at(f, r)) do
          out[#out + 1] = { f = f, r = r, tf = m.f, tr = m.r }
        end
      end
    end
  end
  return out
end

local MATED = 90000

local function order(self, moves)
  table.sort(moves, function(a, b)
    local ca, cb = self:piece(a.tf, a.tr), self:piece(b.tf, b.tr)
    return (ca and VALUE[ca.t] or 0) > (cb and VALUE[cb.t] or 0)
  end)
end

search = function(self, depth, alpha, beta)
  self.nodes = self.nodes + 1
  if depth <= 0 or self.nodes > NODE_BUDGET then return evaluate(self) end

  local moves = pseudo_moves(self, self.turn)
  order(self, moves)
  local black = self.turn == BLACK
  local best = black and -math.huge or math.huge
  for _, mv in ipairs(moves) do
    local p, cap = self:piece(mv.f, mv.r), self:piece(mv.tf, mv.tr)
    local sc
    if cap and cap.t == "K" then
      sc = black and (MATED + depth) or (-MATED - depth)   -- 吃到将：这一方胜（对方上一步漏了将）
    else
      self.board[mv.tr][mv.tf] = p
      self.board[mv.r][mv.f] = nil
      self.turn = foe(self.turn)
      sc = search(self, depth - 1, alpha, beta)
      self.turn = foe(self.turn)
      self.board[mv.r][mv.f] = p
      self.board[mv.tr][mv.tf] = cap
    end
    if black then
      if sc > best then best = sc end
      if best > alpha then alpha = best end
    else
      if sc < best then best = sc end
      if best < beta then beta = best end
    end
    if beta <= alpha then break end
    if self.nodes > NODE_BUDGET then break end
  end
  return best
end

function Game:pick_ai_move()
  local t0 = self.now and self.now() or 0
  self.nodes = 0
  local legal = self:all_legal(self.ai_side)   -- 根节点用**严格合法**走法（返回的走法必然合法）
  order(self, legal)
  local best, best_score = nil, -math.huge
  for _, mv in ipairs(legal) do
    local p, cap = self:piece(mv.f, mv.r), self:piece(mv.tf, mv.tr)
    self.board[mv.tr][mv.tf] = p
    self.board[mv.r][mv.f] = nil
    self.turn = foe(self.turn)
    self.nodes = self.nodes + 1
    local sc = search(self, AI_DEPTH, -math.huge, math.huge) + self.rand() * 0.2
    self.turn = foe(self.turn)
    self.board[mv.r][mv.f] = p
    self.board[mv.tr][mv.tf] = cap
    if sc > best_score then best_score, best = sc, mv end
    if self.nodes > NODE_BUDGET then break end
  end
  self.think_ms = math.floor(((self.now and self.now() or 0) - t0) * 1000)
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
    think_ms = self.think_ms, nodes = self.nodes,
  }
end

return Game

-- game.lua —— 中国象棋规则。不读键盘、不画东西、不发声音。
-- 棋盘 9 列（文件 f=0..8）× 10 行（r=0..9）。红方在下（r=9）先行，黑方在上（r=0）。
-- 走法、将军、将死的判定都收在这里；选哪一步（搜素）在 ai.lua。

local AI = require("ai")

local Game = {}
Game.__index = Game

local FW, FH = 9, 10
local RED, BLACK = "r", "b"

local function in_board(f, r) return f >= 0 and f < FW and r >= 0 and r < FH end
local function foe(s) return s == RED and BLACK or RED end
local function in_palace(f, r, s)
  if f < 3 or f > 5 then return false end
  if s == BLACK then return r >= 0 and r <= 2 end
  return r >= 7 and r <= 9
end
local function crossed(r, s) return (s == RED and r <= 4) or (s == BLACK and r >= 5) end

function Game.new(rand, now, player_side, level)
  local self = setmetatable({}, Game)
  self.rand = rand or function() return 0.5 end
  self.now = now                       -- 计时函数（测 AI 思考耗时；缺省不用）
  self.nodes = 0
  self.think_ms = 0
  self.player_side = player_side or RED
  self.ai_side = foe(self.player_side)
  self.turn = RED               -- 红先（玩家执黑时电脑先走）
  self.level = math.max(1, math.min(3, level or 2))
  local lv = AI.level(self.level)
  self.ai_depth, self.ai_budget = lv.depth, lv.budget
  self.ai_noise, self.ai_delay = lv.noise, lv.delay
  self.over, self.winner = false, nil
  self.sel = nil                -- 选中：{ f, r, moves }
  self.log = {}                 -- 棋谱（每步一条字符串）
  self.captured = { r = {}, b = {} }
  self.history = {}             -- 每步前的快照，供悔棋
  self.ai_timer = (self.turn == self.ai_side) and self.ai_delay or 0
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
function Game:name_of(p) return NAMES[p.s][p.t] end

local function copy_board(src)
  local out = {}
  for r = 0, FH - 1 do
    out[r] = {}
    for f = 0, FW - 1 do
      local p = src[r][f]
      if p then out[r][f] = { t = p.t, s = p.s } end
    end
  end
  return out
end

function Game:snapshot()
  return { board = copy_board(self.board), turn = self.turn,
           log = #self.log, capb = #self.captured.b, capr = #self.captured.r }
end

function Game:do_move(f, r, tf, tr)
  self.history[#self.history + 1] = self:snapshot()
  local p = self:piece(f, r)
  local cap = self:piece(tf, tr)
  self.board[tr][tf] = p
  self.board[r][f] = nil
  if cap then self.captured[cap.s][#self.captured[cap.s] + 1] = cap end
  -- 棋谱存**结构化**的一步（谁 / 什么子 / 从哪到哪），文案在面板里按界面语言拼——
  -- 规则层不写死"红/黑"这类界面字样
  self.log[#self.log + 1] = { s = p.s, t = p.t, f = f, r = r, tf = tf, tr = tr }
  self.last = { f = f, r = r, tf = tf, tr = tr }
  self.sel = nil
  self.turn = foe(self.turn)
  if self.turn == self.ai_side then self.ai_timer = self.ai_delay end
  if #self:all_legal(self.turn) == 0 then
    self.over, self.winner = true, foe(self.turn)   -- 无子可走即负（将死或困毙）
  end
  return cap
end

-- 悔棋：回退到"玩家该走"的那一步（一般一次退两步：自己的 + 电脑的应手）
function Game:can_undo() return #self.history > 0 end

function Game:undo()
  if not self:can_undo() then return false end
  local s
  repeat
    s = table.remove(self.history)
    if not s then break end
    self.board = s.board
    self.turn = s.turn
    for i = #self.log, s.log + 1, -1 do self.log[i] = nil end
    for i = #self.captured.b, s.capb + 1, -1 do self.captured.b[i] = nil end
    for i = #self.captured.r, s.capr + 1, -1 do self.captured.r[i] = nil end
    self.over, self.winner, self.sel = false, nil, nil
  until self.turn == self.player_side or #self.history == 0
  self.ai_timer = 0
  return true
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

function Game:update(dt)
  local events = {}
  if self.over then return events end
  if self.turn == self.ai_side then
    self.ai_timer = self.ai_timer - dt
    if self.ai_timer <= 0 then
      local mv = AI.pick(self)
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
    player_side = self.player_side, level = self.level,
    in_check = (not self.over) and self:in_check(self.turn) or false,
    moves = #self.log, sel = self.sel and (self.sel.f .. "," .. self.sel.r) or "",
    can_undo = self:can_undo(), think_ms = self.think_ms, nodes = self.nodes,
  }
end

return Game

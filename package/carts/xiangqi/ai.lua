-- ai.lua —— 电脑走子：alpha-beta 搜索。规则在 game.lua，这里只负责"选哪一步"。
-- 只读 / 临时改写传入的棋局（搜索用 make/unmake，走完复原）；不读键盘、不画东西、不发声音。
--
-- 为什么单独成文件：搜索是"想清楚才写"的一块（评估、剪枝、走子排序、等级参数），
-- 混在规则里以后谁都说不清"为什么它走这一步"。与 worms 的 ai.lua 是同一个拆分理由。

local AI = {}

-- 等级：深度 / 节点上限 / 随机扰动 / 思考时长。节点上限夹住单帧耗时（看门狗 100ms/调用）
AI.LEVELS = {
  { depth = 2, budget = 700, noise = 1.6, delay = 0.35 },
  { depth = 3, budget = 1500, noise = 0.35, delay = 0.75 },
  { depth = 4, budget = 2200, noise = 0.06, delay = 1.4 },
}
function AI.level(n) return AI.LEVELS[math.max(1, math.min(3, n or 2))] end

local FH, FW = 10, 9
local BLACK = "b"
local VALUE = { K = 10000, R = 9, N = 4.5, C = 4.5, B = 2, A = 2, P = 1 }
local MATED = 90000

local function foe(s) return s == "r" and "b" or "r" end
local function crossed(r, s) return (s == "r" and r <= 4) or (s == "b" and r >= 5) end

-- 局面评估（黑方视角）：子力 + 少量位置奖励
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

-- 走子排序：吃子优先（被吃子价值降序）。明显的剪枝加速项。
local function order(self, moves)
  table.sort(moves, function(a, b)
    local ca, cb = self:piece(a.tf, a.tr), self:piece(b.tf, b.tr)
    return (ca and VALUE[ca.t] or 0) > (cb and VALUE[cb.t] or 0)
  end)
end

local search  -- 前置声明（递归）

search = function(self, depth, alpha, beta)
  self.nodes = self.nodes + 1
  if depth <= 0 or self.nodes > self.ai_budget then return evaluate(self) end

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
    if self.nodes > self.ai_budget then break end
  end
  return best
end

-- 选一步。根节点用**严格合法**走法（返回的走法必然合法）；评分黑方视角，AI 执黑取最大、执红取最小。
function AI.pick(self)
  local t0 = self.now and self.now() or 0
  self.nodes = 0
  local legal = self:all_legal(self.ai_side)
  order(self, legal)
  local maximize = (self.ai_side == BLACK)
  local best, best_score = nil, maximize and -math.huge or math.huge
  for _, mv in ipairs(legal) do
    local p, cap = self:piece(mv.f, mv.r), self:piece(mv.tf, mv.tr)
    self.board[mv.tr][mv.tf] = p
    self.board[mv.r][mv.f] = nil
    self.turn = foe(self.turn)
    self.nodes = self.nodes + 1
    local sc = search(self, self.ai_depth, -math.huge, math.huge)
    sc = sc + (self.rand() - 0.5) * self.ai_noise   -- 等级越低扰动越大（会犯错）
    self.turn = foe(self.turn)
    self.board[mv.r][mv.f] = p
    self.board[mv.tr][mv.tf] = cap
    if maximize and sc > best_score then best_score, best = sc, mv end
    if (not maximize) and sc < best_score then best_score, best = sc, mv end
    if self.nodes > self.ai_budget then break end
  end
  self.think_ms = math.floor(((self.now and self.now() or 0) - t0) * 1000)
  return best
end

return AI

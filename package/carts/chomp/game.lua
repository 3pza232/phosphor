-- game.lua —— 迷宫贪吃鬼的规则（不碰输入、绘制、音频与存档）
--
-- 迷宫本体在 maze.lua（左半边数据，这里镜像成整幅）。玩法之外的一切——
-- 读键盘、画画面、发什么音、怎么存档——都由 main.lua 决定；这里只报"发生了什么"。

local Maze = require("maze")

local W = #Maze.half[1] * 2 - 1     -- 61 列（奇数：中线只有一条）
local H = #Maze.half                -- 37 行
local TUNNEL_ROW = Maze.tunnel_row  -- 两端开口的那一行

-- 四只幽灵各有脾气：追踪 / 包抄 / 迂回 / 怯阵。它们从中央隧道行出发
local CENTER = (W + 1) // 2
local GHOSTS = {
  { name = "blinky", color = "red",     kind = "chase",  dc = 0,  dr = -1 },
  { name = "pinky",  color = "magenta", kind = "ambush", dc = -3, dr = -1 },
  { name = "inky",   color = "cyan",    kind = "flank",  dc = 3,  dr = -1 },
  { name = "clyde",  color = "orange",  kind = "shy",    dc = 6,  dr = -1 },
}

local STEP = 0.10             -- 玩家每走一格用时（秒）
local GHOST_STEP = 0.128
local FRIGHT_STEP = 0.19
local FRIGHT_TIME = 7.0
local SCATTER_TIME = 5.0
local CHASE_TIME = 16.0
local READY_TIME = 1.8
local DYING_TIME = 1.5
local CLEAR_TIME = 2.2
local FRUIT_TIME = 9.0
local FRUIT_LINE = 120        -- 吃掉这么多豆子后，中央长出水果
local FRUIT_CELL = { c = CENTER, r = (H + 1) // 2 }

local Game = {}
Game.__index = Game
Game.W, Game.H = W, H
Game.TUNNEL_ROW = TUNNEL_ROW
Game.FRUIT_CELL = FRUIT_CELL

-- 镜像成整幅：半边 + 去掉中线后的反向半边
local function build_rows()
  local rows = {}
  for i, half in ipairs(Maze.half) do
    rows[i] = half .. half:sub(1, #half - 1):reverse()
  end
  return rows
end

local WALLS = build_rows()

local function wrap_col(col)
  return (col - 1) % W + 1
end

function Game.new()
  local self = setmetatable({}, Game)
  self.best = 0

  -- 水果落点：从迷宫正中向外找最近的可走格。写死"正中"是不行的——迷宫是
  -- 数据驱动的，形状一改正中就可能是墙，水果会长在墙里，永远吃不到。
  local scan = {}
  for radius = 0, 6 do
    for dr = -radius, radius do
      for dc = -radius, radius do
        if not self:is_wall(FRUIT_CELL.r + dr, FRUIT_CELL.c + dc) then
          scan = { c = FRUIT_CELL.c + dc, r = FRUIT_CELL.r + dr }
          break
        end
      end
      if scan.c then break end
    end
    if scan.c then break end
  end
  if scan.c then FRUIT_CELL = scan end

  self:reset_run()
  return self
end

-- 一局新游戏：分数归零、三条命、从第一关开始
function Game:reset_run()
  self.score = 0
  self.lives = 3
  self.level = 1
  self:start_level()
end

-- 一层新迷宫：豆子复位，双方回到出生点
function Game:start_level()
  self.grid = {}
  self.dots_left = 0
  for r = 1, H do
    local row = {}
    for c = 1, W do
      local ch = WALLS[r]:sub(c, c)
      row[c] = (ch == "." or ch == "o") and ch or ""
      if row[c] ~= "" then self.dots_left = self.dots_left + 1 end
    end
    self.grid[r] = row
  end

  self.eaten = 0
  self.next_fruit = FRUIT_LINE     -- 下一个水果的门槛：吃过一次往后顺延一批
  self.ghost_combo = 0
  self.fruit, self.fruit_timer = nil, 0
  self.mode, self.mode_timer = "scatter", SCATTER_TIME
  self.fright_timer = 0

  self:place_actors()
  self.state, self.state_timer = "ready", READY_TIME
end

function Game:place_actors()
  self.move_acc, self.ghost_acc = 0, 0
  self.player = {
    c = Maze.start.c, r = Maze.start.r, dc = -1, dr = 0,
    want_c = -1, want_r = 0, chomp = 0, alive = true,
  }
  self.ghosts = {}
  for _, spec in ipairs(GHOSTS) do
    self.ghosts[#self.ghosts + 1] = {
      name = spec.name, color = spec.color, kind = spec.kind,
      c = wrap_col(CENTER + spec.dc), r = TUNNEL_ROW, dc = 0, dr = spec.dr,
      home = { wrap_col(CENTER + spec.dc), TUNNEL_ROW }, eaten = false, respawn = 0,
    }
  end
end

function Game:is_wall(r, c)
  if r < 1 or r > H then return true end
  return WALLS[r]:sub(wrap_col(c), wrap_col(c)) == "#"
end

-- 转向意图：main.lua 读到方向键后调用。合法与否由规则判定；
-- 不合法就先记着——经典手感是"提前按键会在下一个路口生效"
function Game:turn(dc, dr)
  if not self.player.alive then return end
  self.player.want_c, self.player.want_r = dc, dr
end

-- 走一格：先兑现转向，再前进；前方是墙就停在原地
function Game:advance_player()
  local p = self.player
  if p.want_c ~= p.dc or p.want_r ~= p.dr then
    if not self:is_wall(p.r + p.want_r, p.c + p.want_c) then
      p.dc, p.dr = p.want_c, p.want_r
    end
  end
  if self:is_wall(p.r + p.dr, p.c + p.dc) then return false end

  p.c, p.r = wrap_col(p.c + p.dc), p.r + p.dr
  p.chomp = (p.chomp + 1) % 4
  return true
end

-- 幽灵的目标格：按脾气算（追踪贴人、包抄堵前、迂回绕侧、怯阵回避）
function Game:ghost_target(g)
  local p = self.player
  if self.fright_timer > 0 then return nil end   -- 惊吓态：随机乱窜

  if self.mode ~= "chase" then
    -- 散开：各回各的角落
    local corners = { { 2, 2 }, { W - 1, 2 }, { 2, H - 1 }, { W - 1, H - 1 } }
    local index = 1
    for i, spec in ipairs(GHOSTS) do
      if spec.name == g.name then index = i end
    end
    return corners[index]
  end

  if g.kind == "ambush" then return { p.c + p.dc * 4, p.r + p.dr * 4 } end
  if g.kind == "flank" then return { p.c - p.dc * 4, p.r - p.dr * 4 } end
  if g.kind == "shy" then
    -- 太近就躲远：去离玩家最远的那个角
    return { (p.c < W / 2) and W - 1 or 2, (p.r < H / 2) and H - 1 or 2 }
  end
  return { p.c, p.r }                            -- 追踪：直接贴上去
end

local DIRS = { { 0, -1 }, { -1, 0 }, { 0, 1 }, { 1, 0 } }

-- 某格有几个出口：用来认出死角（只有一条通路）。幽灵禁止掉头，一旦走进死角，
-- 唯一的出路恰好是掉头——于是它们会集体停在角落里不动。所以死角不进。
function Game:exits(r, c)
  local count = 0
  for _, dir in ipairs(DIRS) do
    if not self:is_wall(r + dir[2], c + dir[1]) then count = count + 1 end
  end
  return count
end

function Game:advance_ghost(g)
  if g.eaten then
    g.respawn = g.respawn - 1
    if g.respawn <= 0 then
      g.eaten = false
      g.c, g.r = g.home[1], g.home[2]
      g.dc, g.dr = 0, -1
    end
    return
  end

  local target = self:ghost_target(g)
  local best, best_score, reverse_dir = nil, nil, nil
  for _, dir in ipairs(DIRS) do
    local dc, dr = dir[1], dir[2]
    if not self:is_wall(g.r + dr, g.c + dc) then
      local is_reverse = (dc == -g.dc and dr == -g.dr)
      local score
      if target then
        local dx = math.abs(g.c + dc - target[1])
        score = math.min(dx, W - dx) ^ 2 + (g.r + dr - target[2]) ^ 2
      else
        score = phos.sys.random(1, 1000)          -- 惊吓：乱走
      end
      if self:exits(g.r + dr, g.c + dc) <= 1 then
        score = score + 100000                    -- 死角：代价高到不会被选中
      end
      if is_reverse then
        reverse_dir = dir                         -- 只在无处可去时才用
      elseif not best_score or score < best_score then
        best, best_score = dir, score
      end
    end
  end

  best = best or reverse_dir                      -- 被逼进死角：允许掉头，至少能动
  if best then
    g.dc, g.dr = best[1], best[2]
    g.c, g.r = wrap_col(g.c + g.dc), g.r + g.dr
  end
end

-- 推进一帧：返回事件表（音效与存档由 main.lua 据此决定）
function Game:update(dt)
  local events = {}

  if self.state == "ready" then
    self.state_timer = self.state_timer - dt
    if self.state_timer <= 0 then self.state = "play" end
    return events
  end

  if self.state == "dying" then
    self.state_timer = self.state_timer - dt
    if self.state_timer <= 0 then
      self.lives = self.lives - 1
      if self.lives <= 0 then
        self.state = "over"
        events.gameover = true
      else
        self:place_actors()
        self.state, self.state_timer = "ready", READY_TIME
      end
    end
    return events
  end

  if self.state == "clear" then
    self.state_timer = self.state_timer - dt
    if self.state_timer <= 0 then
      self.level = self.level + 1
      self:start_level()
    end
    return events
  end

  if self.state == "over" then return events end

  -- --- 追逐 / 散开的节奏切换 ---
  if self.fright_timer > 0 then
    self.fright_timer = self.fright_timer - dt
    if self.fright_timer <= 0 then self.ghost_combo = 0 end
  else
    self.mode_timer = self.mode_timer - dt
    if self.mode_timer <= 0 then
      if self.mode == "scatter" then
        self.mode, self.mode_timer = "chase", CHASE_TIME
      else
        self.mode, self.mode_timer = "scatter", SCATTER_TIME
      end
      -- 换模式时全体掉头：经典手感，也顺手把"正往死角钻"的幽灵赶出来
      for _, g in ipairs(self.ghosts) do
        if not g.eaten then g.dc, g.dr = -g.dc, -g.dr end
      end
    end
  end

  -- --- 玩家（每关略快一点） ---
  local player_step = STEP * (0.96 ^ (self.level - 1))
  self.move_acc = self.move_acc + dt
  while self.move_acc >= player_step do
    self.move_acc = self.move_acc - player_step
    if self:advance_player() then
      local here = self.grid[self.player.r][self.player.c]
      if here == "." then
        self.grid[self.player.r][self.player.c] = ""
        self.dots_left, self.eaten = self.dots_left - 1, self.eaten + 1
        self.score = self.score + 10
        events.eat = true
      elseif here == "o" then
        self.grid[self.player.r][self.player.c] = ""
        self.dots_left, self.eaten = self.dots_left - 1, self.eaten + 1
        self.score = self.score + 50
        self.fright_timer, self.ghost_combo = FRIGHT_TIME, 0
        events.power = true
      end

      -- 水果：每吃满 FRUIT_LINE 颗出现一次。这里必须用"下一颗的门槛"而不能写
      -- eaten >= FRUIT_LINE：那个条件在吃掉水果后**依然成立**，下一格（0.1 秒后）
      -- 心就会当场重生——玩家看到的就是"吃了没反应、也不消失"
      if not self.fruit and self.eaten >= self.next_fruit then
        self.fruit, self.fruit_timer = { c = FRUIT_CELL.c, r = FRUIT_CELL.r }, FRUIT_TIME
        self.next_fruit = self.next_fruit + FRUIT_LINE
        events.fruit = true
      end
      if self.dots_left == 0 then
        self.state, self.state_timer = "clear", CLEAR_TIME
        events.cleared = true
        return events
      end
    end
  end

  -- 吃到水果：每帧都判，而不是只在"走完一格之后"判。水果完全可能出现在玩家脚下
  -- （踩点计时，或者玩家刚复活在同一格），那种情况站着不动就该吃到；只在移动后判会漏掉
  if self.fruit and self.player.c == self.fruit.c and self.player.r == self.fruit.r then
    -- 加分 + 一条命。命才是这条规则里"看得见"的奖励
    local points = 100 * self.level
    self.score = self.score + points
    self.lives = self.lives + 1
    self.fruit, self.fruit_timer = nil, 0
    events.bonus, events.life = points, true
  end

  -- --- 幽灵 ---
  local ghost_step = ((self.fright_timer > 0) and FRIGHT_STEP or GHOST_STEP)
                     * (0.97 ^ (self.level - 1))
  self.ghost_acc = self.ghost_acc + dt
  while self.ghost_acc >= ghost_step do
    self.ghost_acc = self.ghost_acc - ghost_step
    for _, g in ipairs(self.ghosts) do self:advance_ghost(g) end
  end

  -- --- 相遇判定 ---
  for _, g in ipairs(self.ghosts) do
    if not g.eaten and g.c == self.player.c and g.r == self.player.r then
      if self.fright_timer > 0 then
        local points = 200 * (2 ^ self.ghost_combo)
        self.ghost_combo = math.min(self.ghost_combo + 1, 3)
        self.score = self.score + points
        g.eaten, g.respawn = true, 4
        events.ghost = points
      else
        self.state, self.state_timer = "dying", DYING_TIME
        self.player.alive = false
        events.death = true
        return events
      end
    end
  end

  if self.fruit_timer > 0 then
    self.fruit_timer = self.fruit_timer - dt
    if self.fruit_timer <= 0 then self.fruit = nil end
  end

  return events
end

-- 供 agent 观察（main.lua 的 debug_state 会把它带出去）
function Game:status()
  local ghosts = {}
  for _, g in ipairs(self.ghosts) do
    ghosts[#ghosts + 1] = {
      name = g.name, c = g.c, r = g.r,
      scared = self.fright_timer > 0 and not g.eaten, eaten = g.eaten,
    }
  end
  return {
    state = self.state, score = self.score, lives = self.lives, level = self.level,
    dots_left = self.dots_left, power_left = math.floor(self.fright_timer * 10) / 10,
    player_c = self.player.c, player_r = self.player.r,
    maze_w = W, maze_h = H, ghosts = ghosts,
  }
end

-- 可调参数（`~` 调试台，见 phos.debug.number）：闭包直接读写本模块的常数，改完即时生效
function Game.tunables()
  return {
    { name = { zh = "玩家步长", en = "Player step" }, get = function() return STEP end,
      set = function(v) STEP = v end, min = 0.04, max = 0.30, step = 0.005 },
    { name = { zh = "幽灵步长", en = "Ghost step" }, get = function() return GHOST_STEP end,
      set = function(v) GHOST_STEP = v end, min = 0.04, max = 0.35, step = 0.005 },
  }
end

return Game

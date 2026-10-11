-- 玩法：挡板、球、砖块与关卡（不碰音频 / 存档 / 输入）
--
-- 设计上刻意**不用随机数**：球的发射角度固定，碰撞完全确定，
-- 于是"第 N 帧得几分"是钉死的 —— 帧号与分数一一对应，复盘时对得上。

local Game = {}
Game.__index = Game

-- 场地：内容区 80x45，右侧 18 列留给侧栏，左上留边框与标题
Game.OX, Game.OY = 2, 3
Game.W, Game.H = 57, 40

local BRICK_COLS, BRICK_ROWS = 14, 6
local BRICK_W = 3                      -- 每块砖 3 字符宽
local BRICK_STRIDE = 4                 -- 含 1 格间隙：14 列刚好 56 格
local PADDLE_W = 9                      -- 挡板 9 字符宽；高只有 1 行，不必单列常量
local BALL_R = 1
local PADDLE_ROW = Game.H - 3
local PADDLE_SPEED = 46.0              -- 格/秒
local BASE_BALL_SPEED = 21.0
local LAUNCH_ANGLE = 0.52              -- 发射时的横向分量（0 = 垂直向上）
local MAX_BOUNCE_ANGLE = 0.78          -- 挡板边缘的最大反弹角（越斜越好玩，但别贴地平）
local LEVEL_SPEEDUP = 1.07
local KILL_ROW = Game.H                -- 球落到这一行即失一命

Game.LIVES = 3

-- 砖块布局：每格是一个分值档位，0 = 空
local LAYOUT = {
  "66666666666666",
  "55555555555555",
  "44444444444444",
  "33333333333333",
  "22222222222222",
  "11111111111111",
}

local TIER_COLOR = {
  [1] = "dark_gray",
  [2] = "blue",
  [3] = "cyan",
  [4] = "green",
  [5] = "yellow",
  [6] = "red",
}

local TIER_SCORE = { [1] = 10, [2] = 20, [3] = 30, [4] = 40, [5] = 50, [6] = 60 }

local function clock(time)
  local m = math.floor(time / 60)
  local s = math.floor(time % 60)
  return string.format("%d:%02d", m, s)
end

Game.clock = clock

function Game.new()
  local self = setmetatable({}, Game)
  self.score = 0
  self.lives = Game.LIVES
  self.level = 1
  self.time = 0
  self.paddle_x = math.floor((Game.W - PADDLE_W) / 2)
  self:reset_ball()
  self:build_bricks()
  self.state = "ready"   -- ready | playing | dead | cleared | gameover
  self.hold = 0
  self.ball_h = 0        -- 球的水平分速度（格/秒）
  self.ball_v = 0
  self.events = {}
  return self
end

function Game:ball_speed()
  return BASE_BALL_SPEED * (LEVEL_SPEEDUP ^ (self.level - 1))
end

function Game:reset_ball()
  self.ball_x = self.paddle_x + (PADDLE_W - 1) / 2
  self.ball_y = PADDLE_ROW - 2
  self.ball_h = 0
  self.ball_v = 0
end

function Game:build_bricks()
  self.bricks = {}
  self.bricks_left = 0
  for row = 1, BRICK_ROWS do
    local line = LAYOUT[row] or ""
    for col = 1, BRICK_COLS do
      local tier = tonumber(string.sub(line, col, col)) or 0
      if tier > 0 then
        self.bricks[(row - 1) * BRICK_COLS + col] = tier
        self.bricks_left = self.bricks_left + 1
      end
    end
  end
end

function Game:brick_at(cx, cy)
  if cx < 0 or cx >= Game.W or cy < 0 or cy >= Game.H then return nil end
  if cy >= BRICK_ROWS then return nil end
  -- 砖块占 3 列，之后留 1 格间隙：间隙里不能撞到砖
  local col = math.floor(cx / BRICK_STRIDE) + 1
  if col < 1 or col > BRICK_COLS then return nil end
  if cx % BRICK_STRIDE >= BRICK_W then return nil end
  local key = cy * BRICK_COLS + col
  return self.bricks[key], key, col - 1, cy
end

function Game:launch()
  if self.state ~= "ready" then return false end
  self.state = "playing"
  -- 发射角固定（不用随机数）：横向分量决定了整局的确定性
  self.ball_h = self:ball_speed() * LAUNCH_ANGLE
  self.ball_v = -self:ball_speed() * math.sqrt(1 - LAUNCH_ANGLE * LAUNCH_ANGLE)
  self.events.launch = true
  return true
end

function Game:hit_paddle()
  -- 打中挡板的位置决定反弹角度：越靠边角度越斜
  local offset = (self.ball_x - (self.paddle_x + PADDLE_W / 2)) / (PADDLE_W / 2)
  offset = math.max(-1, math.min(1, offset))
  local angle = offset * MAX_BOUNCE_ANGLE
  local speed = self:ball_speed()
  self.ball_h = speed * angle
  self.ball_v = -speed * math.sqrt(1 - angle * angle)
  self.events.paddle = true
end

function Game:lose_life()
  self.lives = self.lives - 1
  self.events.dead = true
  if self.lives <= 0 then
    self.state = "gameover"
    self.events.gameover = true
    return
  end
  self.state = "ready"
  self:reset_ball()
end

function Game:step_ball(dt)
  -- 分步推进：每步不超过 1 格，避免高速穿砖
  local steps = math.max(1, math.ceil(math.max(math.abs(self.ball_h), math.abs(self.ball_v)) * dt))
  local sub = dt / steps
  for _ = 1, steps do
    self.ball_x = self.ball_x + self.ball_h * sub
    self.ball_y = self.ball_y + self.ball_v * sub

    -- 左右墙
    if self.ball_x < 0 then
      self.ball_x = 0
      self.ball_h = -self.ball_h
      self.events.wall = true
    elseif self.ball_x > Game.W - 1 then
      self.ball_x = Game.W - 1
      self.ball_h = -self.ball_h
      self.events.wall = true
    end
    -- 顶墙
    if self.ball_y < 0 then
      self.ball_y = 0
      self.ball_v = -self.ball_v
      self.events.wall = true
    end

    -- 砖块：命中即碎，按行给分
    local brick, key, col, row = self:brick_at(math.floor(self.ball_x), math.floor(self.ball_y))
    if brick then
      self.bricks[key] = nil
      self.bricks_left = self.bricks_left - 1
      self.score = self.score + (TIER_SCORE[brick] or 10) * 1
      self.ball_v = -self.ball_v
      self.events.brick = brick
      if self.bricks_left <= 0 then
        self.state = "cleared"
        self.hold = 1.2
        self.events.cleared = true
        return
      end
    end

    -- 挡板
    local py = PADDLE_ROW
    if self.ball_v > 0 and self.ball_y >= py - BALL_R and self.ball_y <= py and
       self.ball_x >= self.paddle_x - 0.5 and self.ball_x <= self.paddle_x + PADDLE_W - 0.5 then
      self.ball_y = py - BALL_R
      self:hit_paddle()
    end

    if self.ball_y > KILL_ROW then
      self:lose_life()
      return
    end
  end
end

-- 返回本帧事件（main.lua 据此播音效）
function Game:update(dt)
  self.events = {}
  if self.state == "gameover" then return self.events end

  if self.state == "cleared" then
    self.hold = self.hold - dt
    if self.hold <= 0 then
      self.level = self.level + 1
      self:build_bricks()
      self.state = "ready"
      self:reset_ball()
    end
    return self.events
  end

  self.time = self.time + dt
  if self.state == "playing" then self:step_ball(dt) end

  if self.state == "ready" then
    -- 球停在挡板上，随挡板一起走
    self.ball_x = self.paddle_x + (PADDLE_W - 1) / 2
    self.ball_y = PADDLE_ROW - 2
  end
  return self.events
end

function Game:move_paddle(dir, dt)
  if self.state == "gameover" or self.state == "cleared" then return end
  self.paddle_x = self.paddle_x + dir * PADDLE_SPEED * dt
  if self.paddle_x < 0 then self.paddle_x = 0 end
  if self.paddle_x > Game.W - PADDLE_W then self.paddle_x = Game.W - PADDLE_W end
end

function Game:restart()
  self.score = 0
  self.lives = Game.LIVES
  self.level = 1
  self.time = 0
  self.paddle_x = math.floor((Game.W - PADDLE_W) / 2)
  self:build_bricks()
  self.state = "ready"
  self:reset_ball()
end

function Game:color_of(tier)
  return TIER_COLOR[tier] or "white"
end

Game.PADDLE_W, Game.PADDLE_ROW = PADDLE_W, PADDLE_ROW
Game.BRICK_W, Game.BRICK_STRIDE = BRICK_W, BRICK_STRIDE
Game.BRICK_COLS, Game.BRICK_ROWS = BRICK_COLS, BRICK_ROWS

return Game

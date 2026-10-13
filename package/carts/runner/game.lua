-- game.lua —— 沙漠长跑的规则（不碰输入、绘制、音频与存档）
--
-- 坐标：一切高度都记"离地面多少格"（0 = 站在地面上），规则里不出现屏幕行号，
-- 屏幕映射由 main.lua 负责，于是规则与分辨率无关。
--
-- 碰撞盒只算实心部分：仙人掌只看中间那一列，翼龙只看下排。四种障碍因此各有唯一解法：
--   矮仙人掌 → 跳；高 / 带臂仙人掌 → 跳更高；贴地翼龙 → 跳；高位翼龙 → 蹲。
--
-- 跳跃高度是算出来的：v²/(2g) = 18² / (2·30) = 5.4 格，滞空 1.2 秒。
-- 所以"跳不过高仙人掌"不会发生，也不必靠反复试出来。

-- 仙人掌只有单株：障碍判定宽 1 格。想在跳跃窗口（高度 ≥3 的那段时间）里通过
-- 更宽的障碍是算不通的，所以宁可换形状，也不放"看着能过其实过不去"的东西。
-- 字符画里 '.' 是透明格，其余字符是实心像素（'#' 才是上色用的键——精灵的颜色映射
-- 以**单字节**字符为键，用 '█' 这种多字节字符查不到表，会退化成风格色）。
local CACTUS = {
  { shape = { ".#.", ".#." },        hit = { dx = 1, w = 1, h = 2 } },  -- 矮：跳
  { shape = { ".#.", ".#.", ".#." }, hit = { dx = 1, w = 1, h = 3 } },  -- 高：跳更高
  { shape = { ".#.", "###", ".#." }, hit = { dx = 1, w = 1, h = 3 } },  -- 带臂：跳更高
}
-- 翼龙两种高度：lift 是它下排离地多少格，判定只算下排中间两格
-- （翅膀是画给人看的；判定收窄才不会被"看着擦边"骗到）
local BIRD = {
  { lift = 0, hit = { dx = 1, w = 2, h = 1 } },   -- 贴地：只能跳过去
  { lift = 1, hit = { dx = 1, w = 2, h = 1 } },   -- 高位：只能蹲下去
}
local BIRD_FRAMES = {
  { ".##.", "##.#" },   -- 翅膀下压
  { "##.#", ".##." },   -- 翅膀上扬
}

-- 跳跃参数是算出来的，不是调出来的。唯一的硬要求是：**跳上去之后必须一直保持到
-- 障碍完全过去**，否则就是"跳起来也照样蹭到"。
--   通过时间 = (障碍判定宽 + 跑者判定宽) / 速度 = (1 + 3) / 11 ≈ 0.36 秒
--   高度 ≥3（高仙人掌）的窗口 = (2/g)·√(v²-6g) ≈ 0.80 秒；≥2（矮仙人掌）≈ 0.95 秒
-- 于是时机余量约 0.44 / 0.59 秒，换算成距离是"早 2 格、晚 2 格都能过"；
-- 速度越快通过时间越短，所以越跑越宽松。这组数是 5.4 格高、1.2 秒滞空。
local GRAVITY = 30.0
local JUMP_VELOCITY = 18.0
local RELEASE_KEEP = 0.9      -- 松手保留的上升速度：轻点约 4.4 格，按住约 5.4 格
local BASE_SPEED = 11.0
local SPEED_GAIN = 0.55       -- 每 100 分加速
local STAGE_LENGTH = 700      -- 昼夜每这么多分换一次
local READY_TIME = 1.2
local DYING_TIME = 1.1
local FIRST_GAP = 1.2         -- 开局第一个障碍等这么久

local Game = {}
Game.__index = Game
Game.CACTUS, Game.BIRD, Game.BIRD_FRAMES = CACTUS, BIRD, BIRD_FRAMES
Game.RUNNER_X, Game.RUNNER_BOX_W = 8, 3
-- 供测试与文档核对：最高能跳多少格
Game.JUMP_HEIGHT = (JUMP_VELOCITY * JUMP_VELOCITY) / (2 * GRAVITY)

function Game.new(world_width)
  local self = setmetatable({}, Game)
  self.world_w = world_width
  self.best = 0
  self:reset_run()
  return self
end

function Game:reset_run()
  self.score = 0
  self.speed = BASE_SPEED
  self.night = false
  self.stage = 0
  self.state, self.state_timer = "ready", READY_TIME
  self.runner = { lift = 0, vy = 0, ducking = false, stride = 0 }
  self.obstacles = {}
  self.spawn_timer = FIRST_GAP
  self.gap = 18
  self.flash = 0
  self.milestone = 0
end

-- 起跳：只有踩在地面上才跳得起来（顺手挡掉二段跳）
function Game:jump()
  if self.state ~= "play" or self.runner.lift > 0 then return false end
  self.runner.vy = JUMP_VELOCITY
  self.runner.ducking = false
  return true
end

function Game:release_jump()
  if self.runner.vy > 0 then self.runner.vy = self.runner.vy * RELEASE_KEEP end
end

-- 按住"下"：在地面上是蹲、在空中是急速下落，两件事分开记
-- （腾空时不许变蹲：空中忽大忽小的碰撞盒玩起来像被"吸"下去）
function Game:hold_down(on)
  if self.state ~= "play" then return end
  self.runner.ducking = on and self.runner.lift <= 0
  self.runner.diving = on and self.runner.lift > 0
end

-- 跑者的碰撞盒：站立占底下两格，蹲下只占最下一格
function Game:runner_box()
  if self.runner.ducking then return { bottom = 0, h = 1 } end
  return { bottom = self.runner.lift, h = 2 }
end

-- 高度区间是否相交（x 方向在下面单独判）
local function height_overlaps(runner, obstacle)
  return runner.bottom < obstacle.lift + obstacle.hit.h
     and obstacle.lift < runner.bottom + runner.h
end

local function overlaps_x(obstacle)
  local ox = obstacle.x + obstacle.hit.dx
  return ox < Game.RUNNER_X + Game.RUNNER_BOX_W and Game.RUNNER_X < ox + obstacle.hit.w
end

local function spawn_cactus(self, index, x)
  local spec = CACTUS[index]
  self.obstacles[#self.obstacles + 1] = {
    kind = "cactus", shape = spec.shape, hit = spec.hit, lift = 0,
    x = x, width = 3,
  }
end

local function spawn(self)
  local roll = phos.sys.random(1, 100)
  if roll <= 45 then
    spawn_cactus(self, 1, self.world_w)              -- 矮
  elseif roll <= 72 then
    spawn_cactus(self, 2, self.world_w)              -- 高
  elseif roll <= 88 then
    spawn_cactus(self, 3, self.world_w)              -- 带臂
  else
    local index = phos.sys.random(1, 2)              -- 翼龙：贴地要跳、高位要蹲
    self.obstacles[#self.obstacles + 1] = {
      kind = "bird", shape = BIRD_FRAMES[1], hit = BIRD[index].hit, lift = BIRD[index].lift,
      x = self.world_w, width = 4, bird = true,
    }
  end
  -- 间隔按"距离"给，并且必须大于一次完整跳跃的落地距离（滞空 1.2 秒 × 速度，
  -- 高速时能到 20 格以上），否则会出现"跳完还在下落，下一个已经贴脸"——
  -- 那会被误当成跳跃不灵。留出的余量随速度同步放大，落地后总还有反应时间。
  self.gap = 18 + math.floor(self.speed) + phos.sys.random(0, 10)
end

function Game:update(dt)
  local events = {}
  self.flash = self.flash + dt

  if self.state == "ready" then
    self.state_timer = self.state_timer - dt
    if self.state_timer <= 0 then self.state = "play" end
    return events
  end

  if self.state == "over" then return events end

  if self.state == "dying" then
    self.state_timer = self.state_timer - dt
    if self.state_timer <= 0 then
      self.state = "over"
      events.gameover = true
    end
    return events
  end

  -- --- 跑者：重力与落地 ---
  local run = self.runner
  if run.lift > 0 or run.vy > 0 then
    -- 空中按住下：重力加大到 1.8 倍，落得更快。它只**加**重力，所以永远只是更早落地，
    -- 不可能变成"跳得更高"；上升段同样生效，于是"跳早了"可以自己压下去
    local gravity = run.diving and GRAVITY * 1.8 or GRAVITY
    run.vy = run.vy - gravity * dt
    run.lift = run.lift + run.vy * dt
    if run.lift <= 0 then
      run.lift, run.vy = 0, 0
      run.ducking, run.diving = false, false
      events.land = true
    end
  end
  run.stride = (run.stride + dt * self.speed) % 2

  -- --- 分数、提速与昼夜 ---
  self.score = self.score + self.speed * dt
  local stage = math.floor(self.score / STAGE_LENGTH)
  if stage ~= self.stage then
    self.stage = stage
    self.night = (stage % 2 == 1)
    events.stage = self.night
  end
  local milestone = math.floor(self.score / 100)
  if milestone > self.milestone then
    self.milestone = milestone
    events.milestone = milestone
  end
  -- 每帧按**当前** BASE_SPEED 重算：于是 `~` 调试台改"基础速度"能立即生效
  -- （只在跨里程碑时重算的话，改了要等下次跨百分才动，看不出效果）
  self.speed = BASE_SPEED + SPEED_GAIN * self.milestone

  -- --- 障碍：开局等一等，之后按"上一组走出了多远"放下一个 ---
  local last = self.obstacles[#self.obstacles]
  local due
  if last then
    due = (self.world_w - last.x) >= self.gap
  else
    self.spawn_timer = self.spawn_timer - dt
    due = self.spawn_timer <= 0
  end
  if due and #self.obstacles < 8 then spawn(self) end

  for i = #self.obstacles, 1, -1 do
    local o = self.obstacles[i]
    o.x = o.x - self.speed * dt
    if o.bird then o.shape = BIRD_FRAMES[(math.floor(self.flash * 7) % 2) + 1] end
    if o.x + o.width < -1 then table.remove(self.obstacles, i) end
  end

  -- --- 碰撞：只认实心部分 ---
  local box = self:runner_box()
  for _, o in ipairs(self.obstacles) do
    if overlaps_x(o) and height_overlaps(box, o) then
      self.state, self.state_timer = "dying", DYING_TIME
      events.death = true
      return events
    end
  end

  self.best = math.max(self.best, math.floor(self.score))
  return events
end

-- 供 agent 观察（main.lua 的 debug_state 会把它带出去）
function Game:status()
  local obstacles = {}
  for _, o in ipairs(self.obstacles) do
    obstacles[#obstacles + 1] = {
      kind = o.kind, x = math.floor(o.x * 10) / 10, lift = o.lift, h = o.hit.h,
    }
  end
  return {
    state = self.state, score = math.floor(self.score), best = self.best,
    speed = math.floor(self.speed * 10) / 10, night = self.night,
    runner_lift = math.floor(self.runner.lift * 100) / 100,
    jump_height = math.floor(Game.JUMP_HEIGHT * 100) / 100,
    ducking = self.runner.ducking, gap = self.gap, obstacles = obstacles,
  }
end

-- 可调参数（`~` 调试台，见 phos.debug.number）
function Game.tunables()
  return {
    { name = "基础速度", get = function() return BASE_SPEED end,
      set = function(v) BASE_SPEED = v end, min = 3, max = 30, step = 0.5 },
    { name = "重力", get = function() return GRAVITY end,
      set = function(v) GRAVITY = v end, min = 5, max = 80, step = 1 },
  }
end

return Game

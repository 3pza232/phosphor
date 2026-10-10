-- SIGNAL RAIN：噪点如雨下落，产品名从干扰中逐列锁定
--
-- 三段（与声音同一批时间点）：
--   0.0~1.6s  雨幕最密：每根雨柱各带速度下落，另有稀疏噪点闪烁
--   1.6~2.6s  逐列锁定：产品名从左往右被"擦"出来，已锁定的列不再受噪点干扰
--   2.6s~     信号已捕获：偶发单点掉帧 + 一条缓慢横移的撕裂线
--
-- 分工：**状态只在 update 里推进**（时间、雨柱位置、音效触发），draw 只按当前状态作画。
-- 主机每帧先 update 再 draw，而 dt 只传给 update——在 draw 里用 dt 会拿到 nil

local t = 0
local W, H = 80, 45

-- 用主机的可玩区尺寸而不是写死 80x45：侧栏宽度变了这段动画也不会画到可见区之外
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end

local LOGO = phos.sys.product()          -- 产品名取自主机 API，不硬编码

-- 文案跟随机器界面语言（与卡带同一套约定：phos.lang.dict，缺 en 回落中文）
local SUB = {
  zh = { prefix = "系统 v", tail = " —— 信号已捕获", wait = "正在搜索信号" },
  en = { prefix = "SYSTEM v", tail = " — SIGNAL LOCKED", wait = "SEARCHING FOR SIGNAL" },
}
local sub = phos.lang.dict(SUB)

local SPECK = { ".", ":", "'", "`", ",", "-", "=", "+", "*" }
local LOCK_T, FULL_T = 1.6, 2.6           -- 开始锁定 / 完全锁定（秒）
local LOGO_ROW = 19                        -- 产品名所在行
local SUB_ROW = 23

-- 雨柱：每列一根，各自带位置与速度。用常驻数组而不是每帧重算，
-- 才能有"持续下落"的方向感；速度差造出雨幕的层次
local drops = {}
for x = 0, W - 1 do
  drops[x] = {
    y = phos.sys.random(0, H - 1),
    speed = phos.sys.random(18, 42) / 10,   -- 1.8~4.2 行/秒
    len = phos.sys.random(2, 4),            -- 拖尾长度：有尾巴才是"落下"，单点只是闪烁
    alive = phos.sys.random(1, 100) <= 80,  -- 大部分列在下雨，少数空着：疏密不匀才像雨
  }
end

local next_crackle = 0
local locked = false
local tear_y = 0

local function clamp01(v) return v < 0 and 0 or (v > 1 and 1 or v) end

-- 信号强度：0 = 全是干扰，1 = 完全锁定。雨与噪点都按它衰减
local function signal()
  return clamp01((t - LOCK_T) / (FULL_T - LOCK_T))
end

function update(dt)
  t = t + dt

  -- 沙沙声：雨最密的 1.6 秒里每 0.2s 一次短噪声，音量随雨一起变小
  if t < LOCK_T and t >= next_crackle then
    next_crackle = t + 0.2
    phos.audio.beep(120, 0.07, { wave = "noise", volume = 0.12 * (1 - t / LOCK_T), release = 0.05 })
  end

  -- 锁定：产品名擦完的同一刻给一声清亮的确认，再补一个高音把它"钉住"
  if not locked and t >= FULL_T then
    locked = true
    phos.audio.note("A4", { wave = "square", dur = 0.12, sweep = 1760, volume = 0.18 })
    phos.audio.note("E5", { wave = "sine", dur = 0.5, volume = 0.08, release = 0.4 })
  end

  -- 雨柱下落：位置只在 update 里推进；落到屏底就回到顶端（循环成持续的雨）。
  -- 锁定后雨势明显变慢，但不会骤然消失
  local noise = 1 - signal()
  for x = 0, W - 1 do
    local d = drops[x]
    if d.alive then
      d.y = d.y + d.speed * dt * (0.25 + noise)
      if d.y > H + d.len then
        d.y = -d.len
        d.speed = phos.sys.random(18, 42) / 10
        d.len = phos.sys.random(1, 3)
        d.alive = phos.sys.random(1, 100) <= math.floor(20 + 60 * noise)
      end
    end
  end

  -- 撕裂线缓慢下移（比固定频率闪烁更像"信号不稳"）
  tear_y = tear_y + (2 + 5 * noise) * dt
  if tear_y >= H + 4 then tear_y = -2 end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  local s = signal()
  local noise = 1 - s
  local cx = W // 2
  local logo_x = cx - #LOGO // 2
  local lit = math.floor(clamp01((t - LOCK_T) / (FULL_T - LOCK_T)) * (#LOGO + 1))
  if lit > #LOGO then lit = #LOGO end

  -- 产品名那一行附近不落雨：字要先看得清，雨是从它背后退开的
  local function over_logo(x, y)
    return y == LOGO_ROW and x >= logo_x - 1 and x < logo_x + #LOGO + 1
  end

  -- 雨柱：只画，不动状态
  for x = 0, W - 1 do
    local d = drops[x]
    if d.alive then
      for k = 0, d.len - 1 do
        local y = math.floor(d.y) - k
        if y >= 0 and y < H and not over_logo(x, y) then
          -- 柱头亮、柱尾暗；四分之一柱头带荧光绿，呼应机器的磷光配色
          local col = (k > 0) and C.dark_gray
                      or ((x % 4 == 0) and C.green or C.gray)
          S.put(x, y, SPECK[phos.sys.random(1, #SPECK)], col)
        end
      end
    end
  end

  -- 背景噪点：稀疏闪烁，数量随信号增强而减少
  local specks = math.floor(H * W * 0.030 * noise)
  for _ = 1, specks do
    local x, y = phos.sys.random(0, W - 1), phos.sys.random(0, H - 1)
    if not over_logo(x, y) then
      S.put(x, y, SPECK[phos.sys.random(1, #SPECK)],
            phos.sys.random(1, 3) == 1 and C.gray or C.dark_gray)
    end
  end

  -- 产品名：已锁定的前缀压成亮字（最后一位带绿），未锁定的位置偶尔闪一点轮廓
  for k = 1, lit do
    S.put(logo_x + k - 1, LOGO_ROW, LOGO:sub(k, k), k == lit and C.green or C.white)
  end
  if lit > 0 and lit < #LOGO then
    S.put(logo_x + lit, LOGO_ROW, "_", C.green)     -- 正在被"擦"的那一格
  elseif lit == 0 and noise > 0.35 and math.floor(t * 6) % 3 == 0 then
    for k = 1, #LOGO, 2 do
      S.put(logo_x + k - 1, LOGO_ROW, ".", C.dark_gray)
    end
  end

  -- 副标题：锁定后打字机打出；未锁定前显示"正在搜索信号"
  if s >= 1 then
    local line = sub.prefix .. phos.sys.version() .. sub.tail
    local n = math.min(#line, math.floor((t - FULL_T) * 22))
    S.print(cx - #line // 2, SUB_ROW, line:sub(1, n), C.green)
    if n < #line and math.floor(t * 4) % 2 == 0 then
      S.put(cx - #line // 2 + n, SUB_ROW, "_", C.white)
    end
  else
    local wait = sub.wait
    local x = cx - #wait // 2
    S.print(x, SUB_ROW, wait, C.dark_gray)
    if math.floor(t * 3) % 2 == 0 then S.put(x + #wait + 1, SUB_ROW, ".", C.gray) end
  end

  -- 余韵：单点掉帧 + 缓慢下移的撕裂线
  if t > FULL_T then
    if phos.sys.random(1, 90) == 1 then
      S.put(phos.sys.random(0, W - 1), phos.sys.random(0, H - 1), "*", C.gray)
    end
    local y = math.floor(tear_y)
    if y >= 0 and y < H then
      for x = 0, W - 1 do
        if (x + y) % 5 == 0 and not over_logo(x, y) then S.put(x, y, "-", C.dark_gray) end
      end
    end
  end
end

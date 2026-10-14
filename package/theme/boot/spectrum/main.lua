-- SPECTRUM：频谱分析仪（抖动电平柱 + 峰值保持 + 倒影 + 扫描光标）
--
-- 时间线：
--   0.0~2.2s  46 根电平柱各自跳动（上升快、下落慢，像真的电平表），峰值保持点慢慢回落
--   2.2s~     目标电压归零，柱体收平 → 打出一声锁定音与产品名
-- 分工：状态只在 update 推进，draw 只按当前状态作画（dt 不进 draw）
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "频谱分析", lock = "锁定" },
              en = { title = "SPECTRUM ANALYZER", lock = "LOCKED" } }
local L = phos.lang.dict(TXT)

local TOP, BASE = 6, H - 12          -- 柱顶最高行 / 基线行
local SPAN = BASE - TOP
local BARS = math.min(46, W - 8)
local X0 = (W - BARS) // 2
local FLAT_T = 2.2

local function rnd(a, b) return phos.sys.random(a, b) end

local bars = {}
for i = 1, BARS do bars[i] = { h = rnd(6, 60) / 100, peak = 0.4, target = 0.3, next = 0 } end
local flat, locked = false, false

function update(dt)
  t = t + dt
  if t >= FLAT_T then flat = true end
  for i = 1, BARS do
    local b = bars[i]
    if t >= b.next then
      b.next = t + rnd(4, 11) / 100
      b.target = flat and 0.03 or (rnd(6, 100) / 100)
    end
    local rate = (b.target > b.h) and 9 or 4     -- 上升快、下落慢
    b.h = b.h + (b.target - b.h) * math.min(1, rate * dt)
    b.peak = math.max(b.h, b.peak - dt * 0.35)   -- 峰值保持：慢慢回落
  end
  if flat and not locked and t >= FLAT_T + 0.6 then
    locked = true
    phos.audio.note("A4", { wave = "square", dur = 0.18, sweep = 1320, volume = 0.16 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.gray)
  if locked then S.print(math.max(3, W - #L.lock - 4), 1, L.lock, C.green) end

  -- 背景刻度（横向细线）
  for y = TOP, BASE, 6 do
    for x = X0 - 2, X0 + BARS + 1, 2 do S.put(x, y, ".", C.dark_gray) end
  end
  for x = X0 - 2, X0 + BARS + 1 do S.put(x, BASE + 1, "-", C.dark_gray) end

  -- 柱体从基线往上画；按高度分红/黄/绿三色，越高压越"危险"
  for i = 1, BARS do
    local x = X0 + i - 1
    local h = math.floor(bars[i].h * SPAN + 0.5)
    for k = 0, h - 1 do
      local frac = k / math.max(1, SPAN)
      local col = frac > 0.72 and C.red or (frac > 0.45 and C.yellow or C.green)
      S.put(x, BASE - k, "#", col)
    end
    local pk = BASE - math.floor(bars[i].peak * SPAN + 0.5)   -- 峰值保持：柱顶上方一颗亮点
    if pk < BASE then S.put(x, pk, "'", C.white) end
    if h > 0 then S.put(x, BASE + 2, ":", C.dark_gray) end     -- 倒影：基线下方一行镜像
  end

  -- 扫描光标：慢慢掠过整排柱体
  local cur = X0 + math.floor((0.5 + 0.5 * math.sin(t * 0.9)) * (BARS - 1))
  S.put(cur, BASE + 1, "+", C.white)

  if locked then
    S.print(W // 2 - #LOGO // 2, TOP - 3, LOGO, C.white)
  end
end

-- SPECTRUM：频谱条随噪声跳动，末段收束成一条平线，再打出产品名
--
-- 时间线：
--   0.0~2.2s  46 根电平柱各自跳动（上升快、下落慢，像真的电平表）
--   2.2s~     目标电压归零，柱体收平 → 基线拉直后打出一声锁定音与产品名
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

local TOP, BASE = 6, H - 10          -- 柱顶最高行 / 基线行
local SPAN = BASE - TOP
local BARS = math.min(46, W - 8)
local X0 = (W - BARS) // 2
local FLAT_T = 2.2

local bars = {}
for i = 1, BARS do bars[i] = { h = phos.sys.random(6, 60) / 100, target = 0.3, next = 0 } end
local flat, locked = false, false

function update(dt)
  t = t + dt
  if t >= FLAT_T then flat = true end
  for i = 1, BARS do
    local b = bars[i]
    if t >= b.next then
      b.next = t + phos.sys.random(4, 11) / 100
      b.target = flat and 0.03 or (phos.sys.random(6, 100) / 100)
    end
    local rate = (b.target > b.h) and 9 or 4     -- 上升快、下落慢
    b.h = b.h + (b.target - b.h) * math.min(1, rate * dt)
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
  if locked then S.print(W - #L.lock - 4, 1, L.lock, C.green) end

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
  end

  if locked then
    local lx = W // 2 - #LOGO // 2
    S.print(lx, TOP - 3, LOGO, C.white)
  end
end

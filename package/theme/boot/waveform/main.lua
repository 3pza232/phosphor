-- WAVEFORM LOCK：示波器锁相
-- 动效：栅格上先是一条抖动的噪声波，随"锁相"进度逐渐收敛成稳定的方波；
--       右侧读数从 CALIBRATING 变成 LOCKED，游标沿波推进，底部一行进度。
--
-- 实现要点：波形每个**半格**采样一次，用 ▀ / ▄ / █ 三个字符表达上/下半格，
-- 于是竖直方向的解析度是字符格的两倍——曲线才不会像楼梯。噪声用两个正弦
-- 叠加（确定性、不依赖随机数），锁相后噪声项按 lock 衰减到 0。

local W, H = 80, 45
local PX, PY, PW, PH = 6, 8, 68, 24  -- 示波器绘图区

-- 文案按界面语言给（启动动画跑在完整 API 沙箱里，取值走 phos.lang）
local Text = {
  zh = { title = "示波器", calibrating = "校正中", locked = "锁定", chan = "通道 A" },
  en = { title = "OSCILLOSCOPE", calibrating = "CALIBRATING", locked = "LOCKED", chan = "CH A" },
}
local L = phos.lang.dict(Text)

local t = 0
local clicked, chimed = false, false

local function lock()                       -- 锁相进度：0.45s 起、2.3s 满
  local p = (t - 0.45) / 1.85
  if p < 0 then return 0 end
  if p > 1 then return 1 end
  return p * p * (3 - 2 * p)                -- 平滑起步与收尾
end

-- 采样：返回值 ∈ [-1,1]；x 用**半格**为单位，所以整格精度是它的两倍
local function sample(x)
  local clean = math.sin(x * 0.22 + t * 2.2) * 0.62 + math.sin(x * 0.66 + t * 2.2) * 0.22
  local noisy = math.sin(x * 1.7 + t * 11.0) * 0.55 + math.sin(x * 3.9 + t * 17.0) * 0.35
  local k = lock()
  return clean * (0.35 + 0.65 * k) + noisy * (1 - k) * 0.9
end

function update(dt)
  t = t + dt

  if not clicked and t > 0.35 then
    clicked = true
    phos.audio.beep(70, 0.4, { wave = "saw", sweep = 420, volume = 0.14, release = 0.15 })
  end
  if not chimed and lock() >= 1 then
    chimed = true
    phos.audio.note("A4", { wave = "square", dur = 0.09, volume = 0.16 })
    phos.audio.note("E5", { wave = "square", dur = 0.16, volume = 0.18 })
    phos.audio.perc("H")
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  -- 栅格：每 4 半格（= 2 格）一条点线，中线用实线
  local mid = PY + PH // 2
  for y = PY, PY + PH do
    for x = PX, PX + PW - 1 do
      local on = ((y - PY) % 4 == 0) and ((x - PX) % 4 == 0)
      if on then S.put(x, y, "·", C.dark_gray) end
    end
  end
  for x = PX, PX + PW - 1 do
    S.put(x, mid, "-", C.dark_gray)
  end

  -- 波形：逐列取两个半格采样，用 ▀ / ▄ / █ 表达到半格精度
  local prev = nil
  for x = 0, PW - 1 do
    local v1 = sample(x * 2)
    local v2 = sample(x * 2 + 1)
    local y1 = mid - math.floor(v1 * (PH // 2 - 1) + 0.5)
    local y2 = mid - math.floor(v2 * (PH // 2 - 1) + 0.5)
    local lo, hi = math.min(y1, y2), math.max(y1, y2)
    local col = (lock() >= 1) and C.green or C.yellow
    for y = lo, hi do
      local top_half = (y == hi)
      local bot_half = (y == lo)
      local ch = (top_half and bot_half) and "█" or (top_half and "▀" or "▄")
      if y >= PY and y <= PY + PH then S.put(PX + x, y, ch, col) end
    end
    prev = v2
  end

  -- 游标：沿波推进的采样头，不画在波形上时也留一个刻度
  local cx = PX + (math.floor(t * 26) % PW)
  local cy = mid - math.floor(sample(cx - PX) * (PH // 2 - 1) + 0.5)
  for y = PY, PY + PH do
    if y ~= cy then S.put(cx, y, ":", C.dark_gray) end
  end
  S.put(cx, cy, "+", C.white)

  -- 读数：标题 / 通道 / 频率 / 状态
  S.print(PX, 2, L.title, C.green)
  S.print(PX, 4, L.chan, C.gray)
  local hz = 100 + math.floor(lock() * 340)
  S.print(PX + 40, 2, string.format("%4d Hz", hz), C.white)
  local state = (lock() >= 1) and L.locked or L.calibrating
  local sc = (lock() >= 1) and C.green or C.yellow
  S.print(PX + 40, 4, state, sc)

  -- 底部进度：锁相完成度（也是"信号质量"）
  local pct = math.floor(lock() * 100)
  local w = 40
  for i = 0, w - 1 do
    local on = i < math.floor(lock() * w)
    S.put(PX + 2 + i, H - 5, on and "#" or "-", on and C.green or C.dark_gray)
  end
  S.print(PX + 2 + w + 2, H - 5, string.format("%3d%%", pct), C.gray)
end

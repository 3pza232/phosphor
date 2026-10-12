-- STARDUST：漫天星辰向心汇聚成一颗"星滴"，坠落水面溅起涟漪，产品名自水面浮起
--
-- 时间线：
--   0.0~1.5s  星点从四面八方收向中央上方，逐渐合成一颗星滴
--   1.5~2.1s  星滴坠落，触到水面
--   2.1s~     水面扩散同心涟漪；产品名在涟漪中央浮现
-- 分工：状态只在 update 推进（坠落进度、涟漪的出生与扩散），draw 只按当前状态作画（dt 不进 draw）
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "召星" }, en = { title = "STARFALL" } }
local L = phos.lang.dict(TXT)

local CX = W // 2
local GATHER_Y = 8
local WATER_Y = H // 2 + 3
local GATHER_T, DROP_T, REVEAL_T = 1.5, 2.1, 2.4

local stars = {}
for i = 1, 64 do
  stars[i] = { a = phos.sys.random(0, 628) / 100, r0 = phos.sys.random(14, 60) }
end

local ripples = {}
local splashed, next_ripple = false, 0

local function ring(S, cx, cy, r, col)
  local n = math.max(10, math.floor(5.0 * r))
  for k = 0, n - 1 do
    local a = 2 * math.pi * k / n
    local x = math.floor(cx + r * math.cos(a) + 0.5)
    local y = math.floor(cy + r * math.sin(a) * 0.4 + 0.5)  -- 水面视角：纵向压扁
    if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, "~", col) end
  end
end

function update(dt)
  t = t + dt
  if not splashed and t >= DROP_T then
    splashed = true
    phos.audio.note("A3", { wave = "sine", dur = 0.5, sweep = 880, volume = 0.14 })
  end
  -- 触水后每 0.1s 补一圈新涟漪
  if splashed and t >= next_ripple and #ripples < 5 then
    next_ripple = t + 0.1
    ripples[#ripples + 1] = { r = 2, age = 0 }
  end
  for i = #ripples, 1, -1 do
    local rp = ripples[i]
    rp.r = rp.r + 18 * dt
    rp.age = rp.age + dt
    if rp.r > math.max(W, H) * 0.7 then table.remove(ripples, i) end
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.dark_gray)

  if t < GATHER_T then
    -- 收拢阶段：半径随时间收缩，越近越亮
    local k = 1 - t / GATHER_T
    for _, s in ipairs(stars) do
      local r = s.r0 * k
      local x = math.floor(CX + r * math.cos(s.a) + 0.5)
      local y = math.floor(GATHER_Y + r * math.sin(s.a) * 0.5 + 0.5)
      if x >= 0 and x < W and y >= 0 and y < H then
        S.put(x, y, (r < 6) and "*" or ".", (r < 10) and C.white or C.cyan)
      end
    end
    S.put(CX, GATHER_Y, "*", C.white)
  else
    -- 星滴坠落
    local p = math.min(1, (t - GATHER_T) / (DROP_T - GATHER_T))
    local dy = math.floor(GATHER_Y + (WATER_Y - GATHER_Y) * p + 0.5)
    if t < DROP_T + 0.06 then S.put(CX, dy, "*", C.white) end

    -- 水面与涟漪
    for x = 6, W - 7 do S.put(x, WATER_Y, "-", C.dark_gray) end
    for _, rp in ipairs(ripples) do
      ring(S, CX, WATER_Y, rp.r, rp.age < 0.3 and C.cyan or C.blue)
    end
  end

  -- 产品名：涟漪散开后自水面浮起（逐列）
  local lit = math.floor((t - REVEAL_T) * 16)
  if lit > 0 then
    local lx = CX - #LOGO // 2
    for k = 1, math.min(lit, #LOGO) do
      S.put(lx + k - 1, WATER_Y - 2, LOGO:sub(k, k), C.white)
    end
  end
end

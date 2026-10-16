-- SONAR：深潜声呐开机动画
--
-- 时间线（duration = 6.4s；段与段之间用缓动 + 淡入淡出过渡，不硬切）：
--   0.0~1.9s  DIVE   下潜：海面微光收束变暗、水压渐暗、深度计缓出爬升、
--                     远海底剪影自暗处浮现、气泡上升
--   1.9~3.9s  PING   声呐脉冲：低频 ping + 同心环缓出外扩，回声逐圈
--                     点亮海底与机台轮廓（与下潜段交叠淡变）
--   3.9~4.9s  BIO    生物荧光：青绿光点由暗转亮、沉浮铺满前景
--   4.9~6.4s  REVEAL 揭露：产品名自深处缓出上浮、下划线自中心展开、
--                     副读数与深度/就绪读数淡入，收尾一记"就绪"和弦
-- 分层：背景（海雪 / 远海底剪影 / 光柱）+ 中景（舷窗弧 / 声呐栅格 / 海底与机台）
--       + 前景（气泡 / 生物荧光 / 产品名）
-- 音效：一组同调（A 大调）的有音高提示，绝不逐帧发声
-- 分工：状态只在 update 推进，draw 只按当前状态作画（dt 不进 draw）
local t = 0
duration = 6.4

local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end

local LOGO = phos.sys.product()
local SUB = "SONAR ARRAY ONLINE"           -- 副读数（技术读数，保持 ASCII）
local TXT = {
  zh = { title = "深渊声呐", diving = "下潜", ping = "声呐 PING",
         bio = "生物荧光", depth = "深度", ready = "就绪" },
  en = { title = "ABYSSAL SONAR", diving = "DIVING", ping = "SONAR PING",
         bio = "BIOLUMINESCENCE", depth = "DEPTH", ready = "READY" },
}
local L = phos.lang.dict(TXT)

local CX, CY = W // 2, H // 2
local PR = math.min(W, H) * 0.44               -- 舷窗半径
local DIVE_T, PING_T, BIO_T, REVEAL_T = 1.9, 1.9, 3.9, 4.9
local GROW = 24                                -- 声呐前缘扩散速度（格/秒）
local RMAX = math.sqrt(CX * CX + CY * CY) + 3
local TARGET_DEPTH = 3847

-- ---------------------------------------------------------------- 工具
local function rnd() return phos.sys.random(0, 999) / 1000 end
local function clamp01(v)
  if v ~= v then return 0 end                  -- NaN 保护
  return v < 0 and 0 or (v > 1 and 1 or v)
end
local function ease_out_cubic(x) local u = 1 - clamp01(x); return 1 - u * u * u end
local function smoothstep(a, b, x)
  if b == a then return x >= b and 1 or 0 end
  local u = clamp01((x - a) / (b - a)); return u * u * (3 - 2 * u)
end
local function in_circle(x, y, cx, cy, r)
  local dx, dy = x - cx, y - cy
  return dx * dx + dy * dy <= r * r
end
local function ring(S, cx, cy, r, ch, col)
  if r < 0.4 then return end
  local n = math.max(8, math.floor(6.0 * r))
  for k = 0, n - 1 do
    local a = 2 * math.pi * k / n
    local x = math.floor(cx + r * math.cos(a) + 0.5)
    local y = math.floor(cy + r * math.sin(a) + 0.5)
    if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, ch, col) end
  end
end
local function line(S, a, b, ch, col)          -- 通用画线（含竖线，供机台轮廓用）
  local x0, y0, x1, y1 = a.x, a.y, b.x, b.y
  local dx, dy = math.abs(x1 - x0), -math.abs(y1 - y0)
  local sx = x0 < x1 and 1 or -1
  local sy = y0 < y1 and 1 or -1
  local err = dx + dy
  while true do
    if x0 >= 0 and x0 < W and y0 >= 0 and y0 < H then S.put(x0, y0, ch, col) end
    if x0 == x1 and y0 == y1 then break end
    local e2 = 2 * err
    if e2 >= dy then err = err + dy; x0 = x0 + sx end
    if e2 <= dx then err = err + dx; y0 = y0 + sy end
  end
end

-- ---------------------------------------------------------------- 中景：海底与机台回声
local function floor_y(x)                      -- 平滑起伏的海底轮廓
  return H - 6 + 1.7 * math.sin(x * 0.10) + 1.0 * math.sin(x * 0.043 + 1.7)
end
local floor_top = {}                           -- 每列远海底剪影高度（背景）
for x = 0, W - 1 do floor_top[x] = math.floor(floor_y(x) + 0.5) end

local echoes = {}
do
  for x = 6, W - 7, 3 do
    echoes[#echoes + 1] = { x = x, y = floor_top[x], kind = "floor", seg = "floor" }
  end
  local bx0, by0 = W - 25, CY - 7
  local bx1, by1 = W - 11, CY + 5
  local function edge(x0, y0, x1, y1, seg)     -- 机台轮廓四边，按段打点
    local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
    for k = 0, n, 3 do
      local f = n == 0 and 0 or k / n
      echoes[#echoes + 1] = { x = math.floor(x0 + (x1 - x0) * f + 0.5),
                              y = math.floor(y0 + (y1 - y0) * f + 0.5),
                              kind = "obj", seg = seg }
    end
  end
  edge(bx0, by0, bx1, by0, "top")
  edge(bx1, by0, bx1, by1, "right")
  edge(bx1, by1, bx0, by1, "bot")
  edge(bx0, by1, bx0, by0, "left")
end
for _, e in ipairs(echoes) do
  local dx, dy = e.x - CX, e.y - CY
  e.dist = math.sqrt(dx * dx + dy * dy)
  e.lit = false
end

-- ---------------------------------------------------------------- 背景 / 前景粒子
local snow = {}                                -- 海雪：极细的背景悬浮颗粒，缓慢下沉
for i = 1, 54 do
  snow[i] = { x = rnd() * (W - 1), y = rnd() * (H - 1), spd = 0.15 + rnd() * 0.5,
              lum = rnd() }
end
local bio = {}                                 -- 生物荧光光点（青绿沉浮）
for i = 1, 48 do
  bio[i] = { x = rnd() * (W - 1), y = rnd() * (H - 1), spd = 0.4 + rnd() * 1.0,
             amp = 0.6 + rnd() * 1.8, ph = rnd() * 6.283, warm = rnd() < 0.5 }
end
local bubbles = {}

-- ---------------------------------------------------------------- 状态与音效调度
local front_r, pinged, revealed, locked = 0, false, false, false
local next_bub = 0
local echo_marks = { { r = 13, played = false }, { r = 25, played = false },
                     { r = 37, played = false } }
local echo_notes = { "A3", "C#4", "E4" }       -- 回声中高：A 大三和弦
local snd_dive, snd_bio = false, false

function update(dt)
  t = t + dt

  -- 下潜低鸣（A 大调基音，一次）
  if not snd_dive and t >= 0.25 then
    snd_dive = true
    phos.audio.note("A2", { wave = "triangle", dur = 1.4, volume = 0.06, release = 0.9 })
  end

  -- 声呐 ping：低频主音 + 一层次低音（同一次触发，绝不逐帧）
  if not pinged and t >= PING_T then
    pinged = true
    phos.audio.note("A2", { wave = "sine", dur = 0.9, sweep = 82, volume = 0.20, release = 0.6 })
    phos.audio.note("A1", { wave = "triangle", dur = 1.1, volume = 0.07, release = 0.8 })
  end
  if t >= PING_T then front_r = math.min((t - PING_T) * GROW, RMAX) end

  -- 回声：前缘扫过标记半径，依次奏出 A 大调三和弦（每圈一次）
  if pinged then
    for i, m in ipairs(echo_marks) do
      if not m.played and front_r >= m.r then
        m.played = true
        phos.audio.note(echo_notes[i], { wave = "sine", dur = 0.18, volume = 0.05, release = 0.12 })
      end
    end
  end

  -- 前缘扫过回声目标即点亮（纯视觉，回音由上面的和弦代表）
  if pinged and front_r > 0 then
    for _, e in ipairs(echoes) do
      if not e.lit and front_r >= e.dist then e.lit = true end
    end
  end

  -- 气泡：下潜段与揭露段各自冒泡（纯视觉，不发声）
  if (t < DIVE_T or revealed) and t >= next_bub then
    next_bub = t + 0.20 + rnd() * 0.22
    local bx = (t < DIVE_T) and (CX + (rnd() * 2 - 1) * PR * 0.7) or (10 + rnd() * (W - 20))
    local by = (t < DIVE_T) and (CY + PR * 0.4) or (H - 2 - rnd() * 3)
    bubbles[#bubbles + 1] = { x = bx, y = by, spd = 3 + rnd() * 5,
                              sway = rnd() * 2 - 1, ph = rnd() * 6.283 }
  end
  for i = #bubbles, 1, -1 do
    local b = bubbles[i]
    b.y = b.y - b.spd * dt
    b.x = b.x + math.sin(t * 2 + b.ph) * b.sway * dt * 3
    if b.y < -1 or b.x < -1 or b.x > W then table.remove(bubbles, i) end
  end

  -- 海雪缓沉（环回）
  for _, s in ipairs(snow) do
    s.y = s.y + s.spd * dt
    if s.y > H - 0.5 then s.y = s.y - H end
  end

  -- 生物荧光：由暗转亮 + 上浮；一声极短的高频细响
  if not snd_bio and t >= BIO_T + 0.1 then
    snd_bio = true
    phos.audio.note("A5", { wave = "sine", dur = 0.08, volume = 0.04 })
    phos.audio.note("E6", { wave = "sine", dur = 0.06, volume = 0.035 })
  end
  if t >= BIO_T then
    for _, b in ipairs(bio) do
      b.y = b.y - b.spd * dt
      if b.y < 0 then b.y = H - 1 end
    end
  end

  -- 揭露：产品名上浮 + 收尾"就绪"和弦（A 大三和弦，三音错开一瞬）
  if not revealed and t >= REVEAL_T then revealed = true end
  if not locked and t >= REVEAL_T + 1.0 then
    locked = true
    phos.audio.note("A4", { wave = "sine", dur = 0.8, volume = 0.09, release = 0.5 })
    phos.audio.note("C#5", { wave = "sine", dur = 0.8, volume = 0.07, release = 0.5 })
    phos.audio.note("E5", { wave = "sine", dur = 0.9, volume = 0.06, release = 0.6 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  local dive = clamp01(t / DIVE_T)             -- 下潜进度
  local dark = ease_out_cubic(dive)            -- 水压渐暗

  -- ============================== 背景层 ==============================
  -- 海雪：越深越暗的悬浮微尘
  for _, s in ipairs(snow) do
    local x, y = math.floor(s.x + 0.5), math.floor(s.y + 0.5)
    if x >= 0 and x < W and y >= 0 and y < H then
      S.put(x, y, s.lum > 0.9 and "," or ".", C.dark_gray)
    end
  end

  -- 远海底剪影：随下潜渐显，作中景地形背后的暗层
  if dive > 0.12 then
    for x = 0, W - 1 do
      local y = floor_top[x]
      if y >= 0 and y < H then
        S.put(x, y, (x % 2 == 0) and "-" or "~", C.dark_gray)
      end
    end
  end

  -- 光柱：下潜段海面透下的数缕微光（随深度上移、收束、变暗）
  if t < PING_T + 0.4 then
    local shaft = (1 - smoothstep(PING_T - 0.6, PING_T + 0.4, t)) * (1 - 0.7 * dark)
    local surf = (CY - PR + 6) - dive * 5
    for x = 0, W - 1 do
      local yy = math.floor(surf + math.sin(x * 0.35 + t * 1.6) * 1.4 + 0.5)
      if shaft > 0.12 and in_circle(x, yy, CX, CY, PR - 1) then
        local col = shaft > 0.6 and C.cyan or (shaft > 0.3 and C.blue or C.dark_gray)
        S.put(x, yy, "~", col)
      end
    end
  end

  -- ============================== 中景层 ==============================
  -- 舷窗弧（下潜段；ping 时淡出，不硬切）
  local port = 1 - smoothstep(PING_T - 0.35, PING_T + 0.45, t)
  if port > 0.02 then
    ring(S, CX, CY, PR, "-", C.dark_gray)
    if port > 0.4 then ring(S, CX, CY, PR - 1.2, ".", C.dark_gray) end
    for k = 0, 7 do
      local a = k * math.pi / 4
      local x = math.floor(CX + (PR - 0.5) * math.cos(a) + 0.5)
      local y = math.floor(CY + (PR - 0.5) * math.sin(a) + 0.5)
      if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, "o", C.gray) end
    end
  end

  -- 声呐栅格（ping 段淡入，揭露前淡出）
  local grid = smoothstep(PING_T - 0.1, PING_T + 0.5, t) *
               (1 - smoothstep(REVEAL_T - 0.4, REVEAL_T + 0.4, t))
  if grid > 0.02 then
    for x = 0, W - 1, 4 do S.put(x, CY, ".", C.dark_gray) end
    for y = 0, H - 1, 3 do S.put(CX, y, ".", C.dark_gray) end
  end

  -- 海底 / 机台成像：点亮即常驻，回声点按段连线成轮廓
  if t >= PING_T then
    local prev = {}
    for _, e in ipairs(echoes) do
      if e.lit then
        if prev[e.seg] then
          line(S, prev[e.seg], e, e.kind == "floor" and "-" or ":", C.blue)
        end
        S.put(e.x, e.y, e.kind == "floor" and "=" or "+",
              e.kind == "floor" and C.cyan or C.gray)
        prev[e.seg] = e
      end
    end
  end

  -- 声呐同心环：前缘 + 两圈余波，揭露前淡出
  if t >= PING_T and t < REVEAL_T + 0.3 then
    local fade = 1 - smoothstep(REVEAL_T - 0.6, REVEAL_T + 0.3, t)
    local k = 0
    while front_r - k * 13 > 0.6 and k < 3 do
      local col = k == 0 and C.green or (k == 1 and C.cyan or C.dark_gray)
      ring(S, CX, CY, front_r - k * 13, ".", fade > 0.4 and col or C.dark_gray)
      k = k + 1
    end
  end

  -- ============================== 前景层 ==============================
  -- 生物荧光：由暗转亮 + 明暗呼吸
  if t >= BIO_T then
    local bio_i = smoothstep(BIO_T, BIO_T + 0.9, t)
    for _, b in ipairs(bio) do
      local x = math.floor(b.x + 0.5)
      local y = math.floor(b.y + math.sin(t * 1.5 + b.ph) * b.amp + 0.5)
      if x >= 0 and x < W and y >= 0 and y < H then
        local hot = bio_i * (0.5 + 0.5 * math.sin(t * 2.2 + b.ph))
        if hot > 0.72 then
          S.put(x, y, "*", b.warm and C.green or C.cyan)
        elseif hot > 0.34 then
          S.put(x, y, "+", b.warm and C.green or C.cyan)
        else
          S.put(x, y, ".", C.dark_gray)
        end
      end
    end
  end

  -- 气泡
  for _, b in ipairs(bubbles) do
    local x = math.floor(b.x + 0.5)
    local y = math.floor(b.y + 0.5)
    if x >= 0 and x < W and y >= 0 and y < H then
      S.put(x, y, b.spd > 6 and "o" or ".", C.gray)
    end
  end

  -- ============================== HUD ==============================
  S.print(3, 1, L.title, C.gray)
  local tag = (t < PING_T) and L.diving or (t < BIO_T and L.ping or (t < REVEAL_T and L.bio or L.ready))
  S.print(3, H - 2, tag, C.dark_gray)
  local depth = math.floor(TARGET_DEPTH * ease_out_cubic(dive) + 0.5)
  local ds = string.format("%s %4dm", L.depth, depth)
  S.print(math.max(3, W - phos.text.width(ds) - 3), 1, ds, t < REVEAL_T and C.cyan or C.gray)

  -- ============================== 产品名揭露 ==============================
  if t >= REVEAL_T then
    local rp = clamp01((t - REVEAL_T) / 1.0)
    local name_y = math.floor((H - 2) - ease_out_cubic(rp) * ((H - 2) - (CY - 3)) + 0.5)
    local lw = phos.text.width(LOGO)
    local lx = CX - lw // 2
    S.print(lx, name_y, LOGO, rp > 0.5 and C.white or C.gray)

    -- 下划线：自中心向两侧展开
    local up = ease_out_cubic(clamp01((t - REVEAL_T - 0.15) / 0.7))
    local half = math.floor(up * (lw // 2 + 1))
    for k = -half, half do
      local x = CX + k
      if x >= 0 and x < W then S.put(x, name_y + 1, "-", C.green) end
    end

    -- 副读数：打字机逐字显出
    local sw = phos.text.width(SUB)
    local sx = CX - sw // 2
    local np = math.floor(clamp01((t - REVEAL_T - 0.55) / 0.7) * sw + 0.5)
    if np > 0 then S.print(sx, name_y + 3, SUB:sub(1, np), C.cyan) end

    -- 深度 / 就绪读数（缓入）
    if t >= REVEAL_T + 0.75 then
      local readout = string.format("%s %dm    %s", L.depth, TARGET_DEPTH, L.ready)
      local rw = phos.text.width(readout)
      S.print(math.max(1, CX - rw // 2), name_y + 4, readout, C.green)
    end
  end
end

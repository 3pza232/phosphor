-- PULSE：脉冲校准台（同心环扩散/收束 + 雷达扫描线 + 火花 + 同步率 HUD）
--
-- 时间线：
--   0.0~2.0s  每 0.3s 从中心放出一圈正弦环，向外扩散、越远越暗；环上随机蹦出火花
--   2.0s~     新的环改为向内收束，把注意力压回中心
--   2.5s~     核心聚光 → 产品名亮起，同步率爬满
-- 分工：状态只在 update 推进，draw 只按当前状态作画（dt 不进 draw）
local t = 0
duration = 4.8               -- 本动画自报时长（秒）：环扩散 2s + 收束 + 锁定后留白欣赏
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "脉冲校准", sync = "同步" },
              en = { title = "PULSE ALIGN", sync = "SYNC" } }
local L = phos.lang.dict(TXT)

local CX, CY = W // 2, H // 2 + 1
local SPAWN = 0.30
local GATHER_T = 2.0
local R_MAX = math.max(W, H)
local rings, sparks = {}, {}
local next_spawn, locked = 0.0, false
local sync = 0                    -- 假装的"同步率"，随时间爬升

local function rnd() return phos.sys.random(0, 999) / 1000 end

-- 字符格是正方形（kCellPx 等宽等高），所以 x/y 用同一尺度才画得圆
local function ring(S, cx, cy, r, ch, col)
  local n = math.max(8, math.floor(6.0 * r))
  for k = 0, n - 1 do
    local a = 2 * math.pi * k / n
    local x = math.floor(cx + r * math.cos(a) + 0.5)
    local y = math.floor(cy + r * math.sin(a) + 0.5)
    if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, ch, col) end
  end
end

function update(dt)
  t = t + dt
  sync = math.min(100, sync + dt * (locked and 60 or 22))
  if t >= next_spawn then
    next_spawn = t + SPAWN
    rings[#rings + 1] = { r = 0.5, grow = (t < GATHER_T) and 26 or -32 }
    phos.audio.beep(300 + #rings * 24, 0.03, { wave = "sine", volume = 0.06 })
  end
  for i = #rings, 1, -1 do
    local rg = rings[i]
    rg.r = rg.r + rg.grow * dt
    if rnd() < 0.25 then                       -- 环上随机蹦出火花
      local a = rnd() * 2 * math.pi
      sparks[#sparks + 1] = { x = CX + rg.r * math.cos(a), y = CY + rg.r * math.sin(a),
                              vx = math.cos(a) * 6, vy = math.sin(a) * 6, life = 0.35 }
    end
    if rg.r < 0.5 or rg.r > R_MAX then table.remove(rings, i) end
  end
  for i = #sparks, 1, -1 do
    local s = sparks[i]
    s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
    s.life = s.life - dt
    if s.life <= 0 then table.remove(sparks, i) end
  end
  if not locked and t >= GATHER_T + 0.5 then
    locked = true
    phos.audio.note("E5", { wave = "sine", dur = 0.5, sweep = 1760, volume = 0.12 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.gray)
  if locked then
    S.print(math.max(3, W - 7), 1, "LOCKED", C.green)
  else
    S.print(math.max(3, W - 13), 1, string.format("%s %3d%%", L.sync, math.floor(sync)), C.dark_gray)
  end

  if not locked then
    -- 十字准星 + 雷达扫描线（锁定后撤掉，免得压住产品名）
    for x = 0, W - 1, 4 do S.put(x, CY, ".", C.dark_gray) end
    for y = 0, H - 1, 2 do S.put(CX, y, ".", C.dark_gray) end
    local rr = math.min(W, H) * 0.42
    for k = 0, 10 do
      -- 尾迹跟在亮头**后面**（a 随 k 递减）：原来写成 +k，拖尾跑到头前面去了
      local a = t * 1.6 - k * 0.06
      local x = math.floor(CX + rr * math.cos(a) + 0.5)
      local y = math.floor(CY + rr * math.sin(a) + 0.5)
      if x >= 0 and x < W and y >= 0 and y < H then
        S.put(x, y, k == 0 and "#" or "=", k == 0 and C.white or C.dark_gray)
      end
    end
  end

  for _, rg in ipairs(rings) do
    -- 环越大越暗：外圈是余波，内圈才是当前脉冲
    local col = rg.r > R_MAX * 0.6 and C.dark_gray or (rg.r > R_MAX * 0.3 and C.gray or C.green)
    ring(S, CX, CY, rg.r, ".", col)
  end
  for _, s in ipairs(sparks) do
    local x, y = math.floor(s.x + 0.5), math.floor(s.y + 0.5)
    if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, "+", C.yellow) end
  end

  if locked then
    -- 锁定态：杂讯收干净，核心亮一枚白点，产品名居中 + 一道绿色细下划线收尾
    S.put(CX, CY, "O", C.white)
    S.print(CX - #LOGO // 2, CY - 1, LOGO, C.white)
    local u = #LOGO // 2 + 3
    for x = CX - u, CX + u do S.put(x, CY + 1, "-", C.green) end
  else
    S.put(CX, CY, "+", C.green)
  end
end

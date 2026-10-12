-- PULSE：从中心扩散的同心环；环收束后，产品名在核心处亮起
--
-- 时间线：
--   0.0~2.0s  每 0.3s 从中心放出一圈正弦环，向外扩散、越远越暗
--   2.0s~     新的环改为向内收束，把注意力压回中心 → 定格打出产品名
-- 分工：状态只在 update 推进，draw 只按当前状态作画（dt 不进 draw）
local t = 0
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
local rings = {}
local next_spawn, locked = 0.0, false

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
  if t >= next_spawn then
    next_spawn = t + SPAWN
    rings[#rings + 1] = { r = 0.5, grow = (t < GATHER_T) and 26 or -32 }
    phos.audio.beep(300 + #rings * 24, 0.03, { wave = "sine", volume = 0.06 })
  end
  for i = #rings, 1, -1 do
    local rg = rings[i]
    rg.r = rg.r + rg.grow * dt
    if rg.r < 0.5 or rg.r > R_MAX then table.remove(rings, i) end
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

  for _, rg in ipairs(rings) do
    -- 环越大越暗：外圈是余波，内圈才是当前脉冲
    local col = rg.r > R_MAX * 0.6 and C.dark_gray or (rg.r > R_MAX * 0.3 and C.gray or C.green)
    ring(S, CX, CY, rg.r, ".", col)
  end
  S.put(CX, CY, "+", C.green)

  if locked then
    S.print(CX - #LOGO // 2, CY - 1, LOGO, C.white)
    S.print(CX - #L.sync // 2, CY + 2, L.sync, C.gray)
  end
end

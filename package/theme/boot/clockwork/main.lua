-- CLOCKWORK：上发条 → 齿轮咬合 → 走时 → 揭示
-- 段一 0.00~1.35s  上发条：发条螺旋由松到紧（慢起稳收），张力表随读数上升（棘轮连续哒哒）
-- 段二 1.15~2.70s  齿轮咬合：齿列按齿数比反向转起，啮合点齿入齿缝（低沉"喀"）
-- 段三 2.70~4.05s  走时：指针自零点 p² 加速扫过表盘刻度，落点带回弹锁定（清脆钟铃）
-- 段四 4.30s~     表盘中央开启，产品名自机芯中亮起 + 铜绿铭牌 + 收尾和音
--
-- 齿轮咬合（正确相位）：相邻两轮必须等"模数"（节圆齿距 = 2πr/N 相等），
-- 于是齿数正比于半径；啮合点处一齿入另一轮的齿缝。设 A 驱动 B、A 中心指向 B 中心的
-- 方位为 α，则 B 的相位 offset = α + π − pitch_B·(0.5 − α/pitch_A)，此后
-- B.rot = offset − (N_A/N_B)·(A.rot)：转速比严格反比，且始终差半个齿距（齿对缝）。
--
-- 齿轮画法（角度连续、不跳帧）：轮缘逐点采样成环；轮齿沿轮缘 N 个点、随 rot 一起转，
-- 取该点方向决定符号（近水平 "-"、近垂直 "|"、斜向按 dx·dy 定 "/" 或 "\"）；
-- 轮辐是过圆心的直径线，同样按方向挑符号。0 号齿用亮色标出，隔帧看相位在变。
local t = 0
local W, H = 80, 45
local TAU = math.pi * 2
local LOGO = phos.sys.product()

-- 文案：面向玩家的字都按语言给两列（缺 en 回落 zh）
local TXT = {
  zh = { title = "发条钟", winding = "上发条", meshing = "齿轮咬合", running = "走时",
         wound = "已上弦", wound_run = "已上弦 · 运转", tension = "张力" },
  en = { title = "CLOCKWORK", winding = "WINDING", meshing = "MESHING", running = "RUNNING",
         wound = "WOUND", wound_run = "WOUND · RUNNING", tension = "TENSION" },
}
local L = phos.lang.dict(TXT)

-- 表盘中心（产品名也在此揭秘）
local CX, CY = 40, 16
local DR = 12.5
-- 发条盒（左下）
local SPR_X, SPR_Y, SPR_R = 11, 21, 8
-- 时段
local WIND_END   = 1.35
local MESH_START = 1.15
local RUN_START  = 2.70
local LOCK_T     = 4.05
local REVEAL_T   = 4.30

-- 小工具
local function clamp01(x) if x < 0 then return 0 elseif x > 1 then return 1 else return x end end
local function lerp(a, b, u) return a + (b - a) * u end
local function smooth(x) x = clamp01(x); return x * x * (3 - 2 * x) end
local function ease_out(x) x = clamp01(x); return 1 - (1 - x) * (1 - x) end
local function px(v) return math.floor(v + 0.5) end
local function inb(x, y) return x >= 0 and x < W and y >= 0 and y < H end
local function colof(C, name)
  if name == "yellow" then return C.yellow elseif name == "cyan" then return C.cyan
  elseif name == "red" then return C.red elseif name == "white" then return C.white
  elseif name == "gray" then return C.gray elseif name == "dark_gray" then return C.dark_gray
  else return C.green end
end
local function dir_char(dx, dy)
  local ax, ay = math.abs(dx), math.abs(dy)
  if ax > ay * 1.6 then return "-" end
  if ay > ax * 1.6 then return "|" end
  if dx * dy > 0 then return "\\" end
  return "/"
end

-- 齿列：三只啮合轮（居中在表盘下方），逐级反向、转速比 = 齿数反比
-- 模数统一为 π：N = 2r ⇒ 节圆齿距相等，方可咬合
local train = {
  { cx = 28, cy = 35, r = 7, teeth = 14, col = "green",  spokes = 4, born = 0.55 },
  { cx = 40, cy = 35, r = 5, teeth = 10, col = "yellow", spokes = 3, born = 0.80 },
  { cx = 49, cy = 35, r = 4, teeth = 8,  col = "cyan",   spokes = 3, born = 1.00 },
}
-- 啮合相位：以 A.rot = 0 为参考求 B 的 offset
local function mesh_offset(A, B)
  local alpha = math.atan(B.cy - A.cy, B.cx - A.cx)
  local pA, pB = TAU / A.teeth, TAU / B.teeth
  return alpha + math.pi - pB * (0.5 - alpha / pA)
end
for i = 1, #train do train[i].rot = 0 end
for i = 2, #train do
  local a, b = train[i - 1], train[i]
  b.offset = mesh_offset(a, b)
  b.ratio = a.teeth / b.teeth          -- 转速比 = 齿数反比
end
local drive = 0                        -- 主动轮（齿列第一只）的累计转角

local next_click = 0
local fired = {}
local function once(key, fn) if not fired[key] then fired[key] = true; fn() end end

-- 上发条量：慢起稳收（smoothstep），末段带极小的过冲回弹（棘爪咬住）
local function wind_amount()
  local s = smooth(t / WIND_END)
  if t > WIND_END then
    local q = t - WIND_END
    s = 1 - 0.03 * math.exp(-16 * q) * math.abs(math.sin(q * 42))
  end
  return s
end

-- 一只齿轮
local function draw_gear(S, C, g)
  local col = colof(C, g.col)
  local rim = C.dark_gray
  -- 轮缘环
  local n = math.max(36, g.teeth * 3)
  for k = 0, n - 1 do
    local a = TAU * k / n
    local x, y = px(g.cx + g.r * math.cos(a)), px(g.cy + g.r * math.sin(a))
    if inb(x, y) then S.put(x, y, ".", rim) end
  end
  -- 轮齿：沿轮缘两格，0 号齿用亮色标相位
  for k = 0, g.teeth - 1 do
    local a = g.rot + TAU * k / g.teeth
    local ca, sa = math.cos(a), math.sin(a)
    local key = (k == 0)
    local ch = key and "#" or dir_char(ca, sa)
    local cc = key and C.white or col
    for rr = g.r + 0.5, g.r + 1.5 do
      local x, y = px(g.cx + rr * ca), px(g.cy + rr * sa)
      if inb(x, y) then S.put(x, y, ch, cc) end
    end
  end
  -- 轮毂环
  for k = 0, 11 do
    local a = TAU * k / 12
    local x, y = px(g.cx + 2.2 * math.cos(a)), px(g.cy + 2.2 * math.sin(a))
    if inb(x, y) then S.put(x, y, ".", rim) end
  end
  -- 轮辐（随 rot 旋转）
  for s = 0, g.spokes - 1 do
    local a = g.rot + TAU * s / g.spokes
    local ca, sa = math.cos(a), math.sin(a)
    local ch = dir_char(ca, sa)
    for rr = 2, g.r - 1 do
      local x, y = px(g.cx + rr * ca), px(g.cy + rr * sa)
      if inb(x, y) then S.put(x, y, ch, col) end
    end
  end
  S.put(px(g.cx), px(g.cy), "@", C.gray)   -- 轴心
end

-- 发条螺旋：圈数随 wind 由松盘到紧，半径线性张开（阿基米德螺线）
local function draw_spring(S, C, wind)
  local turns = 1.6 + wind * 2.2
  local n = math.max(28, math.floor(turns * 30))
  local col = wind > 0.66 and C.yellow or (wind > 0.33 and C.gray or C.dark_gray)
  for i = 0, n do
    local u = i / n
    local a = u * turns * TAU + wind * 5.0     -- 盘紧时整体旋进，像被拧动
    local r = 1.4 + (SPR_R - 1.4) * u
    local x, y = px(SPR_X + r * math.cos(a)), px(SPR_Y + r * math.sin(a))
    if inb(x, y) then S.put(x, y, "*", col) end
  end
  S.put(SPR_X, SPR_Y, "@", C.gray)
end

-- 右侧竖直张力表（含刻度与读数）
local function draw_gauge(S, C, wound)
  local bx, by, bh = 74, 9, 26
  S.put(bx, by - 1, "+", C.gray)
  for i = 0, bh - 1 do
    local frac = 1 - i / (bh - 1)
    local on = frac <= wound
    local major = (i % 5 == 0)
    S.put(bx, by + i, on and "|" or (major and "-" or "."),
                          on and C.yellow or C.dark_gray)
  end
  S.put(bx, by + bh, "+", C.gray)
  S.print(bx - 2, by + bh + 2, L.tension, C.gray)
  S.print(bx - 1, by + bh + 3, string.format("%3d%%", math.floor(wound * 100 + 0.5)), C.white)
end

-- 表盘：60 格刻度，5 格一个长刻度；appear 控制"化作"进度（12 点起顺时针描出）
local function draw_dial(S, C, appear)
  for k = 0, 59 do
    local u = k / 60
    if u <= appear then
      local a = -math.pi / 2 + TAU * u
      local major = (k % 5 == 0)
      local rr = major and DR or (DR - 1)
      local x, y = px(CX + rr * math.cos(a)), px(CY + rr * math.sin(a))
      if inb(x, y) then S.put(x, y, major and "+" or ".", major and C.gray or C.dark_gray) end
    end
  end
  -- 四方位罗马位（单字，刻画更精细；贴近轮缘，避开中央开启区）
  local marks = { { 0, "XII" }, { 3, "III" }, { 6, "VI" }, { 9, "IX" } }
  for _, m in ipairs(marks) do
    local a = -math.pi / 2 + TAU * m[1] / 12
    local rr = DR - 2
    local x = px(CX + rr * math.cos(a) - phos.text.width(m[2]) / 2)
    local y = px(CY + rr * math.sin(a))
    if inb(x, y) then S.print(x, y, m[2], C.gray) end
  end
end

-- 一根指针：正方向长身 + 反方向配重尾巴；tip 处点一个亮头
local function draw_hand(S, C, ang, len, col, tip_col)
  local ca, sa = math.cos(ang), math.sin(ang)
  local ch = dir_char(ca, sa)
  for r = 1, len do
    local x, y = px(CX + r * ca), px(CY + r * sa)
    if inb(x, y) then S.put(x, y, ch, col) end
  end
  for r = 1, math.floor(len * 0.3) do
    local x, y = px(CX - r * ca), px(CY - r * sa)
    if inb(x, y) then S.put(x, y, ch, C.dark_gray) end
  end
  local tx, ty = px(CX + (len + 1) * ca), px(CY + (len + 1) * sa)
  if inb(tx, ty) then S.put(tx, ty, "#", tip_col) end
end

-- 揭秘：表盘中央开启 + 铜绿铭牌 + 名号逐字印出 + 扩散环
local function draw_reveal(S, C)
  local op = clamp01((t - REVEAL_T) / 0.55)
  local lw = phos.text.width(LOGO)
  local bw = lw + 8
  local bx = CX - bw // 2
  local by = CY
  -- 扩散环（先画，被铭牌压住中心）
  local rr = 3 + ease_out(op) * 12
  for k = 0, 27 do
    local a = TAU * k / 28
    local x, y = px(CX + rr * math.cos(a)), px(CY + rr * math.sin(a))
    if inb(x, y) then S.put(x, y, ".", C.cyan) end
  end
  -- 中央开启：表盘面裂开一缝，清出铭牌位
  S.fill(bx, by - 1, bw, 3, " ", C.white, C.black)
  -- 铭牌边框（铜绿呼吸）+ 四角铆钉
  local flash = math.floor((t - REVEAL_T) * 8) % 2 == 0
  local bcol = flash and C.cyan or C.green
  S.print(bx, by - 1, "+" .. string.rep("-", bw - 2) .. "+", bcol, C.black)
  S.print(bx, by + 1, "+" .. string.rep("-", bw - 2) .. "+", bcol, C.black)
  S.put(bx, by, "|", bcol, C.black); S.put(bx + bw - 1, by, "|", bcol, C.black)
  S.put(bx, by - 1, "o", C.cyan); S.put(bx + bw - 1, by - 1, "o", C.cyan)
  S.put(bx, by + 1, "o", C.cyan); S.put(bx + bw - 1, by + 1, "o", C.cyan)
  -- 产品名自左向右印出（擦写光标停在字尾）
  local shown = math.floor(op * (lw + 0.99))
  local part = LOGO:sub(1, shown)
  local lpad = (bw - 2 - lw) // 2
  S.print(bx + 1, by, string.rep(" ", lpad) .. part, C.white, C.black)
  if op < 1 then
    local cx = bx + 1 + lpad + phos.text.width(part)
    if inb(cx, by) then S.put(cx, by, "|", C.yellow, C.black) end
  end
  -- 状态行
  if op >= 0.55 then
    local st = L.wound_run
    S.print(CX - phos.text.width(st) // 2, by + 3, st, C.cyan, C.black)
  end
end

function update(dt)
  t = t + dt

  -- 齿轮：主动轮积分转角，从动轮按严格反比的相位跟随
  local spin = smooth((t - MESH_START) / 0.55)
  drive = drive + 3.1 * spin * dt
  train[1].rot = drive
  for i = 2, #train do
    local g = train[i]
    g.rot = g.offset - drive * g.ratio
  end

  -- 上发条：棘轮连续哒哒（按间隔触发，末段更密）
  if t < WIND_END and t >= next_click then
    local w = clamp01(t / WIND_END)
    next_click = t + lerp(0.088, 0.052, w)
    phos.audio.beep(1500 + math.floor(700 * w), 0.012,
                    { wave = "noise", volume = 0.04, release = 0.012 })
  end
  -- 齿轮咬合：低沉"喀"（G 音，承接结尾的 C 大调）
  if t >= MESH_START then
    once("mesh", function()
      phos.audio.beep(98, 0.26, { wave = "square", sweep = 49, volume = 0.18, release = 0.16 })
      phos.audio.perc("K")
    end)
  end
  -- 锁定：清脆钟铃（C 大调琶音）
  if t >= LOCK_T then
    once("lock", function()
      phos.audio.note("C5", { wave = "square", dur = 0.06, volume = 0.15 })
      phos.audio.note("E5", { wave = "square", dur = 0.06, volume = 0.15 })
      phos.audio.note("G5", { wave = "square", dur = 0.08, volume = 0.16 })
      phos.audio.note("E6", { wave = "sine", dur = 0.70, volume = 0.11, release = 0.60 })
    end)
  end
  -- 收尾和音：C 大调和弦（与钟铃同调）
  if t >= REVEAL_T then
    once("reveal", function()
      for _, n in ipairs({ "C4", "E4", "G4", "C5" }) do
        phos.audio.note(n, { wave = "sine", dur = 1.0, volume = 0.09, release = 0.9 })
      end
    end)
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  -- 顶部标题 + 当前段状态（切段时短暂闪白，作过渡）
  S.print(2, 1, L.title, C.gray)
  local cap, capcol, seg_start
  if t < WIND_END then cap, capcol, seg_start = L.winding, C.yellow, 0
  elseif t < RUN_START then cap, capcol, seg_start = L.meshing, C.yellow, MESH_START
  elseif t < LOCK_T then cap, capcol, seg_start = L.running, C.green, RUN_START
  else cap, capcol, seg_start = L.wound, C.green, LOCK_T end
  if t - seg_start < 0.25 then capcol = C.white end
  S.print(W - phos.text.width(cap) - 2, 1, cap, capcol)

  local wind = wind_amount()
  draw_spring(S, C, wind)
  draw_gauge(S, C, wind)

  -- 表盘在走时前 0.6s 起从 12 点顺时针"化作"，作段落过渡
  local appear = smooth((t - (RUN_START - 0.6)) / 0.6)
  if appear > 0 then draw_dial(S, C, appear) end

  -- 齿列（表盘下方，机芯）
  for i = 1, #train do
    local g = train[i]
    if t >= g.born then draw_gear(S, C, g) end
  end
  -- 表盘中心到齿列的短连杆（暗示机芯驱动指针）
  if appear > 0.5 then
    for y = CY + 6, 33 do
      if (y % 2 == 0) then S.put(CX, y, ":", C.dark_gray) end
    end
  end

  -- 走时：指针自零点 p² 加速扫过，落点带回弹；锁定后轻微顿挫
  if t >= RUN_START then
    local raw = clamp01((t - RUN_START) / (LOCK_T - RUN_START))
    local e = raw * raw
    if t >= LOCK_T then
      local q = t - LOCK_T
      e = 1 + 0.035 * math.exp(-10 * q) * math.sin(q * 38)
    end
    local ang = -math.pi / 2 + TAU * 2 * e
    local locked = t >= LOCK_T
    local tick = locked and (math.floor((t - LOCK_T) * 8) % 2 == 0) and C.red or C.white
    draw_hand(S, C, -math.pi / 2 + (ang + math.pi / 2) / 12, 6, C.gray, C.gray)  -- 短针（1/12 速）
    draw_hand(S, C, ang, 10, C.yellow, tick)                                     -- 长针（走时主针）
    S.put(CX, CY, "@", C.white)                                                  -- 中心帽
  end

  if t >= REVEAL_T then draw_reveal(S, C) end
end

duration = 5.4   -- 本动画自报时长（秒）

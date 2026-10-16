-- CALLIGRAPHY：翰墨——毛笔在宣纸上逐笔书写产品名，由湿到干、落印成篇
--
-- 时间线（时长自报；笔速不匀——起笔/收笔各一顿，字与字之间留呼吸）：
--   ~0.06s         卷轴自上而下展开（沙沙）；砚台落墨、墨点晕开
--   WRITE0~        笔尖逐笔书写产品名（湿→干：实块→半干→细线；笔周围洇出墨晕）
--   写完 + 一小息   朱砂印章盖下：落章一"顿" + 红晕，朱底阴文清晰
--   再 + 一小息     墨香提示 + 读数 INK DRY · READY，纸角微卷
--
-- 实现要点：开写前先把"书写计划"摊平——每个字的每一笔、每一格都带一个
--   绝对落墨时刻（含起/收笔的顿与笔间、字间的停留）。于是"节奏"与"由湿到干"
--   都只由这张时刻表 + 一个指数衰减决定，不需要任何逐帧补间。
--   分工：状态只在 update 推进，draw 只按当前状态（t 与 ink 表）作画。
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()

-- 文案 zh/en 双语：缺 en 自动回落中文（见 api-reference 的 phos.lang）
local TXT = {
  zh = { title = "翰墨", ready = "墨已干 · 就绪", scent = "墨香" },
  en = { title = "CALLIGRAPHY", ready = "INK DRY · READY", scent = "INK SCENT" },
}
local L = phos.lang.dict(TXT)

-- 5x7 点阵字形（产品名只用到 P H O S R）；每字拆成若干条连续笔画——
-- 笔画内按格顺序落墨，于是书写是连贯的一笔，而不是整字一起蹦出来
local GLYPH = {
  P = {
    { {0,0},{0,1},{0,2},{0,3},{0,4},{0,5},{0,6} },               -- 竖
    { {1,0},{2,0},{3,0},{3,1},{3,2},{2,3},{1,3} },               -- 上半围
  },
  H = {
    { {0,0},{0,1},{0,2},{0,3},{0,4},{0,5},{0,6} },               -- 左竖
    { {4,0},{4,1},{4,2},{4,3},{4,4},{4,5},{4,6} },               -- 右竖
    { {1,3},{2,3},{3,3} },                                       -- 横档
  },
  O = {
    { {1,0},{2,0},{3,0},{4,1},{4,2},{4,3},{4,4},{4,5},{3,6},{2,6},{1,6},{0,5},{0,4},{0,3},{0,2},{0,1} },
  },
  S = {
    { {4,0},{3,0},{2,0},{1,0},{0,1},{0,2},{1,3},{2,3},{3,3},{4,4},{4,5},{3,6},{2,6},{1,6},{0,6} },
  },
  R = {
    { {0,0},{0,1},{0,2},{0,3},{0,4},{0,5},{0,6} },               -- 竖
    { {1,0},{2,0},{3,0},{4,1},{4,2},{3,3},{2,3},{1,3} },         -- 上半围
    { {2,4},{3,5},{4,6} },                                       -- 右撇
  },
}

local PITCH = 6
local WORD_W = #LOGO * PITCH - 1
local OX, OY = (W - WORD_W) // 2, 15

-- 书写计划：每格带绝对落墨时刻。起笔/收笔各顿一下（更慢），笔与笔、字与字
-- 之间留白——于是书写不匀速、有呼吸；已写完的字会随时间由湿转干。
local PLAN, NCELL = {}, 0
local WRITE0 = 1.15
do
  local clock = WRITE0
  local head_dwell, tail_dwell, mid = 0.030, 0.024, 0.013
  local stroke_gap, glyph_gap = 0.030, 0.090
  local first_glyph = true
  for i = 1, #LOGO do
    local g = GLYPH[LOGO:sub(i, i)]
    if g then
      if not first_glyph then clock = clock + glyph_gap end
      first_glyph = false
      local ox = OX + (i - 1) * PITCH
      for si, stroke in ipairs(g) do
        if si > 1 then clock = clock + stroke_gap end
        local n = #stroke
        for ci, c in ipairs(stroke) do
          clock = clock + ((ci == 1) and head_dwell or (ci == n and tail_dwell or mid))
          NCELL = NCELL + 1
          PLAN[NCELL] = { x = ox + c[1], y = OY + c[2], at = clock,
                          head = (ci == 1), tail = (ci == n) }
        end
      end
    end
  end
end
local WRITE_END = (PLAN[NCELL] and PLAN[NCELL].at) or WRITE0

-- 关键节点（段与段之间留呼吸，不硬切）
local ROLL_T   = 0.06
local INK_DROP = 0.62
local INK_HIT  = 0.88
local SEAL_T   = WRITE_END + 0.42
local READY_T  = SEAL_T + 0.62
local SEAL_X, SEAL_Y = 52, 24                     -- 印章左上角（8x8）
duration = READY_T + 1.35

-- 印章阴文（# = 朱底，. = 刻出的纸色）：朱文边框 + 回纹，四边清晰
local SEAL_INK = {
  "########", "#......#", "#.####.#", "#.#..#.#",
  "#.#..#.#", "#.####.#", "#......#", "########",
}

-- 墨迹表：ink[y][x] = 落墨时刻
local ink = {}
local revealed = 0
local rolled, dropped, hit, sealed, done = false, false, false, false, false

-- ---------------------------------------------------------------- 小工具
local function clamp01(v)
  if v ~= v then return 0 end                   -- NaN 保护
  return v < 0 and 0 or (v > 1 and 1 or v)
end
local function ease_out(x) local u = 1 - clamp01(x); return 1 - u * u end
local function hash(x, y) return ((x * 73856093 + y * 19349663) % 997) / 997 end
local function put_if(S, x, y, ch, col)
  if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, ch, col) end
end
local function ring(S, cx, cy, r, col, ch, squash)
  if r < 0.5 then return end
  squash = squash or 0.5                        -- 俯视：纵向压扁
  local n = math.max(8, math.floor(5.0 * r))
  for k = 0, n - 1 do
    local a = 2 * math.pi * k / n
    put_if(S, math.floor(cx + r * math.cos(a) + 0.5),
              math.floor(cy + r * math.sin(a) * squash + 0.5), ch or ".", col)
  end
end

local function reveal_until(n, now)
  while revealed < n and revealed < NCELL do
    revealed = revealed + 1
    local c = PLAN[revealed]
    if c then
      ink[c.y] = ink[c.y] or {}
      ink[c.y][c.x] = now
      if c.head then
        -- 每笔起手的一声轻擦：一笔一声（不是每格），音量极轻、频率微变
        phos.audio.beep(290 + phos.sys.random(0, 130), 0.025,
                        { wave = "noise", volume = 0.035, release = 0.02 })
      end
    end
  end
end

-- ---------------------------------------------------------------- update
function update(dt)
  if dt ~= dt or dt < 0 then dt = 0 end
  t = t + dt

  if not rolled and t >= ROLL_T then              -- 卷轴沙沙
    rolled = true
    phos.audio.beep(1400, 0.60, { wave = "noise", volume = 0.045,
                                  attack = 0.18, release = 0.40 })
  end
  if not dropped and t >= INK_DROP then           -- 墨点离砚
    dropped = true
    phos.audio.beep(2100, 0.05, { wave = "noise", volume = 0.05 })
  end
  if not hit and t >= INK_HIT then                -- 墨点落砚：低频闷响
    hit = true
    phos.audio.beep(128, 0.22, { wave = "sine", sweep = 66, volume = 0.12 })
  end

  if t >= WRITE0 then
    -- 逐格推进：表按时刻有序，二分找最后一个 at<=t 的格，避免每帧遍历
    local target, lo, hi = 0, 1, NCELL
    while lo <= hi do
      local m = (lo + hi) // 2
      if PLAN[m].at <= t then target = m; lo = m + 1 else hi = m - 1 end
    end
    reveal_until(target, t)
  end

  if not sealed and t >= SEAL_T then              -- 印章：咚 + 低频落纸
    sealed = true
    phos.audio.perc("K")
    phos.audio.beep(92, 0.22, { wave = "sine", sweep = 52, volume = 0.16 })
  end

  if not done and t >= READY_T then               -- 收尾：安稳的和弦（A 大三，错开一瞬）
    done = true
    phos.audio.note("A4",  { wave = "triangle", dur = 0.14, volume = 0.09 })
    phos.audio.note("C#5", { wave = "triangle", dur = 0.16, volume = 0.09 })
    phos.audio.note("E5",  { wave = "sine", dur = 0.42, volume = 0.11, release = 0.26 })
  end
end

-- ---------------------------------------------------------------- draw
function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  -- === 卷轴：宣纸自上而下铺开（缓出） ===
  local u = ease_out(t / 1.10)
  local half = math.floor(u * 19 + 0.5)
  local topE, botE = H // 2 - half, H // 2 + half
  if half > 4 then
    for y = topE + 1, botE - 1 do
      for x = 1, W - 2 do
        if ((x * 11 + y * 23) % 61) == 0 then put_if(S, x, y, ".", C.dark_gray) end
      end
    end
  end
  if half > 0 then
    for x = 1, W - 2 do
      put_if(S, x, topE, "=", C.gray)
      put_if(S, x, botE, "=", C.gray)
    end
    put_if(S, 1, topE, "[", C.gray); put_if(S, W - 2, topE, "]", C.gray)
    put_if(S, 1, botE, "[", C.gray); put_if(S, W - 2, botE, "]", C.gray)
  end

  -- === 砚台（左下）与落墨 ===
  if u > 0.5 then
    local ox, oy = 4, 33
    S.print(ox, oy,     " .---. ", C.gray)
    S.print(ox, oy + 1, "( ", C.gray)
    S.print(ox + 2, oy + 1, "▓▓▓", C.white)
    S.print(ox + 5, oy + 1, " )", C.gray)
    S.print(ox, oy + 2, " '---' ", C.gray)
  end
  if t >= INK_DROP and t < INK_HIT then
    local p = clamp01((t - INK_DROP) / (INK_HIT - INK_DROP))
    put_if(S, 7, math.floor(19 + 15 * p + 0.5), "*", C.white)   -- 墨点离砚，落入墨池
  elseif t >= INK_HIT then
    local age = t - INK_HIT
    if age < 0.9 then
      for k = 0, 1 do
        local rr = age * 6 - k * 1.6
        if rr > 0 and rr < 5 then
          ring(S, 7, 34, rr, (k == 0) and C.gray or C.dark_gray, ".", 0.5)
        end
      end
    end
  end

  -- === 笔迹（由湿到干：实块 → 半干 → 细线） ===
  for y = 0, H - 1 do
    local row = ink[y]
    if row then
      for x, drawn in pairs(row) do
        local age = t - drawn
        if age < 0 then age = 0 end
        local wet = math.exp(-age * 2.6)          -- 1 刚写 → 0 干
        local ch = (wet > 0.72 and "█") or (wet > 0.46 and "▓")
                   or (wet > 0.24 and "▒") or "#"
        S.put(x, y, ch, C.white)
      end
    end
  end

  -- === 墨晕：湿墨向四邻不规则洇开（越湿越远，干则收；不画成一圈同尺寸点） ===
  for y = 0, H - 1 do
    local row = ink[y]
    if row then
      for x, drawn in pairs(row) do
        local wet = math.exp(-(t - drawn) * 2.6)
        if wet > 0.30 then
          local reach = (wet > 0.62) and 2 or 1
          for dy = -reach, reach do
            for dx = -reach, reach do
              if dx ~= 0 or dy ~= 0 then
                local nx, ny = x + dx, y + dy
                if nx >= 0 and nx < W and ny >= 0 and ny < H
                   and not (ink[ny] and ink[ny][nx]) then
                  local h = hash(nx * 7 + dx * 3, ny * 11 + dy * 5)
                  local prob = (wet - 0.28) * 0.6
                  if reach == 2 then prob = prob * 0.45 end
                  if h < prob then
                    S.put(nx, ny, (h < prob * 0.3 and ",") or ".", C.dark_gray)
                  end
                end
              end
            end
          end
        end
      end
    end
  end

  -- === 笔尖（书写中）：竹管 + 笔锋，落在下一格上 ===
  if t >= WRITE0 and revealed < NCELL then
    local c = PLAN[revealed + 1]
    if c then
      put_if(S, c.x, c.y, "*", C.white)             -- 笔锋触纸
      put_if(S, c.x, c.y - 1, "|", C.gray)
      put_if(S, c.x + 1, c.y - 2, "/", C.gray)
    end
  end

  -- === 朱砂印章（朱底阴文） ===
  if t >= SEAL_T then
    local age = t - SEAL_T
    local cx, cy = SEAL_X + 4, SEAL_Y + 4
    if age < 0.45 then                              -- 朱砂红晕：先扩后淡
      ring(S, cx, cy, 2.5 + age * 9, (age < 0.20) and C.red or C.dark_gray, ".", 0.85)
    end
    if age < 0.09 then                              -- 落章前的一"顿"：先见其影
      for xx = 0, 7 do put_if(S, SEAL_X + xx, SEAL_Y - 1, "-", C.gray) end
      for yy = 0, 7 do put_if(S, SEAL_X + 7, SEAL_Y - 1 + yy, "|", C.gray) end
    else
      for yy = 0, 7 do
        for xx = 0, 7 do S.put(SEAL_X + xx, SEAL_Y + yy, "█", C.red) end
      end
      if age > 0.10 then                            -- 阴文：刻出的字成纸色
        for yy = 0, 7 do
          local rowmask = SEAL_INK[yy + 1]
          for xx = 0, 7 do
            if rowmask:sub(xx + 1, xx + 1) == "." then
              S.put(SEAL_X + xx, SEAL_Y + yy, "█", C.black)
            end
          end
        end
        if age < 1.2 then                           -- 朱砂渗：边缘数点，随干渐隐
          local spots = { {SEAL_X-1,SEAL_Y+2},{SEAL_X+8,SEAL_Y+4},{SEAL_X+2,SEAL_Y-1},
                          {SEAL_X+6,SEAL_Y+8},{SEAL_X-1,SEAL_Y+6},{SEAL_X+8,SEAL_Y+1} }
          for i, sp in ipairs(spots) do
            if (i + math.floor(age * 4)) % 2 == 0 then put_if(S, sp[1], sp[2], ".", C.red) end
          end
        end
      end
    end
  end

  -- === 读数与提示 ===
  if t >= READY_T then
    local pulse = (math.floor((t - READY_T) * 2) % 2 == 0)
    local w = phos.text.width(L.ready)
    S.print((W - w) // 2, 38, L.ready, pulse and C.white or C.red)
    S.print(SEAL_X + 10, SEAL_Y + 3, L.scent, C.dark_gray)
    put_if(S, 2, 5, "~", C.dark_gray);   put_if(S, W - 3, 5, "~", C.dark_gray)
    put_if(S, 2, 40, "~", C.dark_gray);  put_if(S, W - 3, 40, "~", C.dark_gray)
  end

  S.print(3, 1, L.title, C.gray)
  local vt = "v" .. phos.sys.version()
  S.print(W - 3 - phos.text.width(vt), 1, vt, C.dark_gray)
  local pct = math.min(100, math.floor(revealed / math.max(1, NCELL) * 100))
  S.print(3, H - 2, string.format("INK %3d%%", pct), C.gray)
end

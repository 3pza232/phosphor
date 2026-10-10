-- PERSISTENCE：余辉留痕
-- 动效：写头从左向右扫过，扫到的笔画**先亮后暗**——像显像管上的余辉，
--       于是 PHOSPHOR 的字样在第一遍里逐渐"显影"；第二遍扫得更利落，
--       最后停在稳定的余辉上，报一句 READY。
--
-- 实现要点：全屏只维护一张 heat 表（0~1，每帧按 0.9/秒 衰减）。
-- 写头经过的格子 heat = 1，之后自己黯淡下去；字形与颜色都由 heat 选。
-- 所以"显影"与"留住"是同一套数据，不需要任何逐帧的补间状态。

local W, H = 80, 45
local DECAY = 0.9                    -- 余辉衰减速率（每秒）

-- 文案按界面语言给：启动动画跑在完整 API 沙箱里，取值同样走 phos.lang
local Text = {
  zh = { title = "显像管余辉", ready = "就绪", sweep = "扫描 %02d / %02d" },
  en = { title = "PHOSPHOR PERSISTENCE", ready = "READY", sweep = "SWEEP %02d / %02d" },
}
local L = phos.lang.dict(Text)

-- 「PHOSPHOR」的 5x5 点阵：只做 P H O S R 五个字形就够写整句
local GLYPH = {
  P = { "####.", "#...#", "####.", "#....", "#...." },
  H = { "#...#", "#...#", "#####", "#...#", "#...#" },
  O = { ".###.", "#...#", "#...#", "#...#", ".###." },
  S = { ".####", "#....", ".###.", "....#", "####." },
  R = { "####.", "#...#", "####.", "#..#.", "#...#" },
}
local WORD = "PHOSPHOR"
local PITCH = 6                      -- 字形宽 5 + 1 列间隔
local WORD_W = #WORD * PITCH - 1     -- 47
local OX, OY = (W - WORD_W) // 2, 14

-- 余辉：heat[y][x] ∈ [0,1]；0 = 全暗
local heat = {}
for y = 0, H - 1 do
  heat[y] = {}
  for x = 0, W - 1 do heat[y][x] = 0 end
end

-- 第 i 列字形属于哪个字母的第几列（col < 5 才是笔画，5 是字间距）
local function strokes(i)
  local letters, col = {}, i % PITCH
  if col > 4 then return letters, -1 end
  local li = (i - col) // PITCH + 1
  local ch = WORD:sub(li, li)
  for row = 0, 4 do
    local g = GLYPH[ch]
    if g and g[row + 1]:sub(col + 1, col + 1) == "#" then
      letters[#letters + 1] = OY + row
    end
  end
  return letters, col
end

local t = 0
local clicks = 0
local done = false

function update(dt)
  t = t + dt

  -- 衰减在 update 里按 dt 走：写死在 draw 里按"每帧多少"折算会跟着帧率变
  for y = 0, H - 1 do
    local row = heat[y]
    for x = 0, W - 1 do
      if row[x] > 0 then
        row[x] = row[x] - DECAY * dt
        if row[x] < 0 then row[x] = 0 end
      end
    end
  end

  -- 两遍扫描各占一段：第一遍"显影"、第二遍"稳住"；之后只留衰减
  local pass, rate = 1, WORD_W / 1.3
  if t > 1.65 then
    pass, rate = 2, WORD_W / 0.85
  end
  if t <= 1.30 or (t > 1.65 and t <= 2.50) then
    local p1 = math.min(WORD_W, math.floor((t - (pass == 1 and 0 or 1.65)) * rate))
    -- 写头扫过：这一列的所有笔画都点满
    local cursor = math.max(0, math.min(WORD_W - 1, p1 - 1))
    for i = math.max(0, cursor - 2), cursor do
      local rows = strokes(i)
      for _, y in ipairs(rows) do heat[y][OX + i] = 1 end
    end
    -- 每扫过几列给一声轻响（写头的咔哒）
    local c = math.floor(p1 / 6)
    if c > clicks then
      clicks = c
      phos.audio.beep(1400 + pass * 300, 0.02, { wave = "square", volume = 0.06 })
    end
  end

  if not done and t > 2.5 then
    done = true
    phos.audio.note("C5", { wave = "triangle", dur = 0.10, volume = 0.16 })
    phos.audio.note("G5", { wave = "triangle", dur = 0.18, volume = 0.18 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  -- 字形：按余辉强度选块字符与颜色（越亮越实、越冷越白）。
  -- 衰减已在 update 里按 dt 做过，这里只负责画
  local RAMP = { "░", "▒", "▓", "█" }
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      local v = heat[y][x]
      if v > 0.03 then
        local idx = math.min(4, math.floor(v * 4) + 1)
        local col = (v > 0.75 and C.white) or (v > 0.4 and C.green) or C.dark_gray
        S.put(x, y, RAMP[idx], col)
      end
    end
  end

  -- 写头：一道竖直亮线 + 脚下的光斑，扫过时最亮
  local head = nil
  if t <= 1.30 then head = math.floor(t * (WORD_W / 1.3))
  elseif t > 1.65 and t <= 2.50 then head = math.floor((t - 1.65) * (WORD_W / 0.85)) end
  if head then
    local hx = OX + math.max(0, math.min(WORD_W - 1, head - 1))
    for y = OY - 3, OY + 7 do
      if y >= 0 and y < H then S.put(hx, y, ":", C.green) end
    end
    if hx + 1 < W then S.put(hx + 1, OY + 3, ">", C.white) end
  end

  -- 底部读数：扫描进度 + 标题；扫描完成后报就绪
  local p = math.min(1, t / 2.5)
  S.print(2, H - 4, string.format(L.sweep, math.floor(p * 20), 20), C.dark_gray)
  if t > 2.5 then
    local w = phos.text.width(L.ready)
    S.print((W - w) // 2, OY + 9, L.ready, (math.floor(t * 5) % 2 == 0) and C.white or C.green)
  end
  S.print(2, 1, L.title, C.green)
  S.print(W - 2 - phos.text.width("v" .. phos.sys.version()), 1,
          "v" .. phos.sys.version(), C.dark_gray)
end

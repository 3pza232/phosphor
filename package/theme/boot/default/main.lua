-- TUBE WARMUP：显像管预热
-- 阶段一 0.0~0.7s：中央亮线展开 + 亮度冲击波
-- 阶段二 0.7~ :  自检逐行打出，扫描头来回移动
-- 阶段三 末段：整屏轻微抖动后稳定

local t = 0
local H = 45
local W = 80

-- 声音设计：与画面三个阶段同步
--   合闸（电源接通的低频重击 + 触点噪声）
--   → 高压起振（细而高的"咝——"，带慢起振）
--   → 亮线展开（放电 zap）
--   → 自检逐行（每行一声轻微 tick，与打字节奏同一拍）
--   → 稳定锁定（低音 + 余音）
local fired = {}
local last_check_row = 0

local function once(key, fn)
  if fired[key] then return end
  fired[key] = true
  fn()
end

-- 自检行文案：跟随机器界面语言。启动动画与卡带用**同一套约定**（phos.sys.language()），
-- 新增语言只需加一列，不要在脚本里写死某一种语言
local L = {
  zh = {
    "显像管预热 .......... 通过",
    "内存自检 ............ 通过",
    "显示层 ............. 通过",
    "外壳层 ............. 通过",
    "显像管滤镜 .......... 通过",
    "等待插入卡带 _",
  },
  en = {
    "TUBE WARMUP ......... OK",
    "MEMORY CHECK ........ OK",
    "DISPLAY LAYER ....... OK",
    "SHELL LAYER ......... OK",
    "TUBE FILTER ......... OK",
    "WAITING FOR CART _",
  },
}
local text = L[phos.sys.language()] or L.zh

local checks = {
  phos.sys.product() .. " v" .. phos.sys.version(),  -- 版本来自主机 API，不硬编码
  "",
  text[1],
  text[2],
  text[3],
  text[4],
  text[5],
  "",
  text[6],
}

function update(dt)
  t = t + dt

  -- 合闸：低频重击 + 一声触点噪声
  if t >= 0 then
    once("power", function()
      phos.audio.beep(70, 0.30, { wave = "triangle", sweep = 40, volume = 0.30, release = 0.20 })
      phos.audio.beep(1600, 0.03, { wave = "noise", volume = 0.12, release = 0.02 })
    end)
  end

  -- 高压起振：细而高的长音，慢起振（显像管特有的"咝——"）
  if t >= 0.08 then
    once("hv", function()
      phos.audio.beep(1800, 1.0, { wave = "sine", sweep = 3400, volume = 0.06,
                                   attack = 0.30, release = 0.40 })
    end)
  end

  -- 亮线展开：放电 zap
  if t >= 0.70 then
    once("zap", function()
      phos.audio.beep(900, 0.12, { wave = "square", sweep = 150, volume = 0.16, release = 0.08 })
    end)
  end

  -- 自检逐行：每行一声 tick（与画面 0.28s 一行的节奏同一拍）
  if t >= 0.70 then
    local row = math.floor((t - 0.70) / 0.28) + 1
    if row > last_check_row and row <= #checks then
      last_check_row = row
      phos.audio.perc("H")
    end
  end

  -- 稳定锁定：低音落下 + 高频余音
  if t >= 2.90 then
    once("lock", function()
      phos.audio.note("E3", { wave = "triangle", dur = 0.18, volume = 0.16 })
      phos.audio.note("B3", { wave = "sine", dur = 0.55, volume = 0.09, release = 0.45 })
    end)
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  -- 阶段一：亮线从中央展开（带亮度冲击波）
  if t < 0.7 then
    local p = t / 0.7
    local half = math.floor(p * 22)
    for dy = -half, half do
      local y = 22 + dy
      local edge = math.abs(dy) == half
      local ch = edge and "#" or (math.abs(dy) % 3 == 0 and "=" or "-")
      local col = edge and C.white or C.green
      for x = 0, W - 1 do
        S.put(x, y, ch, col)
      end
    end
    -- 冲击波：向外扩散的亮点环
    local ring = math.floor(p * 30)
    if ring > 0 and ring < 30 then
      for x = 0, W - 1, 2 do
        S.put(x, 22 - ring, ".", C.dark_gray)
        S.put(x, 22 + ring, ".", C.dark_gray)
      end
    end
    return
  end

  -- 阶段二：自检逐行打出 + 扫描头
  local phase = t - 0.7
  local visible = math.floor(phase / 0.28) + 1

  for i = 1, #checks do
    if i <= visible then
      local line = checks[i]
      S.print(22, 13 + (i - 1) * 2, line, C.green)
      -- 最近一行显示光标
      if i == visible then
        local cursor = 22 + #line
        if math.floor(t * 5) % 2 == 0 then
          S.put(cursor + 1, 13 + (i - 1) * 2, "|", C.white)
        else
          S.put(cursor + 1, 13 + (i - 1) * 2, " ", C.black)
        end
      end
    end
  end

  -- 扫描头：顶部来回移动的亮点，制造"机器在工作"的动感
  local sweep = math.floor((0.5 + 0.5 * math.sin(t * 2.0)) * (W - 3)) + 1
  S.put(sweep, 2, "#", C.white)
  S.put(sweep - 1, 2, "=", C.dark_gray)
  S.put(sweep + 1, 2, "=", C.dark_gray)

  -- 阶段三：末段整屏轻微抖动（电压不稳的余韵）
  if phase > 2.0 then
    local jitter = math.floor(phase * 12) % 3
    if jitter == 1 then
      S.put(1, 44, "!", C.dark_gray)
      S.put(W - 2, 0, "!", C.dark_gray)
    end
  end
end

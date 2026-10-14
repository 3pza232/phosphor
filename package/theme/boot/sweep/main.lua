-- CART LOADER：卡带装载
-- 动效：进度条从左向右推进，走过的格子逐一点亮，右端有闪烁的读写头；
--       下方逐块校验灯按节奏点亮，全部点亮后标题闪一下

local t = 0
local W, H = 80, 45
local BLOCKS = 12

-- 文案跟随机器界面语言（与卡带同一套约定：phos.lang.dict，新增语言加一列）
local L = {
  zh = { loading = "正在装入卡带", block = "区块 %02d / %02d", ready = "卡槽就绪" },
  en = { loading = "LOADING CART", block = "BLOCK %02d / %02d", ready = "SLOT READY" },
}
local text = phos.lang.dict(L)

local started = false
local finished = false
local last_block = 0

local function progress()
  local p = (t - 0.2) / 2.8
  if p < 0 then return 0 end
  if p > 1 then return 1 end
  return p
end

function update(dt)
  t = t + dt

  -- 装载启动：低频上扫，像马达起转
  if not started and t > 0 then
    started = true
    phos.audio.beep(90, 0.35, { wave = "saw", sweep = 260, volume = 0.16, release = 0.12 })
  end

  -- 每点亮一块：一声清脆的读写头咔哒
  local block = math.floor(progress() * BLOCKS)
  if block > last_block then
    last_block = block
    phos.audio.perc("H")
  end

  -- 装载完成：三声上行确认音
  if not finished and progress() >= 1 then
    finished = true
    phos.audio.note("C5", { wave = "square", dur = 0.09, volume = 0.18 })
    phos.audio.note("E5", { wave = "square", dur = 0.09, volume = 0.18 })
    phos.audio.note("G5", { wave = "square", dur = 0.14, volume = 0.20 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  local bar_w = 56
  local bar_x = (W - bar_w) // 2
  local bar_y = 26

  -- 进度：0.2s 启动延迟后线性推进到 3.0s
  local p = (t - 0.2) / 2.8
  if p < 0 then p = 0 end
  if p > 1 then p = 1 end
  local filled = math.floor(p * bar_w)

  S.print(bar_x, 18, text.loading, C.green)
  S.print(bar_x, 20, string.format(text.block, math.min(BLOCKS, math.floor(p * BLOCKS) + 1), BLOCKS), C.gray)

  -- 进度条
  for i = 0, bar_w - 1 do
    local ch = i < filled and "#" or "-"
    local col = i < filled and C.green or C.dark_gray
    S.put(bar_x + i, bar_y, ch, col)
  end
  S.put(bar_x - 1, bar_y, "[", C.gray)
  S.put(bar_x + bar_w, bar_y, "]", C.gray)

  -- 读写头：在进度末端闪烁
  if filled < bar_w then
    local head_x = bar_x + filled
    if math.floor(t * 12) % 2 == 0 then
      S.put(head_x, bar_y, ">", C.white)
    end
    -- 头部微光：用**调色板**里的颜色。皮肤配色（accent 之类）是主机界面专用的，
    -- 卡带与内容包拿不到也不该拿——那会把机台配色带进游戏画面
    S.put(head_x - 1, bar_y, "=", C.cyan)
  end

  -- 百分比
  local pct = string.format("%3d%%", math.floor(p * 100))
  S.print(bar_x + bar_w // 2 - 2, bar_y + 2, pct, C.yellow)

  -- 校验灯：BLOCKS 个方块，按进度逐个点亮
  local lit = math.floor(p * BLOCKS + 0.0001)
  local led_x = bar_x + bar_w // 2 - BLOCKS
  for i = 0, BLOCKS - 1 do
    if i < lit then
      S.put(led_x + i * 2, bar_y + 5, "#", C.green)
    else
      S.put(led_x + i * 2, bar_y + 5, ".", C.dark_gray)
    end
  end

  -- 完成：标题闪一下
  if p >= 1 then
    local flash = math.floor((t - 3.0) * 6) % 2 == 0
    local title = phos.sys.product() .. " v" .. phos.sys.version()  -- 版本由主机 API 提供
    local col = flash and C.white or C.green
    -- 居中按**显示宽度**算：中英字数不同，拿 #title（字节数）居中会歪
    S.print(W // 2 - phos.text.width(title) // 2, 36, title, col)
    S.print(W // 2 - phos.text.width(text.ready) // 2, 38, text.ready, C.gray)
  end
end

duration = 4.4   -- 本动画自报时长（秒）：由 App 读取，未声明则用出厂 3.2s
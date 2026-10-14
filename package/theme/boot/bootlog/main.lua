-- BOOT LOG：开机自检（逐行 POST + 右侧读数 + 进度条 → 全部 OK 后打出产品名）
--
-- 时间线：
--   0.40s~   逐行打印 POST 记录（每行一声打字机轻响），右侧给出该项读数
--   2.8s~    进度条走满、居中打出产品名与"自检通过"
-- 分工：状态只在 update 里推进（时间、已打印行数），draw 只按当前状态作画。
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "开机自检", pass = "自检通过" },
              en = { title = "POWER-ON SELF-TEST", pass = "SELF-TEST PASSED" } }
local L = phos.lang.dict(TXT)

local LINES = {
  "CPU    4 MHz",
  "RAM    64K CHECK",
  "CRT    RASTER 80x45",
  "CART   SLOT BUS",
  "SOUND  AY 3-CH",
  "CLOCK  VSYNC 60Hz",
  "UART   LOOPBACK",
  "BIOS   PHOSPHOR v" .. phos.sys.version(),
}

local NAME_W = 26
local X, ROW0 = 4, 5
local STEP, DELAY = 0.30, 0.40
local shown, next_at, ready = 0, DELAY, false

local function rnd(a, b) return phos.sys.random(a, b) end

local function pad(name)
  local n = NAME_W - #name
  if n < 1 then n = 1 end
  return name .. string.rep(".", n)
end

-- 每行右侧一个读数（十六进制），让自检看起来真的在量东西
local vals = {}
for i = 1, #LINES do vals[i] = string.format("%04X", rnd(1, 65535)) end

function update(dt)
  t = t + dt
  if shown < #LINES and t >= next_at then
    shown = shown + 1
    next_at = next_at + STEP
    phos.audio.beep(680, 0.025, { wave = "square", volume = 0.09 })
  end
  if not ready and shown >= #LINES and t >= next_at + 0.35 then
    ready = true
    phos.audio.note("C5", { wave = "sine", dur = 0.45, sweep = 1180, volume = 0.12 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  -- 标题栏：标题 + 一条横线 + 右上角 POST 计数器
  S.print(X, 2, L.title, C.gray)
  for x = X, W - X - 1 do S.put(x, 3, "-", C.dark_gray) end
  S.print(math.max(X, W - 14), 2, string.format("POST %02d/%02d", shown, #LINES), C.dark_gray)

  for i = 1, shown do
    local y = ROW0 + i - 1
    S.print(X, y, pad(LINES[i]), C.gray)
    S.print(X + NAME_W + 1, y, vals[i], C.dark_gray)          -- 该项读数
    local ok_col = (i < shown or ready) and C.green or C.gray
    S.print(X + NAME_W + 7, y, "OK", ok_col)                  -- 末行打字时先灰后亮
  end
  if not ready and shown > 0 and math.floor(t * 8) % 2 == 0 then
    S.put(X + NAME_W + 10, ROW0 + shown - 1, "_", C.white)
  end

  -- 进度条：随已测行数推进
  local bw = W - 2 * X
  local filled = math.floor(bw * (shown / #LINES) + 0.5)
  for k = 0, bw - 1 do
    S.put(X + k, ROW0 + #LINES + 1, k < filled and "=" or "-", k < filled and C.green or C.dark_gray)
  end

  if ready then
    local cx = W // 2
    local y = ROW0 + #LINES + 3
    S.print(cx - #LOGO // 2, y, LOGO, C.green)
    S.print(cx - #L.pass // 2, y + 2, L.pass, C.gray)
  end
end

duration = 6.0   -- 本动画自报时长（秒）：自检走完 + 通过横幅停留

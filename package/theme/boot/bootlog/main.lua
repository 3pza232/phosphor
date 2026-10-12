-- BOOT LOG：逐行滚出的开机自检，全部 OK 后打出产品名
--
-- 时间线：
--   0.35s~   逐行打印 POST 记录（每行一声打字机轻响）
--   2.6s~    居中打出产品名与"就绪"
-- 分工：状态只在 update 里推进（时间、已打印行数），draw 只按当前状态作画。
-- dt 只传给 update —— draw 里拿 dt 会是 nil
local t = 0
local W, H = 80, 45

-- 取主机的可玩区尺寸而不是写死 80x45：这样动画在任何皮肤下都不会越出可见区
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end

local LOGO = phos.sys.product()

-- 文案跟随机器界面语言（缺 en 回落中文）
local TXT = { zh = { title = "开机自检", ready = "就绪" },
              en = { title = "POWER-ON SELF-TEST", ready = "READY" } }
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

local NAME_W = 26   -- 名字 + 点线排到这么宽，右侧的 OK 才会对齐成一竖列
local X, ROW0 = 5, 5
local STEP, DELAY = 0.24, 0.35
local shown, next_at, ready = 0, DELAY, false

local function pad(name)
  local n = NAME_W - #name
  if n < 1 then n = 1 end
  return name .. string.rep(".", n)
end

function update(dt)
  t = t + dt
  if shown < #LINES and t >= next_at then
    shown = shown + 1
    next_at = next_at + STEP
    phos.audio.beep(680, 0.025, { wave = "square", volume = 0.09 })
  end
  if not ready and shown >= #LINES and t >= next_at + 0.3 then
    ready = true
    phos.audio.note("C5", { wave = "sine", dur = 0.45, sweep = 1180, volume = 0.12 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(X, 2, L.title, C.gray)

  for i = 1, shown do
    local y = ROW0 + i - 1
    S.print(X, y, pad(LINES[i]), C.gray)
    -- 末行打字时 OK 先灰后亮，像是在逐项核对
    local ok_col = (i < shown or ready) and C.green or C.gray
    S.print(X + NAME_W + 1, y, "OK", ok_col)
  end
  -- 未就绪时，在末行右端闪一个光标
  if not ready and shown > 0 and math.floor(t * 8) % 2 == 0 then
    S.put(X + NAME_W + 4, ROW0 + shown - 1, "_", C.white)
  end

  if ready then
    local cx = W // 2
    local lx = cx - #LOGO // 2
    local y = ROW0 + #LINES + 3
    S.print(lx, y, LOGO, C.green)
    S.print(lx + #LOGO + 3, y, L.ready, C.gray)
  end
end

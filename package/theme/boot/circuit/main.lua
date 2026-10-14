-- CIRCUIT：电路板通电
-- 一批正交走线（带拐角）从左侧起逐段点亮，"电流"亮点沿线流到末端；焊盘闪一下，
-- 全板通电后中央打出产品名。
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "通电自检" }, en = { title = "POWER RAIL" } }
local L = phos.lang.dict(TXT)

-- 生成 6 条正交走线：一串电平/垂直段的坐标，最后一段朝右
local wires = {}
do
  local rnd = phos.sys.random
  for w = 1, 6 do
    local x, y = 3 + rnd(0, 6), 4 + (w - 1) * 7 + rnd(0, 3)
    local pts = { { x, y } }
    for _ = 1, 4 do
      x = math.min(W - 4, x + 8 + rnd(0, 10))
      table.insert(pts, { x, y })
      y = math.min(H - 3, math.max(3, y + (rnd(0, 1) == 0 and -3 or 3)))
      table.insert(pts, { x, y })
    end
    wires[w] = pts
  end
end

local function seg_len(wire)
  local n = 0
  for i = 2, #wire do
    n = n + math.abs(wire[i][1] - wire[i - 1][1]) + math.abs(wire[i][2] - wire[i - 1][2])
  end
  return n
end
local LENS = {}
for i, w in ipairs(wires) do LENS[i] = seg_len(w) end

function update(dt) t = t + dt end

-- 沿走线取第 d 段之后的点（用于逐段点亮）
local function plot(S, C, wire, upto)
  local acc = 0
  for i = 2, #wire do
    local ax, ay = wire[i - 1][1], wire[i - 1][2]
    local bx, by = wire[i][1], wire[i][2]
    local len = math.abs(bx - ax) + math.abs(by - ay)
    if acc < upto then
      local x0, x1 = math.min(ax, bx), math.max(ax, bx)
      local y0, y1 = math.min(ay, by), math.max(ay, by)
      for x = x0, x1 do for y = y0, y1 do
        if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, "-", C.dark_gray) end
      end end
      -- 拐角焊盘
      S.put(ax, ay, "o", C.gray)
    end
    acc = acc + len
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.dark_gray)

  for i, wire in ipairs(wires) do
    local total = LENS[i]
    local prog = math.min(total, t * (total / 2.4) - i * 2)     -- 各线略有先后
    if prog > 0 then
      plot(S, C, wire, prog)
      -- 沿线的"电流"亮点：把已走过的段再打亮一截
      local acc = 0
      local pulse = 6
      for j = 2, #wire do
        local ax, ay = wire[j - 1][1], wire[j - 1][2]
        local bx, by = wire[j][1], wire[j][2]
        local len = math.abs(bx - ax) + math.abs(by - ay)
        -- 亮点位置：以 4 格/秒向前跑，循环
        local p = (t * 6) % total
        if p >= acc and p < acc + len then
          local off = math.floor(p - acc)
          local x = ax + ((bx > ax) and math.min(off, len) or 0)
          local y = ay + ((by > ay) and math.min(off, len) or 0)
          for k = 0, pulse - 1 do
            local xx, yy = x - ((bx > ax) and k or 0), y - ((by > ay) and k or 0)
            if xx >= 0 and xx < W and yy >= 0 and yy < H then S.put(xx, yy, "=", C.green) end
          end
        end
        acc = acc + len
      end
    end
  end

  if t > 3.0 then
    local lit = math.floor((t - 3.0) * 12)
    local lx = W // 2 - #LOGO // 2
    for k = 1, math.min(lit, #LOGO) do S.put(lx + k - 1, H - 4, LOGO:sub(k, k), C.white) end
  end
end

duration = 5.0   -- 本动画自报时长（秒）

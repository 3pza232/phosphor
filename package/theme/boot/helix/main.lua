-- HELIX：双螺旋
-- 两条正弦链在屏上相互缠绕（用 cos 判定前后，前亮后暗），碱基对竖档逐个点亮；
-- 收束阶段两链并拢，"拉链"合上后产品名自中缝亮起。
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "螺旋" }, en = { title = "HELIX" } }
local L = phos.lang.dict(TXT)

local CX = W // 2
local MID = H // 2 + 1
local AMP = 11
local X0, X1 = 5, W - 6
local ZIP_T = 2.6                       -- 两链并拢的时刻

function update(dt) t = t + dt end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.dark_gray)
  S.print(math.max(3, W - 9), 1, "DUPLEX", C.dark_gray)

  -- 并拢：2.6s 后振幅收到 0，两链在中线合上
  local zip = math.min(1, math.max(0, (t - (ZIP_T - 0.9)) / 0.9))
  local amp = AMP * (1 - zip)
  local phase = t * 1.5

  for x = X0, X1 do
    local u = (x - X0) / (X1 - X0)
    local a = phase + u * math.pi * 3.2
    local s = math.sin(a)
    local y1 = math.floor(MID - amp * s + 0.5)
    local y2 = math.floor(MID + amp * s + 0.5)
    local front = math.cos(a) > 0        -- 前链亮、后链暗
    S.put(x, y1, front and "O" or "o", front and C.green or C.dark_gray)
    S.put(x, y2, front and "o" or "O", front and C.dark_gray or C.cyan)

    -- 碱基对：每 7 列一根竖档；一颗"亮点"沿 x 推进，把走过的碱基点亮成黄
    if (x - X0) % 7 == 0 then
      local lo, hi = math.min(y1, y2), math.max(y1, y2)
      local lit = (x <= X0 + math.floor((t * 34) % (X1 - X0)))
      for y = lo + 1, hi - 1 do
        S.put(x, y, "|", lit and C.yellow or C.dark_gray)
      end
    end
  end

  -- 合上后：产品名自中缝逐字亮出
  if t > ZIP_T + 0.2 then
    local lit = math.floor((t - ZIP_T - 0.2) * 12)
    local lx = CX - #LOGO // 2
    for k = 1, math.min(lit, #LOGO) do
      S.put(lx + k - 1, MID, LOGO:sub(k, k), k >= lit and C.yellow or C.white)
    end
  end
end

duration = 5.2   -- 本动画自报时长（秒）

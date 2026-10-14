-- GLOBE：线框地球
-- 一颗旋转的线框球：经线随自转向右流动、纬线为横向椭圆；陆地以亮点扫出；
-- 一圈轨道卫星掠过，最后产品名在球下方亮起。
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "全球链路" }, en = { title = "UPLINK" } }
local L = phos.lang.dict(TXT)

local CX, CY = W // 2, 17
local RX, RY = 20, 10                 -- 椭圆半径：字符格近正方形，纵向压半
local ROT = 0.5                       -- 自转速度

-- 陆地：在球面上撒一批点（经度 lon、纬度 lat，弧度）
local land = {}
for i = 1, 26 do
  land[i] = { lon = phos.sys.random(0, 628) / 100, lat = phos.sys.random(-900, 900) / 1000 * 1.1 }
end

local sat = { a = 0 }

function update(dt)
  t = t + dt
  sat.a = sat.a + dt * 1.1
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.dark_gray)
  S.print(math.max(3, W - 16), 1, string.format("LAT %+03d", math.floor(math.sin(t) * 60)), C.dark_gray)

  -- 纬线：几条横向椭圆
  for k = -3, 3 do
    local lat = k * 0.32
    local y = math.floor(CY + RY * math.sin(lat) + 0.5)
    local r = RX * math.cos(lat)
    for a = 0, 40 do
      local ang = a / 40 * math.pi * 2
      local x = math.floor(CX + r * math.cos(ang) + 0.5)
      if x >= 0 and x < W then S.put(x, y, ".", C.dark_gray) end
    end
  end

  -- 经线：竖椭圆，相位随自转右移（用 sin 表现"转到侧面的经线被压扁"）
  for m = 0, 5 do
    local lon = m * math.pi / 6 + t * ROT
    local w = math.cos(lon) * RX              -- 该经线的横向半宽
    if math.abs(w) > 0.6 then
      for a = 0, 30 do
        local ang = a / 30 * math.pi * 2
        local x = math.floor(CX + w * math.sin(ang) + 0.5)
        local y = math.floor(CY + RY * math.cos(ang) + 0.5)
        if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, "|", C.dark_gray) end
      end
    end
  end

  -- 陆地：只画朝向观察者那一面（cos(lon+t) > 0）
  for _, p in ipairs(land) do
    local lon = p.lon + t * ROT
    local face = math.cos(lon)
    if face > 0 then
      local x = math.floor(CX + RX * math.cos(p.lat) * math.sin(lon) + 0.5)
      local y = math.floor(CY + RY * math.sin(p.lat) + 0.5)
      if x >= 0 and x < W and y >= 0 and y < H then
        S.put(x, y, face > 0.7 and "#" or "+", face > 0.7 and C.green or C.dark_gray)
      end
    end
  end

  -- 轨道卫星：绕球一圈，带一小段尾迹
  local ox, oy = RX + 8, RY + 5
  for k = 0, 2 do
    local a = sat.a - k * 0.08
    local x = math.floor(CX + ox * math.cos(a) + 0.5)
    local y = math.floor(CY + oy * math.sin(a) + 0.5)
    if x >= 0 and x < W and y >= 0 and y < H then S.put(x, y, k == 0 and "*" or ".", k == 0 and C.white or C.dark_gray) end
  end

  if t > 2.6 then
    local lit = math.floor((t - 2.6) * 12)
    local lx = CX - #LOGO // 2
    for k = 1, math.min(lit, #LOGO) do S.put(lx + k - 1, CY + RY + 4, LOGO:sub(k, k), C.white) end
  end
end

duration = 5.6   -- 本动画自报时长（秒）

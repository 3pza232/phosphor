-- EMBER：炉膛火焰（跳动的火体 + 火星 + 升腾的烟 + 热浪，产品名从火中浮出）
--
-- 时间线：
--   0.0s~     底部整排火苗跳动（红→橙→黄），火星升腾，烟缕上飘，炉底一圈热辉
--   2.5s~     产品名逐列从火焰上方浮出，名字带热浪微抖
-- 分工：状态只在 update 推进（火星/烟/时间），draw 只按当前状态作画（dt 不进 draw）
local t = 0
local W, H = 80, 45
do
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 then W, H = pw, ph_ end
end
local LOGO = phos.sys.product()
local TXT = { zh = { title = "点火" }, en = { title = "IGNITION" } }
local L = phos.lang.dict(TXT)

local REVEAL_T = 2.5
local LOGO_ROW = H // 2
local embers, smoke = {}, {}
local spawn_acc = 0

local function rnd(a, b) return phos.sys.random(a, b) end

function update(dt)
  t = t + dt
  spawn_acc = spawn_acc + dt * 40
  while spawn_acc >= 1 do
    spawn_acc = spawn_acc - 1
    embers[#embers + 1] = { x = rnd(0, W - 1), y = H - 2, vy = -(6 + rnd(0, 12)),
                            life = 0.7 + rnd(0, 50) / 100, age = 0 }
    if rnd(0, 99) < 30 then                       -- 少量烟缕
      smoke[#smoke + 1] = { x = rnd(0, W - 1), y = H - 4, vy = -(2 + rnd(0, 4)),
                            life = 1.4 + rnd(0, 80) / 100, age = 0 }
    end
  end
  for i = #embers, 1, -1 do
    local e = embers[i]
    e.age = e.age + dt; e.y = e.y + e.vy * dt; e.vy = e.vy + 6 * dt   -- 上飘减速
    if e.age >= e.life or e.y < 1 then table.remove(embers, i) end
  end
  for i = #smoke, 1, -1 do
    local s = smoke[i]
    s.age = s.age + dt; s.y = s.y + s.vy * dt
    if s.age >= s.life or s.y < 1 then table.remove(smoke, i) end
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.dark_gray)
  S.print(math.max(3, W - 13), 1, string.format("TEMP %d C", 800 + math.floor(t * 120) % 400), C.dark_gray)

  for x = 0, W - 1 do S.put(x, H - 1, "=", C.red) end       -- 炉底热辉

  -- 烟缕（暗，先画免得盖住火星）
  for _, s in ipairs(smoke) do
    if 1 - s.age / s.life > 0.2 then
      S.put(math.floor(s.x + math.sin(s.y * 0.5 + t) * 1.5), math.floor(s.y), "^", C.dark_gray)
    end
  end

  -- 火体：一排跳动的火苗，高度由正弦起伏叠加随机抖动决定
  for x = 0, W - 1 do
    local wave = 0.5 + 0.5 * math.sin(x * 0.35 + t * 7.0)
    local flame = 3 + math.floor(wave * wave * 9 + rnd(0, 3))
    for k = 0, flame - 1 do
      local y = H - 2 - k
      local frac = k / math.max(1, flame - 1)
      local col = frac < 0.4 and C.red or (frac < 0.75 and C.orange or C.yellow)
      S.put(x, y, frac < 0.5 and "#" or "*", col)
    end
  end

  -- 火星：从火苗上飘出，越新越亮
  for _, e in ipairs(embers) do
    local k = 1 - e.age / e.life
    local col = k > 0.6 and C.yellow or (k > 0.3 and C.orange or C.red)
    S.put(math.floor(e.x), math.floor(e.y), k > 0.5 and "'" or ".", col)
  end

  -- 产品名逐列浮出（带热浪微抖）
  local lit = math.floor((t - REVEAL_T) * 16)
  if lit > 0 then
    local lx = W // 2 - #LOGO // 2
    for k = 1, math.min(lit, #LOGO) do
      local jx = (k >= lit) and 0 or (rnd(0, 99) < 25 and 1 or 0)
      S.put(lx + k - 1 + jx, LOGO_ROW, LOGO:sub(k, k), k >= lit and C.yellow or C.white)
    end
  end
end

-- EMBER：炉膛里的火焰随呼吸跳动，产品名从火中浮出
--
-- 时间线：
--   0.0s~     底部一整排火苗（高度随时间/位置起伏，红→橙→黄渐变），火星向上升腾
--   2.5s~     产品名从火焰上方逐列浮出
-- 分工：状态只在 update 推进（火星、时间），draw 只按当前状态作画（dt 不进 draw）
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
local embers = {}
local spawn_acc = 0

local function spawn()
  embers[#embers + 1] = {
    x = phos.sys.random(0, W - 1),
    y = H - 2,
    vy = -(6 + phos.sys.random(0, 10)),
    life = 0.7 + phos.sys.random(0, 50) / 100,
    age = 0,
  }
end

function update(dt)
  t = t + dt
  spawn_acc = spawn_acc + dt * 34
  while spawn_acc >= 1 do
    spawn_acc = spawn_acc - 1
    spawn()
  end
  for i = #embers, 1, -1 do
    local e = embers[i]
    e.age = e.age + dt
    e.y = e.y + e.vy * dt
    e.vy = e.vy + 6 * dt          -- 上飘减速
    if e.age >= e.life or e.y < 1 then table.remove(embers, i) end
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(3, 1, L.title, C.dark_gray)

  -- 火体：一排跳动的火苗，高度由正弦起伏叠加随机抖动决定
  for x = 0, W - 1 do
    local wave = 0.5 + 0.5 * math.sin(x * 0.35 + t * 7.0)
    local flame = 3 + math.floor(wave * wave * 7 + phos.sys.random(0, 2))
    for k = 0, flame - 1 do
      local y = H - 1 - k
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

  -- 产品名逐列浮出
  local lit = math.floor((t - REVEAL_T) * 16)
  if lit > 0 then
    local lx = W // 2 - #LOGO // 2
    for k = 1, math.min(lit, #LOGO) do
      S.put(lx + k - 1, LOGO_ROW, LOGO:sub(k, k), k >= lit and C.yellow or C.white)
    end
  end
end

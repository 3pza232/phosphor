-- STATIC RAIN：雪花噪点如雨，LOGO 从干扰中浮现
-- 动效：整屏随机噪点（逐帧变化）→ 噪点密度随 LOGO 浮现而下降 → LOGO 稳定后余噪闪烁

local t = 0
local W, H = 80, 45

local LOGO = {
  phos.sys.product(),  -- 产品名与版本均取自主机 API
}
-- 文案跟随机器界面语言（与卡带同一套约定：phos.sys.language()）
local SUB = {
  zh = { prefix = "系统 v", tail = " —— 信号已捕获" },
  en = { prefix = "SYSTEM v", tail = " — SIGNAL LOCKED" },
}
local sub_text = SUB[phos.sys.language()] or SUB.zh

local NOISE = { ".", ":", ";", "+", "*", "-", "=", "x" }

local next_crackle = 0
local acquired = false

function update(dt)
  t = t + dt

  -- 沙沙声：噪点密集的 2.2 秒里每 0.22s 一次短噪声，音量随噪点一起衰减
  if t < 2.2 and t >= next_crackle then
    next_crackle = t + 0.22
    phos.audio.beep(120, 0.07, { wave = "noise", volume = 0.12 * (1 - t / 2.2), release = 0.05 })
  end

  -- 信号锁定：副标题浮现的同一刻给一声清亮的确认音
  if not acquired and t >= 2.0 then
    acquired = true
    phos.audio.note("A4", { wave = "square", dur = 0.12, sweep = 1760, volume = 0.18 })
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()

  -- 噪点密度：前 2.2s 从 0.55 降到 0.06
  local p = t / 2.2
  if p > 1 then p = 1 end
  local density = 0.55 - 0.49 * p

  -- 噪点雨：每帧重新随机，形成持续的"沙沙"动感
  for y = 0, H - 1 do
    for x = 0, W - 1 do
      if phos.sys.random(1, 1000) <= math.floor(density * 1000) then
        local ch = NOISE[phos.sys.random(1, #NOISE)]
        local shade = phos.sys.random(1, 3)
        local col = shade == 1 and C.dark_gray or (shade == 2 and C.gray or C.green)
        S.put(x, y, ch, col)
      end
    end
  end

  -- LOGO 从中央横向"扫描式"揭露：已揭露部分清出黑底并点亮字符
  local cx = W // 2
  local text = LOGO[1]
  local half = #text // 2
  local lit = math.floor(p * #text * 1.4)
  if lit > #text then lit = #text end

  local y = 20
  if lit > 0 then
    S.fill(cx - half - 1, y, lit + 2, 1, " ", C.black, C.black)
  end
  for k = 1, lit do
    local x = cx - half + (k - 1)
    -- 边缘 3 格带余辉（更绿），其余为白亮
    S.put(x, y, text:sub(k, k), k > lit - 3 and C.green or C.white)
  end

  -- 副标题：LOGO 完成后以打字机方式出现
  local sub = sub_text.prefix .. phos.sys.version() .. sub_text.tail
  if t > 2.0 then
    local n = math.floor((t - 2.0) * 22)
    if n > #sub then n = #sub end
    S.print(cx - #sub // 2, 25, sub:sub(1, n), C.green)
  end

  -- 余噪：稳定后偶发一条干扰线，像信号未完全锁定
  if t > 2.6 and math.floor(t * 3) % 7 == 0 then
    local y = phos.sys.random(0, H - 1)
    for x = 0, W - 1 do
      if phos.sys.random(1, 6) == 1 then
        S.put(x, y, "-", C.dark_gray)
      end
    end
  end
end

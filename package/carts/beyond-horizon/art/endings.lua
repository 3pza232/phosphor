-- art/endings.lua —— 四个真结局的全屏美术（80x45）。结局文本/名单由程序叠在画面上。
-- 稳定 id：ending.E1 / E2 / E3 / E4
local U = require("art.util")

local function merge(...)
  local out = {}
  for _, src in ipairs({ ... }) do
    if src then for k, v in pairs(src) do out[k] = v end end
  end
  return out
end

local function sky(c, seed, count, x0, y0, x1, y1)
  U.stars(c, U.rng(seed), count or 110, { x = x0 or 0, y = y0 or 0, x1 = x1 or 79, y2 = y1 or 44 })
end

-- 椭圆环（线段逐点落格）：用于光子环/信号环/站体环
local function ring(c, cx, cy, rx, ry, ch, step)
  for deg = 0, 359, step or 4 do
    local a = math.rad(deg)
    U.cput(c, math.floor(cx + rx * math.cos(a) + 0.5),
              math.floor(cy + ry * math.sin(a) + 0.5), ch)
  end
end

local function finish(id, c, extra, note)
  return U.canvas_block(id, c, merge(U.ascii_ink(), {
    ["*"] = "body", ["'"] = "panel", [","] = "panel", ["."] = "panel",
    ["="] = "ice", ["~"] = "deep", ["o"] = "ice", ["O"] = "body",
    ["#"] = "white", ["@"] = "warm", ["%"] = "ghost", ["&"] = "glitch",
    ["!"] = "alert", ["?"] = "warn", ["-"] = "line", ["|"] = "line",
  }, extra), { note = note })
end

-- E1 把灯留着：站体在左后方的环，渡鸦号带着引擎光离开（右上方），一路尾迹。
local function e1()
  local c = U.canvas(80, 45)
  sky(c, 1201, 130)
  -- 站体环（左下方，远处）
  ring(c, 22, 33, 13, 5, "'", 3)
  ring(c, 22, 33, 11, 4, ",", 5)
  U.cstamp(c, 15, 28, [==[
   ,----,
  /  o   \
  |  o   |
   \ o  /
    '--'
]==])
  -- 渡鸦号：三角舰体 + 引擎光 + 尾迹
  U.cstamp(c, 52, 12, [==[
      /\
     /  \
    /____\
    |    |
    '----'
]==])
  for i = 0, 14 do
    U.cput(c, 48 - i, 20 + math.floor(i / 3), (i % 2 == 0) and "~" or "*")
  end
  U.cstamp(c, 50, 20, "@@")
  -- 留下的灯：站体窗一排
  for i = 0, 5 do U.cput(c, 12 + i * 4, 38, "o") end
  U.chline(c, 6, 41, 68, "-")
  return finish("ending.E1", c, nil, "80x45 结局 E1「把灯留着」：站体环留灯，渡鸦号离开")
end

-- E2 锚：站体剪影只剩一扇亮着的窗，信号环一圈圈向外淡去。
local function e2()
  local c = U.canvas(80, 45)
  sky(c, 1202, 120)
  U.cstamp(c, 20, 16, [==[
        ,---------,
      /             \
     |   ,-------,   |
     |  /         \  |
     |  |    o    |  |
     |  \         /  |
     |   '-------'   |
      \             /
        '---------'
]==])
  -- 信号环：从站体向外
  ring(c, 40, 27, 20, 8, "'", 5)
  ring(c, 40, 27, 27, 11, ",", 7)
  ring(c, 40, 27, 34, 14, ",", 9)
  -- 一扇还亮着的窗
  U.cstamp(c, 38, 24, "[#]")
  U.chline(c, 8, 39, 64, "-")
  return finish("ending.E2", c, nil, "80x45 结局 E2「锚」：站体只余一扇亮窗，信号环外扩")
end

-- E3 视界线外：事件视界占据下半屏，吊舱坠入，光被折成弧。
local function e3()
  local c = U.canvas(80, 45)
  sky(c, 1203, 80, 0, 0, 79, 18)
  local cx, cy = 40, 38
  -- 视界（清空）+ 光子环
  for y = 20, 44 do
    for x = 0, 79 do
      if math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2) < 12.5 then U.cput(c, x, y, " ") end
    end
  end
  ring(c, cx, cy, 13.5, 13.5, "O", 3)
  ring(c, cx, cy, 14.6, 14.6, "o", 4)
  -- 被引力抬起的远侧盘面
  for deg = 180, 360, 2 do
    local a = math.rad(deg)
    U.cput(c, math.floor(cx + 26 * math.cos(a) + 0.5),
              math.floor(cy - 12 + 5 * math.sin(a) + 0.5), (deg % 8 == 0) and "=" or "-")
  end
  -- 吊舱：小三角 + 尾灯，正在坠入
  U.cstamp(c, 39, 6, [==[
   /\
  /  \
  '--'
]==])
  for i = 0, 9 do U.cput(c, 40, 9 + i, "~") end
  U.chline(c, 4, 43, 72, "-")
  return finish("ending.E3", c, nil, "80x45 结局 E3「视界线外」：吊舱坠入光子环")
end

-- E4 回声：人的轮廓被拆成波形，信号环向四面八方传出去。
local function e4()
  local c = U.canvas(80, 45)
  sky(c, 1204, 60)
  -- 人的轮廓（头 + 肩）
  U.cstamp(c, 8, 20, [==[
     ,------,
    /        \
   |          |
   |          |
    \        /
     '------'
    ,--------,
   /          \
  /            \
]==])
  -- 波形从轮廓里出来：一串横向正弦 + 字符密度渐变
  for x = 0, 79 do
    local y = 34 + math.floor(3 * math.sin(x / 6.0) + 0.5)
    local ch
    if x < 20 then ch = nil
    elseif x < 30 then ch = ","
    elseif x < 45 then ch = "~"
    elseif x < 60 then ch = "="
    else ch = "*" end
    if ch then U.cput(c, x, y, ch) end
  end
  for x = 0, 79 do
    local y = 38 + math.floor(2 * math.sin(x / 4.0 + 1.2) + 0.5)
    if x > 14 then U.cput(c, x, y, (x % 3 == 0) and "&" or "-") end
  end
  -- 外扩信号环
  ring(c, 40, 24, 30, 12, "%", 7)
  ring(c, 40, 24, 37, 15, "%", 11)
  return finish("ending.E4", c, nil, "80x45 结局 E4「回声」：轮廓化为波形与信号环")
end

local E = {
  E1 = e1(), E2 = e2(), E3 = e3(), E4 = e4(),
  order = { "E1", "E2", "E3", "E4" },
  blocks = {},
}
for _, id in ipairs(E.order) do E.blocks["ending." .. id] = E[id] end
return E

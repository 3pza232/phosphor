-- panel.lua —— 侧栏：分数 / 生命 / 幽灵图鉴 / 图例与操作（只读地渲染状态）
--
-- 面板坐标是局部的（左上角 0,0），宽度由 manifest 的 sidebar.w 决定。
-- 键位提示放在最底部，与其它卡带保持一致；移动键用方向符号——写单个
-- `[LEFT]` 会让人以为只有左键能走。

local Panel = {}

local Text = {
  zh = {
    score = "得分", best = "最高", level = "关卡", lives = "生命",
    ghosts = "幽灵", legend = "图例", dot = "· 豆子", power = "● 能量豆",
    fruit = "♥ 水果", keys = "操作", move = "[←↑↓→] 移动",
    scared = "吓退", eaten = "回巢", pause = "暂停",
  },
  en = {
    score = "SCORE", best = "BEST", level = "LEVEL", lives = "LIVES",
    ghosts = "GHOSTS", legend = "LEGEND", dot = "· dot", power = "● power",
    fruit = "♥ fruit", keys = "KEYS", move = "[←↑↓→] MOVE",
    scared = "scared", eaten = "eaten", pause = "PAUSE",
  },
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

local GHOST_NAMES = {
  blinky = { zh = "布林基", en = "Blinky" },
  pinky = { zh = "品琪", en = "Pinky" },
  inky = { zh = "因基", en = "Inky" },
  clyde = { zh = "克莱德", en = "Clyde" },
}
-- 与 main.lua 用的是同一套配色（幽灵在场上和面板里必须对得上）
local GHOST_COLORS = { blinky = "red", pinky = "magenta", inky = "cyan", clyde = "orange" }

function Panel.draw(game, cart_t)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end          -- 没声明侧栏（或被 mod 关掉）：什么都不画

  local t = L()
  local status = game:status()
  P.clear()

  P.print(1, 1, cart_t and cart_t.title or "CHOMP", C.yellow)
  P.print(1, 2, string.rep("·", pw - 2), C.dark_gray)

  P.print(1, 4, t.score, C.gray)
  P.print(1, 5, tostring(status.score), C.white)
  P.print(1, 7, t.best, C.gray)
  P.print(1, 8, tostring(game.best or 0), C.purple)
  P.print(1, 10, t.level, C.gray)
  P.print(1, 11, tostring(status.level), C.cyan)

  -- 生命：数字 + 心形行。吃到水果会加命，所以这一行是会变长的
  P.print(1, 13, t.lives .. " " .. status.lives, C.gray)
  local hearts = math.max(0, math.min(status.lives, (pw - 2) // 2))
  P.print(1, 14, string.rep("♥ ", hearts), C.red)

  -- 幽灵图鉴：颜色 + 名字 + 当前状态（这是本作最"有脸"的信息区）
  P.print(1, 16, t.ghosts, C.gray)
  for i, g in ipairs(status.ghosts) do
    local y = 16 + i
    local name = GHOST_NAMES[g.name]
    -- 名字是 { zh = …, en = … } 记录：取值与"缺 en 回落中文"都交给引擎
    local label = name and phos.lang.pick(name) or g.name
    local col = C[GHOST_COLORS[g.name]] or C.white
    local mark = "▲"
    if g.eaten then
      mark, col, label = "◦", C.dark_gray, t.eaten
    elseif g.scared then
      col, label = C.blue, t.scared
    end
    P.print(1, y, mark, col)
    P.print(3, y, label, col)
  end

  -- 图例与操作：最下面留给键位
  P.print(1, ph - 8, t.legend, C.gray)
  P.print(1, ph - 7, t.dot, C.gray)
  P.print(1, ph - 6, t.power, C.yellow)
  P.print(1, ph - 5, t.fruit, C.red)

  P.print(1, ph - 3, t.keys, C.gray)
  P.print(1, ph - 2, t.move, C.white)
  P.print(1, ph - 1, "[" .. phos.input.key_name("start") .. "] " .. t.pause, C.white)
end

return Panel

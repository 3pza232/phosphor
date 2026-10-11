-- 侧栏：得分 / 最高分 / 等级 / 行数 / 下一块 / 操作提示（只读）
--
-- 标签与值同处一行：人一眼看得清，agent 也能直接匹配 "得分 120"
-- 操作提示写**键盘上的键**（phos.input.key_name）：主机没有手柄，
-- 提示写着 SPACE 就必须真的按 SPACE 有效

local Game = require("game")

local Panel = {}

-- 界面文案：跟随机器的界面语言（新增语言加一列即可）
local Text = {
  zh = {title = "俄罗斯方块", score = "得分", best = "最高", level = "等级", lines = "行数",
        next = "下一块", move = "移动", rotate = "旋转", soft = "加速",
        hard = "硬降", pause = "暂停", restart = "重开", menu = "ESC 菜单"},
  en = {title = "TETRIS", score = "SCORE", best = "BEST", level = "LEVEL", lines = "LINES",
        next = "NEXT", move = "move", rotate = "rotate", soft = "soft drop",
        hard = "hard drop", pause = "pause", restart = "restart", menu = "ESC menu"},
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

local K = {
  space = phos.input.key_name("space"),
  start = phos.input.key_name("start"),
  select = phos.input.key_name("select"),
}

-- 下一块的预览：画在侧栏上半块。与井里一样每格铺 2×2 字符 —— 尺寸一致，看着才是
-- "同一套方块"；只是"看一眼形状"，所以不画满、留出呼吸的余地
local PREVIEW = 2
local function draw_next(P, C, kind, x, y)
  if not kind then return end
  local color = C[Game.color_key(kind)]
  for _, c in ipairs(Game.cells(kind)) do
    for dy = 0, PREVIEW - 1 do
      for dx = 0, PREVIEW - 1 do
        P.put(x + (c[1] - 1) * PREVIEW + dx, y + (c[2] - 1) * PREVIEW + dy, "#", color, color)
      end
    end
  end
end

function Panel.draw(state)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end

  P.clear()
  P.print(1, 1, L().title, C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  P.print(1, 4, L().score .. " " .. tostring(state.score), C.white)
  P.print(1, 5, L().best .. " " .. tostring(state.best), C.cyan)
  P.print(1, 7, L().level .. " " .. tostring(state.level), C.green)
  P.print(1, 8, L().lines .. " " .. tostring(state.lines), C.gray)

  P.print(1, 10, L().next, C.gray)
  draw_next(P, C, state.next_kind, 3, 12)

  P.print(1, ph - 6, L().move, C.dark_gray)
  P.print(1, ph - 5, L().rotate, C.dark_gray)
  P.print(1, ph - 4, L().soft, C.dark_gray)
  P.print(1, ph - 3, K.space .. " " .. L().hard, C.dark_gray)
  P.print(1, ph - 2, K.start .. " " .. L().pause, C.dark_gray)
  P.print(1, ph - 1, L().menu, C.dark_gray)
end

return Panel

-- 侧栏：得分 / 最高分 / 余命 / 关卡（只读）
-- 标签与值同处一行：人一眼看得清，agent 也能直接匹配 "得分 10"
--
-- 操作提示写**键盘上的键**（phos.input.key_name）：主机没有手柄，
-- 提示写着 A 就必须真的按 A 有效，否则玩家会以为游戏坏了。

local Game = require("game")

local Panel = {}

-- 界面文案：跟随机器的界面语言（新增语言加一列即可）
local Text = {
  zh = {title = "打砖块", score = "得分", best = "最高", level = "关卡", bricks = "余砖",
        time = "时间", lives = "命", move = "方向键移动", launch = "发射", pause = "暂停",
        restart = "重开", menu = "ESC 菜单"},
  en = {title = "BRICKS", score = "SCORE", best = "BEST", level = "LEVEL", bricks = "LEFT",
        time = "TIME", lives = "LIVES", move = "arrows move", launch = "launch", pause = "pause",
        restart = "restart", menu = "ESC menu"},
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

local K = {
  a = phos.input.key_name("a"),
  start = phos.input.key_name("start"),
  select = phos.input.key_name("select"),
}

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
  P.print(1, 8, L().bricks .. " " .. tostring(state.bricks_left), C.gray)
  P.print(1, 10, L().time .. " " .. Game.clock(state.time), C.gray)

  local lives = ""
  for i = 1, math.max(0, state.lives) do lives = lives .. "#" end
  P.print(1, 12, L().lives .. " " .. (lives == "" and "-" or lives), C.red)

  P.print(1, ph - 5, L().move, C.dark_gray)
  P.print(1, ph - 4, K.a .. " " .. L().launch, C.dark_gray)
  P.print(1, ph - 3, K.start .. " " .. L().pause, C.dark_gray)
  P.print(1, ph - 2, K.select .. " " .. L().restart, C.dark_gray)
  P.print(1, ph - 1, L().menu, C.dark_gray)
end

return Panel

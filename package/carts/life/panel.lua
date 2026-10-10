-- 侧栏：只读状态展示（不修改任何游戏状态）

local Panel = {}

-- 提示里写**键盘上真正该按的键**，而不是手柄按钮名：
-- 主机没有手柄，玩家面前只有键盘（映射改了这里会自动跟着变）
local K = {
  a = phos.input.key_name("a"),
  b = phos.input.key_name("b"),
  x = phos.input.key_name("x"),
  y = phos.input.key_name("y"),
  start = phos.input.key_name("start"),
  select = phos.input.key_name("select"),
}

-- 界面文案：跟随机器的界面语言（含对齐用的空格，保证两列对得齐）
local Text = {
  zh = {title = "生命游戏", rule = "B3/S23  环面", generation = "代   ", alive = "存活 ",
        status = "状态 ", pattern = "图案", cursor = "光标 %d,%d", running = "运行中",
        paused = "已暂停", swap = "切换", stamp = "盖印", next_pattern = "下一图案",
        step = "单步", run_pause = "运行/暂停", clear = "清空", move = "方向键移动",
        menu = "ESC 暂停"},
  en = {title = "LIFE", rule = "B3/S23  torus", generation = "GEN   ", alive = "ALIVE ",
        status = "STATE ", pattern = "PATTERN", cursor = "cursor %d,%d", running = "RUNNING",
        paused = "PAUSED", swap = "swap", stamp = "stamp", next_pattern = "next pattern",
        step = "step", run_pause = "run/pause", clear = "clear", move = "arrows move",
        menu = "ESC pause"},
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

-- 内部状态 -> 面板标签（底部遥测行仍报英文 RUNNING/PAUSED，与主机同一套政策）
local function state_label(running)
  return running and L().running or L().paused
end

function Panel.draw(state)
  local P = phos.panel
  local C = phos.color
  local pw, ph = P.size()
  if pw == 0 then return end

  P.clear()
  P.print(1, 1, L().title, C.green)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)
  P.print(1, 3, L().rule, C.gray)

  P.print(1, 5, L().generation .. tostring(state.generation), C.white)
  P.print(1, 6, L().alive .. tostring(state.population), C.yellow)
  P.print(1, 7, L().status .. state_label(state.running),
          state.running and C.green or C.orange)

  P.print(1, 9, L().pattern, C.dark_gray)
  P.print(1, 10, state.pattern, C.cyan)  -- 图案名来自卡带数据，属内容，不在这里翻译
  P.print(1, 11, string.format(L().cursor, state.cursor_x, state.cursor_y), C.gray)

  P.print(1, ph - 7, K.a .. " " .. L().swap .. "  " .. K.b .. " " .. L().stamp, C.dark_gray)
  P.print(1, ph - 6, K.y .. " " .. L().next_pattern, C.dark_gray)
  P.print(1, ph - 5, K.x .. " " .. L().step, C.dark_gray)
  P.print(1, ph - 4, K.start .. " " .. L().run_pause, C.dark_gray)
  P.print(1, ph - 3, K.select .. " " .. L().clear, C.dark_gray)
  P.print(1, ph - 2, L().move, C.dark_gray)
  P.print(1, ph - 1, L().menu, C.dark_gray)
end

return Panel

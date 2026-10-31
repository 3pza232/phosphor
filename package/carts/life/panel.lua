-- panel.lua —— 侧栏：只读状态展示（不修改任何游戏状态）。
-- 组件化后不再手写局部坐标；键位提示写键盘上真正该按的键。
local Panel = {}

local K = {
  a = phos.input.key_name("a"), b = phos.input.key_name("b"),
  x = phos.input.key_name("x"), y = phos.input.key_name("y"),
  start = phos.input.key_name("start"), select = phos.input.key_name("select"),
}

local Text = {
  zh = {title = "生命游戏", rule = "B3/S23  环面", generation = "代", alive = "存活",
        status = "状态", pattern = "图案", cursor = "光标 %d,%d",
        running = "运行中", paused = "已暂停", swap = "切换", stamp = "盖印",
        next_pattern = "下一图案", step = "单步", run_pause = "运行/暂停", clear = "清空",
        move = "方向键移动", menu = "ESC 暂停"},
  en = {title = "LIFE", rule = "B3/S23  torus", generation = "GEN", alive = "ALIVE",
        status = "STATE", pattern = "PATTERN", cursor = "cursor %d,%d",
        running = "RUNNING", paused = "PAUSED", swap = "swap", stamp = "stamp",
        next_pattern = "next pattern", step = "step", run_pause = "run/pause", clear = "clear",
        move = "arrows move", menu = "ESC pause"},
}
local function L() return phos.lang.dict(Text) end

---@param state table 只读快照（generation/population/running/pattern/cursor_x/cursor_y）
function Panel.draw(state)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local t = L()
  local rows = {
    { kind = "text", text = t.title, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "text", text = t.rule, dim = true },
    { kind = "stat", text = t.generation, value = tostring(state.generation), label_w = 7 },
    { kind = "stat", text = t.alive, value = tostring(state.population), label_w = 7, accent = true },
    { kind = "stat", text = t.status, value = state.running and t.running or t.paused,
      label_w = 7, fg = state.running and "green" or "orange" },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = t.pattern, value = state.pattern, label_w = 7 },
    { kind = "text", text = string.format(t.cursor, state.cursor_x, state.cursor_y), dim = true },
    { kind = "spacer", grow = 1 },
    { kind = "text", text = K.a .. " " .. t.swap .. "   " .. K.b .. " " .. t.stamp, dim = true },
    { kind = "text", text = K.y .. " " .. t.next_pattern, dim = true },
    { kind = "text", text = K.x .. " " .. t.step, dim = true },
    { kind = "text", text = K.start .. " " .. t.run_pause, dim = true },
    { kind = "text", text = K.select .. " " .. t.clear, dim = true },
    { kind = "text", text = t.move, dim = true },
    { kind = "text", text = t.menu, dim = true },
  }

  phos.ui.render{
    screen = "panel",
    surface = "panel",
    input = false,
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 0,
    children = rows,
  }
end

return Panel

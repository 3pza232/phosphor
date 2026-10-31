-- panel.lua —— 侧栏：得分 / 最高分 / 关卡 / 余砖 / 时间 / 命（只读）。
--
-- 声明式组件：标签与值的对齐、宽度变化、裁剪都交给引擎；卡带只描述内容。
local Panel = {}

local Text = {
  zh = {title = "打砖块", level = "关卡", bricks = "余砖", time = "时间", lives = "命",
        move = "方向键移动", launch = "发射", pause = "暂停", restart = "重开", menu = "ESC 菜单"},
  en = {title = "BRICKS", level = "LEVEL", bricks = "LEFT", time = "TIME", lives = "LIVES",
        move = "arrows move", launch = "launch", pause = "pause", restart = "restart",
        menu = "ESC menu"},
}
local function L() return phos.lang.dict(Text) end
local function KEY(name) return phos.input.key_name(name) end

function Panel.draw(state)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local words = phos.lang.shared()
  local t = L()
  local lives = string.rep("#", math.max(0, state.lives))
  local rows = {
    { kind = "text", text = t.title, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = words.score, value = phos.text.score(state.score), label_w = 7 },
    { kind = "stat", text = words.best, value = phos.text.score(state.best), label_w = 7, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = t.level, value = tostring(state.level), label_w = 7 },
    { kind = "stat", text = t.bricks, value = tostring(state.bricks_left), label_w = 7 },
    { kind = "stat", text = t.time, value = phos.text.clock(state.time), label_w = 7 },
    { kind = "stat", text = t.lives, value = lives ~= "" and lives or "-", label_w = 7,
      fg = "red" },
    { kind = "spacer", grow = 1 },
    { kind = "text", text = t.move, dim = true },
    { kind = "text", text = KEY("a") .. " " .. t.launch, dim = true },
    { kind = "text", text = KEY("start") .. " " .. t.pause, dim = true },
    { kind = "text", text = KEY("select") .. " " .. t.restart, dim = true },
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

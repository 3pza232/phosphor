-- panel.lua —— 右侧栏：棋谱、被吃子、键位提示（提示放最下面，与其它卡带一致）。
-- 声明式组件：棋谱行数按面板高度自适应，裁剪与对齐由引擎负责。
local Panel = {}

local Text = {
  zh = { log = "棋谱", cap = "被吃", red = "红", black = "黑",
         move = "方向键 移动", ab = "[%s] 选/落  [%s] 取消",
         undo = "[%s] 悔棋", pause = "[%s] 暂停" },
  en = { log = "MOVES", cap = "CAPTURED", red = "R", black = "B",
         move = "ARROWS move", ab = "[%s] pick  [%s] cancel",
         undo = "[%s] undo", pause = "[%s] pause" },
}

local function KEY(name) return phos.input.key_name(name) end

function Panel.draw(game, cart)
  local pw, ph = phos.panel.size()
  if pw == 0 then return end

  local t = phos.lang.dict(Text)
  local cap_line = function(side)
    local out = ""
    for _, p in ipairs(game.captured[side]) do out = out .. game:name_of(p) end
    return out
  end

  local rows = {
    { kind = "text", text = cart.name, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "spacer", height = 1 },
    { kind = "text", text = t.log, dim = true },
  }
  -- 棋谱只显示最近几条：留出被吃区与键位的固定高度
  local show = math.max(0, (ph - 8) - 5)
  local first = math.max(1, #game.log - show + 1)
  for i = first, #game.log do
    local m = game.log[i]
    local who = (m.s == "r") and t.red or t.black
    rows[#rows + 1] = {
      kind = "text",
      text = string.format("%s %s %d,%d-%d,%d", who, game:name_of(m),
                           m.f + 1, m.r + 1, m.tf + 1, m.tr + 1),
      fg = "white",
    }
  end

  rows[#rows + 1] = { kind = "spacer", grow = 1 }
  rows[#rows + 1] = { kind = "text", text = t.cap, dim = true }
  rows[#rows + 1] = { kind = "text", text = cap_line("b") }
  rows[#rows + 1] = { kind = "text", text = cap_line("r"), fg = "red" }
  rows[#rows + 1] = { kind = "divider", fg = "dark_gray" }
  rows[#rows + 1] = { kind = "text", text = t.move, dim = true }
  rows[#rows + 1] = { kind = "text", text = string.format(t.ab, KEY("a"), KEY("b")) }
  rows[#rows + 1] = { kind = "text", text = string.format(t.undo, KEY("backspace")), dim = true }
  rows[#rows + 1] = { kind = "text", text = string.format(t.pause, KEY("start")), dim = true }

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

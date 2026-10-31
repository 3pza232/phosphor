-- panel.lua —— 侧栏：得分 / 最高分 / 等级 / 行数 / 下一块 / 操作提示（只读）。
--
-- 统计部分用声明式组件（对齐/裁剪/宽度交给引擎）；"下一块"的预览需要逐格画，
-- 由卡带在预留的 spacer 区域里自己铺（引擎只管布局，不替卡带画像素）。
local Game = require("game")

local Panel = {}

local Text = {
  zh = {title = "俄罗斯方块", level = "等级", lines = "行数", next = "下一块",
        move = "移动", rotate = "旋转", soft = "加速", hard = "硬降",
        pause = "暂停", restart = "重开", menu = "ESC 菜单"},
  en = {title = "TETRIS", level = "LEVEL", lines = "LINES", next = "NEXT",
        move = "move", rotate = "rotate", soft = "soft drop", hard = "hard drop",
        pause = "pause", restart = "restart", menu = "ESC menu"},
}
local function L() return phos.lang.dict(Text) end
local function KEY(name) return phos.input.key_name(name) end

local PREVIEW = 2
local function draw_next(kind, x, y)
  if not kind then return end
  local C = phos.color
  local color = C[Game.color_key(kind)]
  for _, c in ipairs(Game.cells(kind)) do
    for dy = 0, PREVIEW - 1 do
      for dx = 0, PREVIEW - 1 do
        phos.panel.put(x + (c[1] - 1) * PREVIEW + dx, y + (c[2] - 1) * PREVIEW + dy, "#", color, color)
      end
    end
  end
end

---@param state table 只读快照（score/best/level/lines/next_kind）
function Panel.draw(state)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local words = phos.lang.shared()
  local t = L()
  local rows = {
    { kind = "text", text = t.title, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = words.score, value = phos.text.score(state.score), label_w = 7 },
    { kind = "stat", text = words.best, value = phos.text.score(state.best), label_w = 7,
      accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = t.level, value = tostring(state.level), label_w = 7 },
    { kind = "stat", text = t.lines, value = tostring(state.lines), label_w = 7 },
    { kind = "text", text = t.next, dim = true },
    { kind = "spacer", height = 5 },          -- 预览区：下面由 draw_next 逐格铺
    { kind = "spacer", grow = 1 },
    { kind = "text", text = t.move, dim = true },
    { kind = "text", text = t.rotate, dim = true },
    { kind = "text", text = t.soft, dim = true },
    { kind = "text", text = KEY("space") .. " " .. t.hard, dim = true },
    { kind = "text", text = KEY("start") .. " " .. t.pause, dim = true },
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

  -- 预览区起点：标题/分隔线/4 行 stat/下一块标签之后（行号从面板顶部算）
  draw_next(state.next_kind, 3, 10)
end

return Panel

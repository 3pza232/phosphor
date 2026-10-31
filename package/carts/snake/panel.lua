-- panel.lua —— 侧栏面板（成绩与图例）。只读地渲染游戏与排行榜状态。
--
-- 界面用声明式组件描述：坐标/裁剪/对齐由引擎负责，宽度运行时变化也不用重算。
local Panel = {}

-- 卡带自己的专有词（通用词由 phos.lang.shared 提供）
local Text = {
  zh = {title = "贪吃蛇", length = "长度", records = "得分纪录", empty = "(空)",
        legend = "图例", head = "@ 蛇头", body = "o 蛇身", food = "O 食物",
        menu = "ESC 暂停"},
  en = {title = "SNAKE", length = "LENGTH", records = "HIGH SCORES", empty = "(none)",
        legend = "LEGEND", head = "@ head", body = "o body", food = "O food",
        menu = "ESC pause"},
}
local function L() return phos.lang.dict(Text) end

---@param game table 规则对象
---@param board phos.Score 排行榜
function Panel.draw(game, board)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local words = phos.lang.shared()
  local t = L()
  local rows = {
    { kind = "text", text = t.title, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = words.score, value = tostring(game.score), label_w = 8 },
    { kind = "stat", text = words.best, value = tostring(board:best()), label_w = 8, accent = true },
    { kind = "text", text = t.length .. " " .. tostring(game:length()) },
    { kind = "divider", fg = "dark_gray" },
    { kind = "text", text = t.records, dim = true },
  }
  local records = board:list()
  if #records == 0 then
    rows[#rows + 1] = { kind = "text", text = t.empty, dim = true }
  else
    for i, value in ipairs(records) do
      rows[#rows + 1] = { kind = "stat", text = i .. ".", value = tostring(value), label_w = 3,
                          accent = i == 1 }
    end
  end
  rows[#rows + 1] = { kind = "spacer", grow = 1 }
  rows[#rows + 1] = { kind = "text", text = t.legend, dim = true }
  rows[#rows + 1] = { kind = "text", text = t.head, fg = "green" }
  rows[#rows + 1] = { kind = "text", text = t.body, fg = "cyan" }
  rows[#rows + 1] = { kind = "text", text = t.food, fg = "red" }
  rows[#rows + 1] = { kind = "text", text = t.menu, dim = true }

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

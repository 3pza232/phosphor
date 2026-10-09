-- panel.lua —— 侧栏面板（成绩与图鉴），只读地渲染游戏与分数状态

local Panel = {}

-- 界面文案：跟随机器的界面语言（新增语言加一列即可）
local Text = {
  zh = {title = "贪吃蛇", score = "得分", best = "最高", length = "长度 ", records = "得分纪录",
        empty = "(空)", legend = "图例", head = "@ 蛇头", body = "o 蛇身", food = "O 食物",
        menu = "ESC 暂停"},
  en = {title = "SNAKE", score = "SCORE", best = "BEST", length = "LENGTH ", records = "HIGH SCORES",
        empty = "(none)", legend = "LEGEND", head = "@ head", body = "o body", food = "O food",
        menu = "ESC pause"},
}
local function L() return Text[phos.sys.language()] or Text.zh end

local function section(P, C, y, title)
  P.print(1, y, title, C.dark_gray)
end

function Panel.draw(game, scores)
  local C = phos.color
  local P = phos.panel
  local pw, ph = P.size()
  if pw == 0 then return end

  P.clear()

  P.print(1, 1, L().title, C.green)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  P.print(1, 4, L().score, C.gray)
  P.print(1, 5, tostring(game.score), C.yellow)

  P.print(1, 7, L().best, C.gray)
  P.print(1, 8, tostring(scores.best()), C.orange)

  P.print(1, 10, L().length .. game:length(), C.cyan)

  section(P, C, 12, L().records)
  if #scores.list == 0 then
    P.print(1, 13, L().empty, C.dark_gray)
  else
    for i, value in ipairs(scores.list) do
      P.print(1, 12 + i, string.format("%d. %d", i, value),
              i == 1 and C.orange or C.white)
    end
  end

  section(P, C, ph - 6, L().legend)
  P.print(1, ph - 5, L().head, C.green)
  P.print(1, ph - 4, L().body, C.cyan)
  P.print(1, ph - 3, L().food, C.red)
  P.print(1, ph - 1, L().menu, C.dark_gray)
end

return Panel

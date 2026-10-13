-- panel.lua —— 右侧栏：棋谱、被吃子、状态。
local Panel = {}

local Text = {
  zh = { log = "棋谱", cap = "被吃", red = "红", black = "黑", keys = "方向 选子/落子" },
  en = { log = "MOVES", cap = "CAPTURED", red = "RED", black = "BLK", keys = "pick / drop" },
}

function Panel.draw(game, cart)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end

  local t = phos.lang.dict(Text)
  P.clear()
  P.print(1, 1, phos.text.fit(cart.name, pw - 2), C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  -- 棋谱：滚动到最近几条
  P.print(1, 4, t.log, C.gray)
  local show = ph - 10
  local first = math.max(1, #game.log - show + 1)
  for i = first, #game.log do
    local m = game.log[i]                    -- 结构化的一步；文案按界面语言拼
    local who = (m.s == "r") and t.red or t.black
    local line = string.format("%s %s %d,%d-%d,%d", who, game:name_of(m),
                               m.f + 1, m.r + 1, m.tf + 1, m.tr + 1)
    P.print(1, 5 + (i - first), phos.text.fit(line, pw - 2), C.white)
  end

  -- 被吃子（红吃掉的黑子 / 黑吃掉的红子）
  P.print(1, ph - 4, t.cap, C.gray)
  local function line(side)
    local out = ""
    for _, p in ipairs(game.captured[side]) do out = out .. game:name_of(p) end
    return out
  end
  P.print(1, ph - 3, phos.text.fit(line("b"), pw - 2), C.white)
  P.print(1, ph - 2, phos.text.fit(line("r"), pw - 2), C.red)
  P.print(1, ph - 1, t.keys, C.dark_gray)
end

return Panel

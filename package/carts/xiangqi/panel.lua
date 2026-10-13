-- panel.lua —— 右侧栏：棋谱、被吃子、键位提示（与其它卡带一致，提示放最下面）。
local Panel = {}

local Text = {
  zh = { log = "棋谱", cap = "被吃", red = "红", black = "黑",
         move = "方向键 移动", ab = "[%s] 选/落  [%s] 取消",
         undo = "[%s] 悔棋", new = "[%s] 重开" },
  en = { log = "MOVES", cap = "CAPTURED", red = "R", black = "B",
         move = "ARROWS move", ab = "[%s] pick  [%s] cancel",
         undo = "[%s] undo", new = "[%s] new" },
}

function Panel.draw(game, cart)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end

  local t = phos.lang.dict(Text)
  P.clear()
  P.print(1, 1, phos.text.fit(cart.name, pw - 2), C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  -- 棋谱：滚动到最近几条（占据被吃区之上的空间）
  P.print(1, 4, t.log, C.gray)
  local show = math.max(0, (ph - 8) - 5)
  local first = math.max(1, #game.log - show + 1)
  for i = first, #game.log do
    local m = game.log[i]                    -- 结构化的一步；文案按界面语言拼
    local who = (m.s == "r") and t.red or t.black
    local line = string.format("%s %s %d,%d-%d,%d", who, game:name_of(m),
                               m.f + 1, m.r + 1, m.tf + 1, m.tr + 1)
    P.print(1, 5 + (i - first), phos.text.fit(line, pw - 2), C.white)
  end

  -- 被吃子
  local function cap_line(side)
    local out = ""
    for _, p in ipairs(game.captured[side]) do out = out .. game:name_of(p) end
    return out
  end
  P.print(1, ph - 7, t.cap, C.gray)
  P.print(1, ph - 6, phos.text.fit(cap_line("b"), pw - 2), C.white)
  P.print(1, ph - 5, phos.text.fit(cap_line("r"), pw - 2), C.red)

  -- 键位提示：真实键名（key_name），放最下面
  local kn = phos.input.key_name
  P.print(1, ph - 4, phos.text.fit(t.move, pw - 2), C.dark_gray)
  P.print(1, ph - 3, phos.text.fit(string.format(t.ab, kn("a"), kn("b")), pw - 2), C.white)
  P.print(1, ph - 2, phos.text.fit(string.format(t.undo, kn("backspace")), pw - 2), C.gray)
  P.print(1, ph - 1, phos.text.fit(string.format(t.new, kn("start")), pw - 2), C.gray)
end

return Panel

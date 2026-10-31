-- panel.lua —— 侧栏：分数 / 生命 / 幽灵图鉴 / 图例与操作（只读地渲染状态）。
-- 声明式组件：对齐/裁剪/宽度都交给引擎；幽灵图鉴按行动态生成。
local Panel = {}

local Text = {
  zh = {level = "关卡", lives = "生命", ghosts = "幽灵", legend = "图例",
        dot = "· 豆子", power = "● 能量豆", fruit = "♥ 水果", keys = "操作",
        move = "[←↑↓→] 移动", scared = "吓退", eaten = "回巢", pause = "暂停"},
  en = {level = "LEVEL", lives = "LIVES", ghosts = "GHOSTS", legend = "LEGEND",
        dot = "· dot", power = "● power", fruit = "♥ fruit", keys = "KEYS",
        move = "[←↑↓→] MOVE", scared = "scared", eaten = "eaten", pause = "PAUSE"},
}
local function L() return phos.lang.dict(Text) end

local GHOST_NAMES = {
  blinky = { zh = "布林基", en = "Blinky" },
  pinky = { zh = "品琪", en = "Pinky" },
  inky = { zh = "因基", en = "Inky" },
  clyde = { zh = "克莱德", en = "Clyde" },
}
local GHOST_COLORS = { blinky = "red", pinky = "magenta", inky = "cyan", clyde = "orange" }

---@param game table 规则对象
---@param board phos.Score 最高分排行榜
function Panel.draw(game, board)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local words = phos.lang.shared()
  local t = L()
  local status = game:status()
  local hearts = string.rep("♥ ", math.max(0, status.lives))
  local rows = {
    { kind = "text", text = phos.cart.info().name, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = words.score, value = phos.text.score(status.score), label_w = 7 },
    { kind = "stat", text = words.best, value = phos.text.score(math.max(board:best(), game.best or 0)),
      label_w = 7, accent = true },
    { kind = "stat", text = t.level, value = tostring(status.level), label_w = 7 },
    { kind = "stat", text = t.lives, value = tostring(status.lives), label_w = 7 },
    { kind = "text", text = hearts ~= "" and hearts or "-", fg = "red" },
    { kind = "divider", fg = "dark_gray" },
    { kind = "text", text = t.ghosts, dim = true },
  }
  for _, g in ipairs(status.ghosts) do
    local name = GHOST_NAMES[g.name]
    local label = name and phos.lang.pick(name) or g.name
    local color = GHOST_COLORS[g.name] or "white"
    local mark = "▲"
    if g.eaten then
      mark, color, label = "◦", "dark_gray", t.eaten
    elseif g.scared then
      color, label = "blue", t.scared
    end
    rows[#rows + 1] = { kind = "text", text = mark .. " " .. label, fg = color }
  end
  rows[#rows + 1] = { kind = "spacer", grow = 1 }
  rows[#rows + 1] = { kind = "text", text = t.legend, dim = true }
  rows[#rows + 1] = { kind = "text", text = t.dot, dim = true }
  rows[#rows + 1] = { kind = "text", text = t.power, fg = "yellow" }
  rows[#rows + 1] = { kind = "text", text = t.fruit, fg = "red" }
  rows[#rows + 1] = { kind = "divider", fg = "dark_gray" }
  rows[#rows + 1] = { kind = "text", text = t.keys, dim = true }
  rows[#rows + 1] = { kind = "text", text = t.move, dim = true }
  rows[#rows + 1] = { kind = "text",
                      text = "[" .. phos.input.key_name("start") .. "] " .. t.pause, dim = true }

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

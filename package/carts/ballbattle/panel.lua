-- panel.lua —— 右侧栏：排行榜 / 小地图 / 最高纪录（颜色全用主题色板）。
--
-- 排行榜与键位用声明式组件；小地图必须逐格画，由卡带在预留的固定区域内自绘
-- （组件负责布局，像素仍归卡带——与 tetris 的下一块预览同一分工）。
local Panel = {}

local RANK_MAX = 15
local MAP_LABEL_Y = 21  -- "地图"标题所在行（排在排行榜之后）
local MAP_TOP = 22      -- 小地图起始行
local MAP_H = 10

local Text = {
  zh = { rank = "排行榜", map = "地图", best = "最高纪录", you = "你",
         move = "方向键 移动", z = "[%s] 吐食", x = "[%s] 分裂" },
  en = { rank = "LEADERS", map = "MAP", best = "BEST", you = "YOU",
         move = "ARROWS move", z = "[%s] EJECT", x = "[%s] SPLIT" },
}

local function minimap(game)
  local pw = phos.panel.size()
  local mw, mh = pw - 2, MAP_H
  local C = phos.color
  local map = phos.ui.region(1, MAP_TOP, mw, mh, { surface = "panel" })
  map:frame("")
  local iw, ih = mw - 2, mh - 2
  for _, b in ipairs(game.blobs) do
    local mx = 1 + math.floor(b.x / game.WORLD_W * (iw - 1) + 0.5)
    local my = 1 + math.floor(b.y / game.WORLD_H * (ih - 1) + 0.5)
    if b.role == "player" then
      map:put(mx, my, "O", C.cyan)
    else
      map:put(mx, my, "o", C.dark_gray)
    end
  end
end

function Panel.draw(game, cart, best)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local t = phos.lang.dict(Text)
  local listed = game:leaderboard()
  local top = (listed[1] and listed[1].m) or 1
  local rows = {
    { kind = "text", text = cart.name, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "spacer", height = 1 },
    { kind = "text", text = t.rank, dim = true },
  }
  for i = 1, RANK_MAX do
    local e = listed[i]
    if e then
      local who = (e.role == "player") and t.you or ("AI" .. (e.hue or 0))
      -- 星数 = 相对大小（√质量比），榜首 9 颗，最少 1
      local stars = math.max(1, math.min(9, math.floor(math.sqrt(e.m / top) * 9 + 0.5)))
      rows[#rows + 1] = {
        kind = "text",
        text = string.format("%d %s %s", i, phos.text.pad(who, 5), string.rep("*", stars)),
        fg = e.role == "player" and "cyan" or "white",
      }
    else
      rows[#rows + 1] = { kind = "text", text = " " }
    end
  end
  rows[#rows + 1] = { kind = "spacer", height = 1 }
  rows[#rows + 1] = { kind = "text", text = t.map, dim = true }
  rows[#rows + 1] = { kind = "spacer", height = MAP_H }  -- 小地图预留区（下面自绘）
  rows[#rows + 1] = { kind = "spacer", grow = 1 }
  rows[#rows + 1] = { kind = "text", text = t.best, dim = true }
  rows[#rows + 1] = { kind = "text", text = tostring(best), fg = "orange" }
  rows[#rows + 1] = { kind = "text", text = t.move, dim = true }
  rows[#rows + 1] = { kind = "text", text = string.format(t.z, phos.input.key_name("z")), dim = true }
  rows[#rows + 1] = { kind = "text", text = string.format(t.x, phos.input.key_name("x")), dim = true }

  phos.ui.render{
    screen = "panel",
    surface = "panel",
    input = false,
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 0,
    children = rows,
  }

  minimap(game)
end

return Panel

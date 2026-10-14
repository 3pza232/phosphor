-- panel.lua —— 右侧栏：排行榜、小地图、最高纪录。颜色全用主题色板。
local Panel = {}

local RANK_MAX = 15     -- 排行榜最多显示几位
local MAP_LABEL_Y = 21  -- "地图"标题所在行（排在排行榜之后）
local MAP_TOP = 22      -- 小地图起始行

local Text = {
  zh = { rank = "排行榜", map = "地图", best = "最高纪录", you = "你", keys = "方向键 移动" },
  en = { rank = "LEADERS", map = "MAP", best = "BEST", you = "YOU", keys = "ARROWS move" },
}

local function minimap(game, C)
  local pw = phos.panel.size()
  local mw, mh = pw - 2, 10
  local map = phos.ui.region(1, MAP_TOP, mw, mh, { surface = "panel" })
  map:frame("")
  local iw, ih = mw - 2, mh - 2                      -- 边框内可画范围
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
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end

  local t = phos.lang.dict(Text)
  P.clear()
  P.print(1, 1, phos.text.fit(cart.name, pw - 2), C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  P.print(1, 4, t.rank, C.gray)
  local listed = game:ranked()
  local top = (listed[1] and listed[1].r) or 1     -- 榜首半径 = 参照
  for i = 1, math.min(RANK_MAX, #listed) do
    local b = listed[i]
    local who = (b.role == "player") and t.you or ("AI" .. (b.hue or 0))
    -- 星数 = **相对大小**：榜首 9 颗，其余按半径成比例，最少 1 颗（不再按绝对半径）
    local stars = math.max(1, math.min(9, math.floor(b.r / top * 9 + 0.5)))
    local line = string.format("%d %s %s", i, phos.text.pad(who, 5), string.rep("*", stars))
    P.print(1, 4 + i, phos.text.fit(line, pw - 2), (b.role == "player") and C.cyan or C.white)
  end

  P.print(1, MAP_LABEL_Y, t.map, C.gray)
  minimap(game, C)

  P.print(1, ph - 3, t.best, C.gray)
  P.print(1, ph - 2, tostring(best()), C.orange)
  P.print(1, ph - 1, t.keys, C.dark_gray)
end

return Panel

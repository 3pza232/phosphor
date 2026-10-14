-- panel.lua —— 右侧栏：排行榜、小地图、最高纪录。颜色全用主题色板。
local Panel = {}

local RANK_MAX = 15     -- 排行榜最多显示几位
local MAP_LABEL_Y = 21  -- "地图"标题所在行（排在排行榜之后）
local MAP_TOP = 22      -- 小地图起始行

local Text = {
  zh = { rank = "排行榜", map = "地图", best = "最高纪录", you = "你",
         move = "方向键 移动", z = "[%s] 吐食", x = "[%s] 分裂" },
  en = { rank = "LEADERS", map = "MAP", best = "BEST", you = "YOU",
         move = "ARROWS move", z = "[%s] EJECT", x = "[%s] SPLIT" },
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
  local listed = game:leaderboard()        -- 玩家的所有细胞已合成一行
  local top = (listed[1] and listed[1].m) or 1
  for i = 1, math.min(RANK_MAX, #listed) do
    local e = listed[i]
    local who = (e.role == "player") and t.you or ("AI" .. (e.hue or 0))
    -- 星数 = **相对大小**：榜首 9 颗，其余按半径比例（√质量比），上限 9、最少 1
    local stars = math.max(1, math.min(9, math.floor(math.sqrt(e.m / top) * 9 + 0.5)))
    local line = string.format("%d %s %s", i, phos.text.pad(who, 5), string.rep("*", stars))
    P.print(1, 4 + i, phos.text.fit(line, pw - 2), (e.role == "player") and C.cyan or C.white)
  end

  P.print(1, MAP_LABEL_Y, t.map, C.gray)
  minimap(game, C)

  -- 键位提示（底部那行已去掉，提示统一放这里，用真实键名）
  local kn = phos.input.key_name
  P.print(1, ph - 5, t.best, C.gray)
  P.print(1, ph - 4, tostring(best()), C.orange)
  P.print(1, ph - 3, t.move, C.dark_gray)
  P.print(1, ph - 2, string.format(t.z, kn("z")), C.dark_gray)
  P.print(1, ph - 1, string.format(t.x, kn("x")), C.dark_gray)
end

return Panel

-- panel.lua —— 右侧栏：排行榜、最高纪录、操作提示。
local Panel = {}
Panel.__index = Panel

local Text = {
  zh = { rank = "排行榜", best = "最高纪录", you = "你", keys = "方向键 移动" },
  en = { rank = "LEADERS", best = "BEST", you = "YOU", keys = "ARROWS move" },
}

---@param game table  规则对象
---@param cart table  卡带身份
---@param best fun(): integer  取最高纪录
function Panel.draw(game, cart, best)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end

  local t = phos.lang.dict(Text)
  P.clear()

  P.print(1, 1, phos.text.fit(cart.name, pw - 2), C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  local st = game:status()
  P.print(1, 4, t.rank, C.gray)
  local listed = game:ranked()
  for i, b in ipairs(listed) do
    if i > 7 then break end
    local who = (b.role == "player") and t.you or ("AI" .. b.ai)
    local line = string.format("%d %s %s", i, phos.text.pad(who, 5), string.rep("*", math.max(1, math.floor(b.r))))
    P.print(1, 5 + i, phos.text.fit(line, pw - 2), (b.role == "player") and C.cyan or C.white)
  end

  P.print(1, ph - 4, t.best, C.gray)
  P.print(1, ph - 3, tostring(best()), C.orange)
  P.print(1, ph - 1, t.keys, C.dark_gray)
end

return Panel

-- CRIMSON ARCADE：红白街机机台（深红机身 + 金色高亮）
-- 铭牌只用 ASCII（内容包沙箱里没有语言 API）
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

return {
  screen = { x = 2, y = 3 },
  palette = "default",
  left  = "#|",
  right = "|#",
  top = {
    "#" .. string.rep("=", 82) .. "#",
    plate("CRIMSON ARCADE                             1UP       HIGH"),
    "#" .. string.rep("=", 82) .. "#",
  },
  bottom = {
    "#" .. string.rep("=", 82) .. "#",
    plate("(C) PZA SOFTWORKS     PLAYER 1     CREDIT 00      > COIN"),
    "#" .. string.rep("=", 82) .. "#",
  },
  colors = {
    frame  = { 196, 58,  64 },
    accent = { 255, 205, 90 },
    ui_fg  = { 255, 236, 232 },
    ui_bg  = { 28,  8,   12 },
    ui_dim = { 150, 60,  70 },
    panel  = { 42,  12,  17 },  -- 侧栏：比机身略亮
  },
  lamps = {
    { x = 0,  y = 4, color = { 255, 60,  60 }, period = 0.9 },
    { x = 83, y = 4, color = { 255, 205, 90 }, period = 0.9 },
  },
}

-- RUST CABINET：废弃游戏厅的机台（锈蚀斑驳 + 服务铭牌）
-- 上下用斑驳的 ":..:" 锈迹；底部留一块"维修/退币"铭牌与一段剥落的花纹
local W = 84
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

return {
  screen = { x = 2, y = 3 },
  palette = "amber",
  left  = ":|",
  right = "|:",
  top = {
    "##" .. string.rep(":..:", 20) .. "##",
    plate("R U S T   C A B I N E T               SERIAL 1987-04     [X]"),
    "##" .. string.rep(":..:", 20) .. "##",
  },
  bottom = {
    "##" .. string.rep(":..:", 20) .. "##",
    plate("COIN RETURN [ ]      FAULT [!]      SERVICE  ------"),
    plate("      . : .   ## .. ##   : . :        ( peeled )     "),   -- 剥落的花纹
  },
  colors = {
    frame  = { 120, 95, 70 },
    accent = { 255, 170, 60 },
    ui_fg  = { 235, 215, 190 },
    ui_bg  = { 8,  6,  4 },
    ui_dim = { 120, 100, 80 },
    panel  = { 18,  14,  10 },
  },
  lamps = {
    { x = 0,  y = 4,  color = { 255, 170, 60 }, period = 1.2 },
    { x = 83, y = 4,  color = { 255, 170, 60 }, period = 1.35 },
    { x = 0,  y = 42, color = { 255, 60,  60  }, period = 5.0 },
  },
}

-- PHOSPHOR P-1：出厂机身（极简工业风）
local W = 84

-- 左右各留 2 列作侧壁，中间 80 列用于铭牌排版
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

return {
  screen = { x = 2, y = 3, w = 80, h = 45 },
  left  = "||",
  right = "||",
  top = {
    string.rep("=", W),
    plate("PHOSPHOR P-1                        CRT DISPLAY UNIT"),
    string.rep("=", W),
  },
  bottom = {
    string.rep("=", W),
    plate("MODEL P-1           NO USER SERVICEABLE PARTS INSIDE"),
    string.rep("=", W),
  },
  colors = {
    frame  = { 70,  95,  70 },
    accent = { 110, 255, 150 },
    ui_fg  = { 225, 255, 225 },
    ui_bg  = { 0,   0,   0 },
    ui_dim = { 95,  120, 95 },
  },
  lamps = {
    { x = 0,  y = 6,  color = { 80,  255, 120 }, period = 2.4 },
    { x = 83, y = 6,  color = { 255, 90,  90  }, period = 9.0 },
  },
}

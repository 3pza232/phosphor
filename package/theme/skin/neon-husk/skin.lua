-- NEON HUSK：霓虹残壳
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

return {
  screen = { x = 2, y = 3 },
  palette = "ice-blue",
  left  = "+-",
  right = "-+",
  top = {
    "+" .. string.rep("-=", 41) .. "+",
    plate("  NEON HUSK                TERMINAL 7 / NIGHT SHIFT          "),
    "+" .. string.rep("-=", 41) .. "+",
  },
  bottom = {
    "+" .. string.rep("-=", 41) .. "+",
    plate("  TOKEN 1  .  NO REFUNDS  .  CLOSING 04:00  .  STAFF ->      "),
    "+" .. string.rep("-=", 41) .. "+",
  },
  colors = {
    frame  = { 90, 60, 170 },
    accent = { 120, 220, 255 },
    ui_fg  = { 230, 235, 255 },
    ui_bg  = { 4, 2, 12 },
    ui_dim = { 120, 110, 180 },
    panel  = { 14, 8, 26 },  -- 侧栏：比机身略亮的紫黑
  },
  lamps = {
    { x = 0,  y = 8,  color = { 255, 60,  180 }, period = 0.9 },
    { x = 83, y = 8,  color = { 60,  200, 255 }, period = 1.1 },
    { x = 0,  y = 36, color = { 60,  200, 255 }, period = 1.4 },
    { x = 83, y = 36, color = { 255, 60,  180 }, period = 1.7 },
  },
}

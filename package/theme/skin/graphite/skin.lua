-- GRAPHITE：石墨灰工程终端（细线、冷灰，像一台仪器面板）
-- 铭牌只用 ASCII（内容包沙箱里没有语言 API）
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

return {
  screen = { x = 2, y = 3 },
  palette = "slate",
  left  = "|.",
  right = ".|",
  top = {
    "+" .. string.rep(".", 82) .. "+",
    plate("GRAPHITE  TERMINAL                    REVISION 2.1      +"),
    "+" .. string.rep(".", 82) .. "+",
  },
  bottom = {
    "+" .. string.rep(".", 82) .. "+",
    plate("- - -  diagnostic bus  - - -          unit 0x2A"),
    "+" .. string.rep(".", 82) .. "+",
  },
  colors = {
    frame  = { 120, 126, 132 },
    accent = { 170, 200, 220 },
    ui_fg  = { 214, 220, 226 },
    ui_bg  = { 16,  18,  20 },
    ui_dim = { 95,  100, 108 },
    panel  = { 26,  29,  32 },  -- 侧栏：比机身略亮
  },
  lamps = {
    { x = 0,  y = 6, color = { 170, 200, 220 }, period = 3.0 },
    { x = 83, y = 6, color = { 150, 155, 160 }, period = 4.2 },
  },
}

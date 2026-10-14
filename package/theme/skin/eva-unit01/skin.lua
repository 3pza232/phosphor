-- EVANGELION UNIT-01：初号机配色（紫机身 / 荧光绿高亮 / 橙色警戒）
-- 铭牌只用 ASCII（内容包沙箱里没有语言 API）
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

return {
  screen = { x = 2, y = 3 },
  palette = "eva",
  left  = "||",
  right = "||",
  top = {
    "|" .. string.rep("=", 82) .. "|",
    plate("EVANGELION UNIT-01              SYNC RATIO 400%   ARMED"),
    "|" .. string.rep("=", 82) .. "|",
  },
  bottom = {
    "|" .. string.rep("=", 82) .. "|",
    plate("NERV  TOKYO-3        A.T. FIELD: ACTIVE       > LAUNCH"),
    "|" .. string.rep("=", 82) .. "|",
  },
  colors = {
    frame  = { 108, 74, 168 },   -- 初号机紫
    accent = { 150, 216, 70 },   -- 荧光绿高亮
    ui_fg  = { 232, 228, 244 },
    ui_bg  = { 14,  9,   22 },
    ui_dim = { 120, 90,  160 },
    panel  = { 26,  18,  38 },   -- 侧栏：比机身略亮
  },
  lamps = {
    { x = 0,  y = 4, color = { 150, 216, 70 }, period = 1.1 },   -- 绿
    { x = 83, y = 4, color = { 255, 165, 58 }, period = 1.1 },   -- 橙
  },
}

-- GRAPHITE TERMINAL：工程仪器（细刻线 + 刻度尺边 + 侧壁点线）
-- 顶/底用**带刻度的标尺**（每 4 格一个 +），侧壁点线轮换——不再是"一条实线"
local W = 84
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end
-- 刻度尺：+ 与 - 交替，4 格一档
local function ruler()
  local s = "+"
  for _ = 1, 20 do s = s .. "----+" end
  s = s .. "----"
  return s:sub(1, W)
end

return {
  screen = { x = 2, y = 3 },
  palette = "slate",
  left  = "|.",
  right = ".|",
  top = {
    ruler(),
    plate("GRAPHITE  TERMINAL          REVISION 2.1        PN 0x2A"),
    ruler(),
  },
  bottom = {
    ruler(),
    plate("diagnostic bus  - - -        unit 0x2A        no signal loss"),
    ruler(),
  },
  colors = {
    frame  = { 120, 126, 132 },
    accent = { 170, 200, 220 },
    ui_fg  = { 214, 220, 226 },
    ui_bg  = { 16,  18,  20 },
    ui_dim = { 95,  100, 108 },
    panel  = { 26,  29,  32 },
  },
  lamps = {
    { x = 0,  y = 6, color = { 170, 200, 220 }, period = 3.0 },
    { x = 83, y = 6, color = { 150, 155, 160 }, period = 4.2 },
  },
}

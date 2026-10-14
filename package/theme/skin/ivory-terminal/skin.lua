-- IVORY TERMINAL：象牙白实验仪器（暖白机身 + 琥珀高亮）
-- 顶上一条刻度标尺，底下一排状态指示灯 [PWR][SIG][REC] 与序列号——实验台的语汇
local W = 84
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end
local function scale()                        -- |....|....| 的仪表刻度
  local s = "|"
  for _ = 1, 16 do s = s .. "....|" end
  s = s .. "...."
  return s:sub(1, W)
end

return {
  screen = { x = 2, y = 3 },
  palette = "paper",
  left  = "|:",
  right = ":|",
  top = {
    scale(),
    plate("IVORY TERMINAL                        MODEL IV-2         [///]"),
    scale(),
  },
  bottom = {
    scale(),
    plate("PWR [o]     SIG [o]     REC [ ]     LAMP [o]      SER. 0007"),
    scale(),
  },
  colors = {
    frame  = { 150, 140, 118 },
    accent = { 176, 104, 26 },
    ui_fg  = { 40,  36,  30 },
    ui_bg  = { 238, 234, 222 },
    ui_dim = { 116, 108, 92 },
    panel  = { 224, 219, 204 },
  },
  lamps = {
    { x = 0,  y = 5, color = { 205, 150, 70 }, period = 2.2 },
    { x = 83, y = 5, color = { 100, 170, 110 }, period = 3.6 },
  },
}

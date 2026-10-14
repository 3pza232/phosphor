-- EVANGELION UNIT-01：初号机配色（紫机身 + 荧光绿高亮 + 橙色警戒）
-- 上下是斜纹警戒条，底部一条栅格排气；NERV 铭牌
local W = 84
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end
local function stripe()                        -- /\ 斜纹警戒条
  local s = "|"
  for _ = 1, 41 do s = s .. "/\\" end
  return s:sub(1, W)
end

return {
  screen = { x = 2, y = 3 },
  palette = "eva",
  left  = "|^",
  right = "^|",
  top = {
    stripe(),
    plate("EVANGELION UNIT-01               SYNC RATIO 400%   ARMED"),
    stripe(),
  },
  bottom = {
    stripe(),
    plate("NERV  TOKYO-3          A.T. FIELD: ACTIVE        > LAUNCH"),
    plate("|||  |||  |||  |||  |||  |||  |||  |||  |||  |||  |||"),
  },
  colors = {
    frame  = { 108, 74, 168 },
    accent = { 150, 216, 70 },
    ui_fg  = { 232, 228, 244 },
    ui_bg  = { 14,  9,   22 },
    ui_dim = { 120, 90,  160 },
    panel  = { 26,  18,  38 },
  },
  lamps = {
    { x = 0,  y = 4, color = { 150, 216, 70 }, period = 1.1 },
    { x = 83, y = 4, color = { 255, 165, 58 }, period = 1.1 },
  },
}

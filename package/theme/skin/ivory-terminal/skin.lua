-- IVORY TERMINAL：象牙白实验仪器（暖白机身 + 琥珀高亮）
-- 铭牌只用 ASCII：皮肤脚本跑在内容包沙箱里（只有 phos.text.width/truncate），
-- 拿不到界面语言，所以正文一律不写中文
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

return {
  screen = { x = 2, y = 3 },
  palette = "paper",
  left  = "|:",
  right = ":|",
  top = {
    "+" .. string.rep("-", 82) .. "+",
    plate("IVORY TERMINAL                       MODEL IV-2        [///]"),
    "+" .. string.rep("-", 82) .. "+",
  },
  bottom = {
    "+" .. string.rep("-", 82) .. "+",
    plate("PWR [o]     SIG [o]     REC [ ]                SER. 0007"),
    "+" .. string.rep("-", 82) .. "+",
  },
  colors = {
    frame  = { 150, 140, 118 },
    accent = { 176, 104, 26 },
    ui_fg  = { 40,  36,  30 },
    ui_bg  = { 238, 234, 222 },
    ui_dim = { 116, 108, 92 },
    panel  = { 224, 219, 204 },  -- 侧栏：比机身略深（本主题配浅色色板 paper，字是深墨）
  },
  lamps = {
    { x = 0,  y = 5, color = { 205, 150, 70 }, period = 2.2 },
    { x = 83, y = 5, color = { 100, 170, 110 }, period = 3.6 },
  },
}

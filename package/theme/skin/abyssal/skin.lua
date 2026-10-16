-- ABYSSAL DIVER：深潜器耐压舱
-- 深蓝青耐压舱：上下舱缝 + 铆钉排，顶缝中央开一扇舷窗；侧壁是舱内管路；
-- 铭牌左右留白、黄铜/系统读数分行；两对青绿、一对琥珀呼吸灯对称嵌在舱壁上。
-- 六色分工：frame 舱体 / accent 荧光高光 / ui_fg 冷白字 / ui_bg 深舱底 /
-- ui_dim 暗青次字 / panel 更深的凹槽；卡带配色取自 palette "abyss"。
local W = 84
local function spread(left, right, margin)      -- 一行左右两段，居中留出均匀边距
  margin = margin or 2
  if phos.text.width(left) > W then left = phos.text.truncate(left, W) end
  local lw, rw = phos.text.width(left), phos.text.width(right)
  local gap = W - 2 * margin - lw - rw
  if gap < 1 then gap = 1 end
  return string.rep(" ", margin) .. left .. string.rep(" ", gap) .. right ..
         string.rep(" ", margin)
end
local function seam(window)                     -- 舱缝：两端铆钉 + 等号 + 中央舷窗
  local wl = phos.text.width(window)
  local body = W - 4 - wl                       -- 两端各 "##"
  local l = math.floor(body / 2)
  return "##" .. string.rep("=", l) .. window .. string.rep("=", body - l) .. "##"
end
local function rivets() return string.rep("=o", W // 2) end   -- 铆钉排
local function pipes()  return string.rep("|-", W // 2) end   -- 管路排

return {
  screen = { x = 2, y = 3 },                    -- 内容区 80x45，四周留出机身边框
  palette = "abyss",
  left  = "|:|=",
  right = string.reverse("|:|="),               -- 左右侧壁镜像对称
  top = {
    seam("( o )"),                              -- 顶：耐压舱缝，中央一扇舷窗
    spread("ABYSSAL DIVER  DSV-7", "HULL 01 | BRASS PLATE | 6000 m", 2),
    rivets(),
  },
  bottom = {
    rivets(),
    spread("O2 78%  ARGON 21%  TRIM +0.0", "BALLAST FLOOD | SONAR ARRAY ONLINE", 2),
    pipes(),
  },
  colors = {
    frame  = { 58,  112, 130 },
    accent = { 64,  232, 210 },
    ui_fg  = { 214, 240, 242 },
    ui_bg  = { 4,   10,  16  },
    ui_dim = { 84,  132, 144 },
    panel  = { 12,  30,  38  },
  },
  lamps = {
    { x = 1,  y = 5,  color = { 64,  232, 210 }, period = 2.6 },
    { x = 82, y = 5,  color = { 64,  232, 210 }, period = 2.6 },
    { x = 1,  y = 23, color = { 60,  150, 168 }, period = 4.8 },
    { x = 82, y = 23, color = { 60,  150, 168 }, period = 4.8 },
    { x = 1,  y = 41, color = { 255, 178, 72  }, period = 3.6 },
    { x = 82, y = 41, color = { 255, 178, 72  }, period = 3.6 },
  },
}

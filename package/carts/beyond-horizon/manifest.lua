-- manifest.lua —— 《视界线外》卡带身份证。字段规范见 docs/cart-format.md
--
-- 第一阶段不声明 sidebar：舞台示意图 + 底部文本框都要 80x45 的完整宽度。
-- 若 GDD 决定把资源读数放进侧栏，加 sidebar = { w = 18 } 并相应收窄 ui.lua 的布局常量。
return {
  id      = "beyond-horizon",
  name    = { zh = "视界线外", en = "BEYOND THE HORIZON" },
  entry   = "main.lua",

  author  = "PHOSPHOR",
  version = "1.0.0",
  desc = {
    zh = "深空观测员在黑洞边缘的废弃站醒来：修好它、读懂视界内的信号，然后决定留下什么。",
    en = "A deep-space observer wakes on a derelict station at the edge of a black hole: rebuild it, read the signal from inside the horizon, and decide what to leave behind.",
  },

  save = true,

  -- 卡带架图标：黑洞 + 吸积环
  icon = {
    "   ####   ",
    " ##....## ",
    " #..~~..# ",
    "#..~##~..#",
    "#..~##~..#",
    " #..~~..# ",
    " ##....## ",
    "   ####   ",
  },
  icon_colors = {
    ["#"] = { 120, 110, 200 },
    ["~"] = { 255, 200, 120 },
  },

  phos_api = 7,
}

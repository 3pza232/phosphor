-- manifest.lua —— 打砖块
return {
  id = "bricks",
  name = "BRICKS",
  version = "1.0.0",
  author = "PZA",
  desc = {
    zh = "打砖块：移动挡板反弹小球，清空砖墙，别让球掉下去。",
    en = "Breakout: move the paddle to bounce the ball and clear the wall without dropping it.",
  },
  entry = "main.lua",
  sidebar = { w = 18 },
  save = true,   -- 最高分存档
  phos_api = 1,
  icon = {
    "  #############   ",
    "  #############   ",
    "                  ",
    "        #         ",
    "      #####       ",
  },
  icon_colors = {
    ["#"] = { 255, 210, 90 },
  },
}

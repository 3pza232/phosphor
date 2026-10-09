-- BRICKS —— 打砖块
return {
  id = "bricks",
  name = "BRICKS",
  version = "1.0.0",
  author = "phosphor",
  desc = {
    zh = "打砖块 —— 清空砖墙，别让球落下。",
    en = "Breakout: clear the wall, keep the ball up.",
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

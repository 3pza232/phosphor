-- manifest.lua —— CHOMP 卡带标签
return {
  id      = "chomp",
  name    = { zh = "吃豆人", en = "CHOMP" },
  author  = "PZA",
  version = "1.0.0",
  -- 简介双语：卡带架按机器的界面语言取（只写字符串则中英同文）
  desc = {
    zh = "吃豆人：吃掉迷宫里的豆子，躲开幽灵；吃下能量豆就能反过来吃幽灵。",
    en = "Pac-Man: eat the dots, dodge the ghosts, and turn the tables with a power pellet.",
  },
  entry   = "main.lua",
  sidebar = { w = 18 },   -- 右侧栏：分数 / 生命 / 幽灵图例
  save    = true,         -- 需要存档空间（最高分）
  phos_api = 1,

  -- 卡带架展示用的像素图标（'.' 与空格透明）
  icon = {
    "                  ",
    "    ########      ",
    "   ##########  o  ",
    "   #####   ##     ",
    "   #####   ##     ",
    "   ##########     ",
    "    ########      ",
    "     ##  ##       ",
  },
  icon_colors = {
    ["#"] = { 255, 236, 120 },   -- 发光的自己
    ["o"] = { 120, 220, 255 },   -- 一颗豆子
  },
}

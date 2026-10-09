-- SNAKE.EXE 卡带标签
return {
  id      = "snake",
  name    = "SNAKE",
  author  = "phosphor",
  version = "1.1.0",
  -- 简介双语：卡带架按机器的界面语言取（只写字符串则中英同文）
  desc = {
    zh = "在终端里猎食的蛇：方向键移动，回车重开，最高分自动存档。",
    en = "A snake hunting in the terminal: arrows to move, Enter to restart, best score saved.",
  },
  entry   = "main.lua",
  sidebar = { w = 18 },   -- 右侧栏：历史分数记录
  save    = true,         -- 需要存档空间（最高分记录）
  phos_api = 1,           -- 目标 API 世代（高于主机支持的会被拒绝加载）

  -- 卡带架展示用的像素图标（'.' 与空格透明）
  icon = {
    "                  ",
    "     ####         ",
    "    ######    o   ",
    "   ########       ",
    "    ##  ##        ",
    "     ##           ",
  },
  icon_colors = {
    ["#"] = { 80, 255, 120 },
    ["o"] = { 255, 80, 80 },
  },
}

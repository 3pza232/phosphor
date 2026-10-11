-- manifest.lua —— RUNNER 卡带标签
return {
  id      = "runner",
  name    = "RUNNER",
  author  = "phosphor",
  version = "1.0.0",
  -- 简介双语：卡带架按机器的界面语言取（只写字符串则中英同文）
  desc = {
    zh = "沙漠里一直跑：跳过仙人掌、低头躲翼龙，白天跑进黑夜，越跑越快。",
    en = "Keep running through the desert: jump the cacti, duck the pterodactyls, and run from day into night.",
  },
  entry   = "main.lua",
  sidebar = { w = 18 },   -- 右侧栏：分数 / 速度 / 里程碑
  save    = true,         -- 需要存档空间（最高分）
  phos_api = 1,

  -- 卡带架展示用的像素图标（'.' 与空格透明）
  icon = {
    "                  ",
    "        ###       ",
    "       #####   ###",
    "      #######  ###",
    "       ##  #      ",
    "       #   #      ",
    "                  ",
  },
  icon_colors = {
    ["#"] = { 255, 214, 140 },   -- 沙色的小恐龙
  },
}

return {
  id = "ballbattle",
  name = { zh = "球球大作战", en = "BLOB BATTLE" },
  author = "PZA",
  version = "1.0.0",
  desc = {
    zh = "球球大作战：吃掉食物与小球长大，别被更大的球吞掉；活到最后就是最强。",
    en = "Blob Battle: eat pellets and smaller blobs to grow. Don't get swallowed. Last one standing wins.",
  },
  entry = "main.lua",
  sidebar = { w = 20 },   -- 右栏：排行榜与存活时间
  save = true,            -- 最高体格记录
  phos_api = 1,

  icon = {
    "          ",
    "    ##    ",
    "   ####   ",
    "  ######  ",
    "   ####   ",
    "    ##    ",
  },
  icon_colors = { ["#"] = { 120, 220, 255 } },
}

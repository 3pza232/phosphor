return {
  id = "xiangqi",
  name = { zh = "中国象棋", en = "CHINESE CHESS" },
  author = "PZA",
  version = "1.0.0",
  desc = {
    zh = "中国象棋：人机对弈，完整走法与将军判定；吃光对方或将死即胜。",
    en = "Chinese Chess (Xiangqi): full rules and check detection, play against the machine.",
  },
  entry = "main.lua",
  sidebar = { w = 26 },   -- 右栏：棋谱、吃子与键位提示
  save = false,           -- 无存档（不声明 save 就不用它）
  phos_api = 3,           -- 用到 phos.screen.back（独立底色，世代 3）

  icon = {
    "          ",
    "  ##  ##  ",
    " ######## ",
    "  ##  ##  ",
    " ######## ",
    "  ##  ##  ",
  },
  icon_colors = { ["#"] = { 240, 200, 120 } },
}

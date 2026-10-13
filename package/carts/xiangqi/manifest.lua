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
  sidebar = { w = 22 },   -- 右栏：棋谱与吃子
  save = true,            -- 战绩
  phos_api = 1,

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

-- manifest.lua —— 俄罗斯方块
return {
  id = "tetris",
  name = { zh = "俄罗斯方块", en = "TETRIS" },
  version = "1.0.0",
  author = "PZA",
  desc = {
    zh = "俄罗斯方块：方块落进井里，消满一行得分，堆得越高速度越快。",
    en = "Tetris: drop the shapes and clear full lines to score; it speeds up as the stack grows.",
  },
  entry = "main.lua",
  sidebar = { w = 18 },
  save = true,   -- 最高分存档

  -- 本卡带用了 phos.layer（第二代接口）：声明 2，旧主机在卡带架上就明确拒绝，
  -- 而不是运行到建层那一行才出错
  phos_api = 2,

  icon = {
    "   #              ",
    "   #   ##   ###   ",
    "   #   ##   ###   ",
    "                  ",
    "  #############   ",
    "  #############   ",
  },
  icon_colors = {
    ["#"] = { 120, 230, 255 },
  },
}

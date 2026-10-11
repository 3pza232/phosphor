-- manifest.lua —— 俄罗斯方块
return {
  id = "tetris",
  name = "TETRIS",
  version = "1.0.0",
  author = "phosphor",
  desc = {
    zh = "俄罗斯方块 —— 七种方块落进井里，消满一行得分；用图层把井、方块、特效分开画。",
    en = "Tetris: seven shapes fall into the well. Layers keep the well, the falling piece and the effects apart.",
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

-- manifest.lua —— 康威生命游戏
-- name 是卡带架与侧栏显示的标题；id 建议与目录同名
return {
  id = "life",
  name = "LIFE",
  version = "1.0.0",
  author = "phosphor",
  desc = {
    zh = "康威生命游戏 —— 细胞自动机沙盒：画细胞、盖图案、看演化。",
    en = "Conway's Game of Life: draw cells, stamp patterns, watch it evolve.",
  },
  entry = "main.lua",
  sidebar = { w = 18 },
  phos_api = 1,
  icon = {
    "   #  #         ",
    "  # ## #   #    ",
    "  #    # # ##   ",
    "   #  #  # #    ",
    "        ## #    ",
  },
  icon_colors = { ["#"] = { 120, 255, 140 } },
}

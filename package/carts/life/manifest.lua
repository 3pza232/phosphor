-- manifest.lua —— 康威生命游戏
-- name 是卡带架与侧栏显示的标题；id 建议与目录同名
return {
  id = "life",
  name = "LIFE",
  version = "1.0.0",
  author = "PZA",
  desc = {
    zh = "生命游戏：细胞自动机沙盒，画出图案看它自行演化。",
    en = "Game of Life: a cellular-automaton sandbox - draw a pattern and watch it evolve.",
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

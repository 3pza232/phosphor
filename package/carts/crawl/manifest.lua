-- manifest.lua —— 卡带身份证。字段规范见 docs/cart-format.md
--
-- GLOW CRAWL：回合制 Roguelike 地下城探索。你提着一盏会熄灭的磷灯往地牢深处爬，
-- 灯亮看得远、怪物也看得见你；灯弱藏得住、却寸步难行——在光与黑暗之间做取舍。
-- 玩法数值与系统规格见随包的 DESIGN.md。

return {
  -- ─── 必填 ───────────────────────────────────────────────
  id      = "crawl",                       -- 小写字母/数字/连字符；也是存档名 saves/crawl.sav
  name    = { zh = "荧光地牢", en = "GLOW CRAWL" },
  entry   = "main.lua",

  -- ─── 建议填写 ───────────────────────────────────────────
  author  = "PZA",
  version = "0.1.0",                       -- 作者自己的版本号（与主机版本无关）
  desc = {
    zh = "回合制 Roguelike：提一盏会熄灭的磷灯，下潜十层地牢，避怪夺宝，取回磷之心。",
    en = "Turn-based roguelike: carry a dying lantern down ten floors, dodge monsters, grab loot, claim the Phosphor Heart.",
  },

  -- ─── 按需打开 ───────────────────────────────────────────
  -- 右侧栏：状态条 / 灯油 / 装备 / 背包 / 键位提示（右栏宽 20）
  sidebar = { w = 20 },

  -- 存档：最高分 / 最深深度 / 游玩次数 / 上次种子
  save = true,

  -- 卡带架像素图标：一盏发光的磷灯（'.' 与空格透明；图标色与主题无关，固定色）
  icon = {
    "  ######  ",
    " ##    ## ",
    " #  **  # ",
    " # **** # ",
    " # **** # ",
    " #  **  # ",
    " ##    ## ",
    "  ######  ",
  },
  icon_colors = { ["#"] = { 110, 125, 155 }, ["*"] = { 255, 195, 90 } },

  -- 用了主题携带色板（phos.color.*，第 5 代）与同屏多字号（put/print 的 scale，第 6 代）：
  -- 声明 6，旧主机在卡带架上明确拒绝，而不是运行到那一行才失败（见 cart-format.md「版本兼容」）
  phos_api = 6,
}

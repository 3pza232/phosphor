-- manifest.lua —— 卡带身份证（CORE LINE / 磁芯防线）。字段规范见 docs/cart-format.md
-- 设计规格见同目录 DESIGN.md（数值的唯一来源）。

return {
  -- ─── 必填 ───────────────────────────────────────────────
  id = "towerdef",                    -- 唯一标识：同时是目录名、<id>.phos 与存档名
  name = { zh = "磁芯防线", en = "CORE LINE" },
  entry = "main.lua",

  -- ─── 建议填写 ───────────────────────────────────────────
  author = "PZA",
  version = "0.1.0",
  desc = {
    zh = "在网格上砌塔成迷宫、拉电供能，挡住 20 波扑向磁芯的敌人；塔会挡路，电力超载全场降速。",
    en = "Build towers into a maze and power them to hold off 20 waves from the core. Towers block paths; overload cuts your fire rate.",
  },

  -- ─── 按需打开 ───────────────────────────────────────────
  sidebar = { w = 22 },               -- 右栏：波次/资源/塔型面板/选中塔详情/键位
  save = true,                        -- 最高波次、通关次数、最高分、偏好速度与难度

  -- 卡带架里的像素图标（'.' 与空格为透明）：一座炮塔
  icon = {
    "    ##    ",
    "    ##    ",
    "  #    #  ",
    "  ######  ",
    "   ####   ",
    "   ####   ",
    "  ##  ##  ",
    " ##    ## ",
  },
  icon_colors = { ["#"] = { 120, 255, 160 } },

  -- 第三代墨迹 / 半格 / 独立底色、第二代图层（fx/hud 叠层）与第六代同屏多字号
  -- （顶部波次横幅用 scale=2）：声明 6，旧主机在卡带架上就明确拒绝，而不是运行到那一行才失败。
  phos_api = 6,
}

-- manifest.lua —— 叠加与半格示例卡带（见 design/draw-api.md）。放在 devkit 里而不是出厂列表：
-- 它是"同一格要放两样东西时怎么用"的样板，也是 tools/draw_smoke.py 的被测对象
return {
  id = "inks-demo",
  name = "INKS DEMO",
  version = "1.0.0",
  author = "phosphor",
  desc = {
    zh = "叠加与半格示例：同格两笔、底色独立、子位落笔、叠画上限。开机即画完，无需操作。",
    en = "Inks demo: two pens in one cell, background-only writes, sub-cell plot, ink cap.",
  },
  entry = "main.lua",

  -- 画面用的是第三代接口（墨迹叠加 / 半格绘制 / 独立底色）：声明 3，旧主机在卡带架上
  -- 就明确拒绝，而不是运行到 blend / plot 那一行才撞上缺失接口（见 cart-format.md）
  phos_api = 3,
}

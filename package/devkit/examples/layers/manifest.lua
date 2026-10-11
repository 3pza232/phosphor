-- 图层示例卡带（见 design/layers-and-api.md）。放在 devkit 里而不是出厂列表：
-- 它是"新卡带想用分层时怎么用"的样板，出厂卡带一律不改成这种写法
return {
  id = "layers-demo",
  name = "LAYERS DEMO",
  version = "1.0.0",
  author = "phosphor",
  desc = {
    zh = "图层示例：世界、HUD、浮窗各一层。A 开关浮窗，B 显隐 HUD，方向键移动光标。",
    en = "Layer demo: world / HUD / overlay as separate layers. A toggles the window, B the HUD.",
  },
  entry = "main.lua",

  -- 图层是第二代接口：声明 2，主机低于 2 会拒绝加载，而不是运行到一半才撞上缺失接口
  phos_api = 2,
}

-- Mod 清单（必需）：显示名/说明 + 覆盖注册。
-- MODS 管理器里显示的是 name（缺省显示名 = 文件夹名 "font-resize"）。
-- overrides 把这个 mod 独有的内容登记到目标文件上：
--   ["default/font.lua"] = "font.lua"  —— 键是 <目标id>/<包内路径>，值是本 mod 目录内的文件
return {
  name = { zh = "字体放大", en = "Font Resize" },
  desc = { zh = "字号上限 24 → 28", en = "font-size cap 24 → 28" },
  overrides = {
    ["default/font.lua"] = "font.lua",
  },
}

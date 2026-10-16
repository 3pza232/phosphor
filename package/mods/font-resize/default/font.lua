-- 覆盖层 Mod「字体放大」：把字号可调上限从 24 抬到 28。
--
-- 新布局：每个 mod 是一个有名字的文件夹（文件夹名 = mod id），覆盖内容镜像目标结构放在
-- 它之下——`mods/<mod-id>/<目标id>/<目标内路径>`。覆盖键取 mod-id **之后**的相对路径，
-- 于是这里覆盖的是字体方案 "default" 的 font.lua（见 package/theme/font/default/font.lua）：
-- 引擎把方案声明的 max 当作"字号"行的可调上限，于是用户能把字号调到 28。
-- 同一个文件夹里的 mod.lua 是清单（显示名/说明），不参与覆盖路径。
return {
  size = 16,                    -- 默认字号不变
  min = 12,
  max = 28,                     -- ← 抬高上限（出厂 24；硬上限 32）
  order = { "font", "font-cn" },
}

-- 覆盖层 Mod「字体放大」的覆盖内容：把字号可调上限从 24 抬到 28。
--
-- 它被本 mod 的 mod.lua 通过 overrides 登记到键 "default/font.lua"，于是替换字体方案
-- "default" 的 font.lua（见 package/theme/font/default/font.lua）：引擎把方案声明的 max
-- 当作"字号"行的可调上限，用户就能把字号调到 28。内容扁平放，文件名可自由取。
return {
  size = 16,                    -- 默认字号不变
  min = 12,
  max = 28,                     -- ← 抬高上限（出厂 24；硬上限 32）
  order = { "font", "font-cn" },
}

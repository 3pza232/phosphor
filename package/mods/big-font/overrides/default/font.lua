-- 覆盖层 Mod「大字号」：把字号可调上限从 24 抬到 28。
--
-- Mod 就是 mods/<任意名>/ 这一个文件夹，**放进 mods/ 即自动生效**（无需开关）。
-- 一个 mod 可以覆盖多个目标，覆盖项放在 overrides/<目标id>/<目标内路径> 下——
-- 这里覆盖的是字体方案 "default" 的 font.lua（见 package/theme/font/default/font.lua）。
-- 引擎把方案声明的 max 当作"字号"行的可调上限，于是用户能把字号调到 28。
return {
  size = 16,                    -- 默认字号不变
  min = 12,
  max = 28,                     -- ← 抬高上限（出厂 24；硬上限 32）
  order = { "font", "font-cn" },
}

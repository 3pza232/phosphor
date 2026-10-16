-- ABYSS：深海声呐色板（海底深蓝青 + 生物荧光青绿 + 琥珀/橙警示）
-- 配 abyssal 主题：black 深如海沟、white 冷白微青，两者对比足；
-- 12 槽刻意拉开——green(纯荧光绿) 与 cyan(青) 靠蓝分量区分，
-- blue / purple / magenta 靠红分量区分，yellow(暖黄) 与 white(冷白) 靠蓝分量区分；
-- orange/red 是唯一的暖色，作警示。scan/tint 取"深海但不糊"的保守值：
-- 有色偏（tint 冷青）但不过度压暗文字，信息密集的卡带也能看清。
return {
  scan = 0.07,
  tint = { 216, 240, 248 },
  colors = {
    black     = { 0,   5,   10  },
    white     = { 226, 248, 246 },
    gray      = { 118, 156, 168 },
    dark_gray = { 44,  76,  92  },
    red       = { 255, 96,  96  },
    green     = { 104, 255, 150 },
    blue      = { 90,  150, 255 },
    yellow    = { 240, 238, 150 },
    cyan      = { 96,  244, 236 },
    magenta   = { 228, 96,  200 },
    orange    = { 255, 166, 56  },
    purple    = { 150, 120, 235 },
  },
}

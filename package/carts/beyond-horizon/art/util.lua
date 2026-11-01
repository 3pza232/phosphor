-- art/util.lua —— 美术资源的公共工具：行列解析、语义色键、锚点、绘制。
--
-- 三条纪律（与 BRIEF 的"只写 art"一致）：
--   * 图样行只用 ASCII：任何字体方案下都不缺字（中文只放在 title 的文本字段里，
--     由程序用 phos.screen.print 画，默认字体方案带中文回退）；
--   * 颜色只写**语义键**（见 U.palette），每次绘制时才从 phos.color 取值——
--     主题热切换后颜色立刻跟上，不会拿着旧色板的老颜色；
--   * 不读输入、不改状态、不发声音：这里只有"把一块字符画贴到网格上"。

local U = {}

-- 语义色键 → 激活色板名（phos.color.*）。图样只认左边这列；换主题 = 整套换色。
-- 冷色 CRT 的默认落点：深空黑 / 蓝 / 灰 / 白 + 青色仪器光 + 绿信号 + 红告警 + 紫"里面"。
U.palette = {
  void = "black",       -- 纯黑空腔（事件视界内部、遮光处）
  deep = "blue",        -- 深空/低亮结构
  panel = "dark_gray",  -- 面板灰、次级结构
  line = "gray",        -- 仪器刻线、边框
  body = "white",       -- 正文亮部、星点
  ice = "cyan",         -- 冷光、仪表读数、光晕
  signal = "green",     -- 信号、正常状态、波形
  alert = "red",        -- 告警、失压、危险
  warn = "yellow",      -- 注意、临界值
  ghost = "purple",     -- 视界内侧、不可解释的东西
  glitch = "magenta",   -- 故障噪点、干扰
  warm = "orange",      -- 唯一的暖色：人体/旧灯光/吸积盘内缘（克制使用）
}

-- 行表：去掉首尾空行；行内空格与相对缩进**原样保留**（锚点与构图靠它）
function U.rows(text)
  local out = {}
  if text:sub(1, 1) == "\n" then text = text:sub(2) end
  for line in (text .. "\n"):gmatch("(.-)\n") do out[#out + 1] = line end
  while #out > 0 and out[#out] == "" do out[#out] = nil end
  local first = 1
  while first <= #out and out[first] == "" do first = first + 1 end
  if first > 1 then
    local trimmed = {}
    for i = first, #out do trimmed[#trimmed + 1] = out[i] end
    out = trimmed
  end
  return out
end

-- 造一块资源：{ id, rows, colors, w, h, anchor, note }
-- art 是以列 0 起写的多行字符画（[==[ ... ]==]）；colors 是 字符 → 语义键。
function U.block(def)
  local rows = def.rows or U.rows(def.art or "")
  local w = 0
  for i = 1, #rows do
    if #rows[i] > w then w = #rows[i] end
  end
  return {
    id = def.id,
    rows = rows,
    colors = def.colors or {},
    w = def.w or w,
    h = def.h or #rows,
    anchor = def.anchor or "top-center",
    note = def.note,
  }
end

-- 字符 → 颜色表（每次调用现取 phos.color）。overrides 按**语义键**覆盖，例如
-- { signal = "alert" }（换成色板红）或 { signal = phos.color.rgb(255, 40, 40) }。
function U.colors(block, overrides)
  local out = {}
  local C = phos.color
  for ch, key in pairs(block.colors or {}) do
    local value = overrides and overrides[key]
    if value == nil then value = U.palette[key] end
    if type(value) == "string" then value = C[value] end
    if value ~= nil then out[ch] = value end
  end
  return out
end

function U.size(block) return block.w, block.h end

-- 锚点换算：把整块图样摆进 rect（缺省 = 整个内容区 80x45）。
-- where = "top-left" / "top-center" / "top-right" / "center-left" / "center" /
--         "center-right" / "bottom-left" / "bottom-center" / "bottom-right"
function U.anchor_xy(block, where, rect)
  rect = rect or { x = 0, y = 0, w = 80, h = 45 }
  where = where or block.anchor or "top-center"
  local v, h = where:match("^(%a+)%-(%a+)$")
  if not v then v, h = where, "center" end
  local x, y
  if h == "left" then x = rect.x
  elseif h == "right" then x = rect.x + rect.w - block.w
  else x = rect.x + (rect.w - block.w) // 2 end
  if v == "top" then y = rect.y
  elseif v == "bottom" then y = rect.y + rect.h - block.h
  else y = rect.y + (rect.h - block.h) // 2 end
  return x, y
end

-- 摆进 rect 并返回 x, y, w, h（程序画文本框/历史面板时用得上）
function U.place(block, where, rect)
  local x, y = U.anchor_xy(block, where, rect)
  return x, y, block.w, block.h
end

-- 贴到内容区（phos.ui.sprite：左上角定位，'.' 与空格透明，bg 保留）
function U.draw(x, y, block, opts)
  opts = opts or {}
  phos.ui.sprite(x, y, block.rows, U.colors(block, opts.colors),
                 opts.step or 1, opts.brightness or 1)
end

-- 贴到带裁剪的区域（region:sprite；坐标相对该区域左上角）
function U.draw_in(region, x, y, block, opts)
  opts = opts or {}
  region:sprite(x, y, block.rows, U.colors(block, opts.colors),
                opts.step or 1, opts.brightness or 1)
end

-- ---------------------------------------------------------------- 版面组合（房间/结局/章卡用）
-- 画布是"行 × 列"的字符矩阵；组合完成后经 canvas_block 变成普通块。
-- 纯函数、无随机源：同一份代码每次 require 得到同一张图（文字基线/观感每帧一致）。
U.W, U.H = 80, 45
U.ROOM_H = 25   -- GDD §8.1：房间美术槽 25 行 × 80 列
U.CARD_H = 45   -- 标题/结局/章卡：整屏 45 行

function U.canvas(w, h)
  local rows = {}
  for y = 1, h do
    local row = {}
    for x = 1, w do row[x] = " " end
    rows[y] = row
  end
  return rows
end

-- 画布坐标一律 0 基（x 列 / y 行），与 phos.screen 一致；内部表 1 基由这里转换一次
function U.cput(c, x, y, ch)
  local row = c[y + 1]
  if row and row[x + 1] then row[x + 1] = ch end
end

function U.chline(c, x, y, w, ch)
  for i = 0, w - 1 do U.cput(c, x + i, y, ch) end
end

function U.cvline(c, x, y, h, ch)
  for i = 0, h - 1 do U.cput(c, x, y + i, ch) end
end

function U.crect(c, x, y, w, h, fill)
  U.chline(c, x, y, w, "-")
  U.chline(c, x, y + h - 1, w, "-")
  U.cvline(c, x, y, h, "|")
  U.cvline(c, x + w - 1, y, h, "|")
  U.cput(c, x, y, "+") U.cput(c, x + w - 1, y, "+")
  U.cput(c, x, y + h - 1, "+") U.cput(c, x + w - 1, y + h - 1, "+")
  if fill then
    for yy = y + 1, y + h - 2 do U.chline(c, x + 1, yy, w - 2, fill) end
  end
end

-- 贴一小块字符画：空格透明（不覆盖底图），其余字符覆盖——用于在房间壳上摆道具
function U.cstamp(c, x, y, art)
  local rows = type(art) == "string" and U.rows(art) or art
  for dy = 1, #rows do
    local row = rows[dy]
    for dx = 1, #row do
      local ch = row:sub(dx, dx)
      if ch ~= " " then U.cput(c, x + dx - 1, y + dy - 1, ch) end
    end
  end
end

-- 确定性伪随机（不用 math.random：主机会按启动种子播种，图样必须每次一样）
function U.rng(seed)
  local state = seed % 2147483647
  if state <= 0 then state = state + 2147483646 end
  return function()
    state = (state * 16807) % 2147483647
    return state / 2147483647
  end
end

-- 星场：按 rng 撒点，返回 (x, y, ch) 的落点；跳过的区域由调用方先记下
function U.stars(c, rng, count, opts)
  opts = opts or {}
  local x0, y0 = opts.x or 0, opts.y or 0
  local x1, y1 = opts.x2 or (#c[1] - 1), opts.y2 or (#c - 1)
  local chars = opts.chars or { "*", "'", "," }
  local weights = opts.weights or { 0.5, 0.8 }
  for _ = 1, count do
    local x = x0 + math.floor(rng() * (x1 - x0 + 1))
    local y = y0 + math.floor(rng() * (y1 - y0 + 1))
    local roll = rng()
    local ch = chars[#chars]
    for i = 1, #chars - 1 do
      if roll < weights[i] then ch = chars[i] break end
    end
    U.cput(c, x, y, ch)
  end
end

-- 画布 → 块（行右补到宽 w，默认 80；颜色键不变）
function U.canvas_block(id, c, colors, opts)
  opts = opts or {}
  local w = opts.w or #c[1]
  local rows = {}
  for y = 1, #c do
    local line = table.concat(c[y], "")
    if #line < w then line = line .. string.rep(" ", w - #line) end
    rows[y] = line
  end
  return U.block{
    id = id, rows = rows, colors = colors,
    anchor = opts.anchor or "top-left", note = opts.note,
  }
end

-- 全部可打印 ASCII 的兜底色：字母/数字→panel，其余符号→line。
-- 图样里出现的每个墨字都必须有颜色键（artcheck 会逐字核对），兜底表让"多打了一个字"
-- 不会掉到 sprite 的 accent 兜底色上。
function U.ascii_ink()
  local out = {}
  for code = 33, 126 do
    local ch = string.char(code)
    if ch:match("%u") or ch:match("%l") or ch:match("%d") then
      out[ch] = "panel"
    else
      out[ch] = "line"
    end
  end
  return out
end

-- 裁成固定尺寸：先删 drop 里列出的行（0 基下标），再右补/截到 w 列；行数不足 h 时补空行。
-- 房间/场景/结局都是固定槽位（25 或 45 行 × 80 列），程序按槽位直接贴，不做二次排版。
function U.fit(block, w, h, drop)
  local dropped = {}
  for _, index in ipairs(drop or {}) do dropped[index] = true end
  local rows = {}
  for i, row in ipairs(block.rows) do
    if not dropped[i - 1] then
      if #row > w then row = row:sub(1, w) end
      if #row < w then row = row .. string.rep(" ", w - #row) end
      rows[#rows + 1] = row
    end
  end
  while #rows < h do rows[#rows + 1] = string.rep(" ", w) end
  while #rows > h do rows[#rows] = nil end
  return U.block{ id = block.id, rows = rows, colors = block.colors,
                  anchor = block.anchor, note = block.note }
end

-- 行表右补到宽 w（按显示列数；本作图样全 ASCII，宽 = 字节数）
function U.pad_rows(rows, w)
  local out = {}
  for i = 1, #rows do
    local line = rows[i]
    if #line < w then line = line .. string.rep(" ", w - #line) end
    out[i] = line
  end
  return out
end

return U
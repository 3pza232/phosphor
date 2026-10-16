-- GRID（卡带墙）：把架上的卡带摆成一面网格。当前项以高亮边框圈出、其余变暗，
-- 底部一行给当前卡带的名称 + 简介。
--
-- 这是一段**只读绘制**脚本：主机把内容区交给它画，输入（左右移动光标 / 搜索 /
-- Enter 插卡 / Esc）仍归主机。画布是 phos.screen（内容区局部坐标，80x45）。
-- 上下文 ctx 见 docs/content-packs.md 的「shelf（卡带架样式）」一节。

-- 顶层声明（主机在扫描时读它们，不进入 draw 的 ctx）：
--   name 本地化显示名（设置里"卡带架样式"一行显示它；缺 en 回落 zh，没声明回落文件夹名）
--   cols 每行个数（主机据此把上下键映射为逐行移动）
name = { zh = "卡片墙", en = "GRID" }
local COLS = 4
cols = COLS

local S, C, T = phos.screen, phos.color, phos.text

-- 本包自己的文案：缺 en 由 phos.lang.dict 回落中文，两者都缺也不至于空串
local Text = {
  zh = { broken = "（坏卡）", empty = "（无卡带）" },
  en = { broken = "(BROKEN)", empty = "(NO CART)" },
}

-- ctx.colors.* 是 {r,g,b} 表：转成主机颜色对象，bright 用来压暗未选中项。
-- 颜色一律来自主机（随主题/色板走），包不写死任何 rgb
local function col(rgb, bright)
  bright = bright or 1
  return C.rgb(rgb.r * bright, rgb.g * bright, rgb.b * bright)
end

-- 逐像素画图标：按 step 取样（半尺寸 = step 2），bright 统一压暗，缺色的像素用兜底色。
-- 与 phos.ui.sprite 同一套语义，但这里要"未选中变暗"，所以自己走一遍
local function draw_icon(x, y, rows, colors, step, bright, fallback)
  local draw_h = math.floor((#rows + step - 1) / step)
  local src_w = 0
  for i = 1, #rows do
    local w = T.width(rows[i])
    if w > src_w then src_w = w end
  end
  local draw_w = math.floor((src_w + step - 1) / step)
  for dy = 0, draw_h - 1 do
    local row = rows[dy * step + 1]
    if row then
      for k = 1, #row do
        local col_i = k - 1  -- 0 基列号（图标是 ASCII 字符画，多字节字符不参与）
        if col_i % step == 0 then  -- 每 step 列取一个：与 ui::icon 的取样一致
          local ch = row:sub(k, k)
          if ch ~= " " and ch ~= "." then
            local rgb = colors[ch]
            local c = rgb and col(rgb, bright) or fallback
            S.put(x + math.floor(col_i / step), y + dy, ch, c)
          end
        end
      end
    end
  end
  return draw_w, draw_h
end

-- 无图标时的兜底：一个简洁的卡带盒字符画（名字画在下面一格）
local function draw_placeholder(cx, y, bright, fallback)
  local c = fallback
  S.put(cx - 4, y + 0, ".", c)
  S.print(cx - 3, y + 0, "------", c)
  S.put(cx + 3, y + 0, ".", c)
  S.put(cx - 4, y + 1, "|", c)
  S.print(cx - 2, y + 1, "####", c)
  S.put(cx + 3, y + 1, "|", c)
  S.print(cx - 4, y + 2, "'------'", c)
end

-- 名称居中、按显示宽度截断（中文一列算 2 格：#str 是字节数，不能用）
local function center_text(x, y, w, text, fg)
  local t = T.truncate(text, w)
  local pad = math.floor((w - T.width(t)) / 2)
  if pad < 0 then pad = 0 end
  S.print(x + pad, y, t, fg)
end

function draw(ctx)
  local pal = ctx.colors
  local t = phos.lang.dict(Text)
  local carts, cursor, count = ctx.carts, ctx.cursor, ctx.count
  if count <= 0 then return end  -- 空列表由主机处理，这里兜底不画

  local w, h = ctx.content.w, ctx.content.h

  -- 布局：让开主机 chrome 的标题行 + 分隔线（上 3 行）与页脚（下 2 行）；
  -- 底部 info_h 行留给当前卡带的名称 + 简介，其余给网格
  local top = 3
  local footer = 2
  local info_h = 3
  local grid_top = top
  local grid_h = h - top - footer - info_h
  local cell_w = 20
  local cell_h = 12
  -- 列数用声明的 COLS（与主机导航一致）；卡带不足一行时收窄到实际数量
  local cols = math.min(COLS, count)
  local rows_visible = math.max(1, math.floor(grid_h / cell_h))
  local total_rows = math.ceil(count / cols)

  -- 让选中项始终可见：把首行滑到选中行附近
  local sel = cursor
  local sel_row = math.floor((sel - 1) / cols)
  local first_row = sel_row - math.floor(rows_visible / 2)
  local max_first = math.max(0, total_rows - rows_visible)
  if first_row < 0 then first_row = 0 end
  if first_row > max_first then first_row = max_first end

  local grid_w = cols * cell_w
  local origin_x = math.floor((w - grid_w) / 2)

  for r = 0, rows_visible - 1 do
    local row_index = first_row + r
    if row_index >= total_rows then break end
    for c = 0, cols - 1 do
      local i = row_index * cols + c + 1
      if i > count then break end
      local cart = carts[i]
      local selected = (i == sel)
      local x = origin_x + c * cell_w
      local y = grid_top + r * cell_h

      local border = selected and col(pal.accent) or col(pal.dim, 0.7)
      local fg = selected and col(pal.fg) or col(pal.dim)
      local bright = selected and 1.0 or 0.55

      -- 边框
      for dx = 1, cell_w - 2 do
        S.put(x + dx, y, "-", border)
        S.put(x + dx, y + cell_h - 1, "-", border)
      end
      for dy = 1, cell_h - 2 do
        S.put(x, y + dy, "|", border)
        S.put(x + cell_w - 1, y + dy, "|", border)
      end
      S.put(x, y, "+", border)
      S.put(x + cell_w - 1, y, "+", border)
      S.put(x, y + cell_h - 1, "+", border)
      S.put(x + cell_w - 1, y + cell_h - 1, "+", border)

      -- 图标（内容盒内居中；有字符画用 1x/2x 缩放的图标，没有就画兜底卡带盒）
      local inner_w = cell_w - 2
      local inner_h = cell_h - 3  -- 最后一行留给名字
      local rows_icon = cart.icon_rows
      if rows_icon and #rows_icon > 0 then
        local src_w, src_h = 0, #rows_icon
        for k = 1, src_h do
          local iw = T.width(rows_icon[k])
          if iw > src_w then src_w = iw end
        end
        local step = (src_w <= inner_w and src_h <= inner_h) and 1 or 2
        local dw = math.floor((src_w + step - 1) / step)
        local dh = math.floor((src_h + step - 1) / step)
        local ix = x + 1 + math.max(0, math.floor((inner_w - dw) / 2))
        local iy = y + 1 + math.max(0, math.floor((inner_h - dh) / 2))
        draw_icon(ix, iy, rows_icon, cart.icon_colors or {}, step, bright, col(pal.accent))
      else
        draw_placeholder(x + math.floor(cell_w / 2), y + 3, bright, col(pal.accent))
      end

      -- 名称：选中项用高亮色，其余压暗
      local name = cart.name or ""
      if cart.broken then name = name .. t.broken end
      center_text(x + 1, y + cell_h - 2, inner_w, name, fg)
    end
  end

  -- 右侧一列小刻度：行数多于一屏时画一条滚动条，让"还有下一页"看得出来。
  -- 它压在最后一列的右边框上（网格正好铺满内容区，不额外占位）：暗色是轨道，亮色是滑块
  if total_rows > rows_visible then
    local track_x = w - 1
    local span = rows_visible * cell_h
    local thumb_h = math.max(1, math.floor(span * rows_visible / total_rows))
    local denom = total_rows - rows_visible
    local thumb_y = grid_top + (denom > 0 and math.floor((span - thumb_h) * first_row / denom) or 0)
    for y = grid_top, grid_top + span - 1 do
      S.put(track_x, y, "|", col(pal.dim, 0.5))
    end
    for y = thumb_y, math.min(thumb_y + thumb_h - 1, grid_top + span - 1) do
      S.put(track_x, y, "#", col(pal.accent))
    end
  end

  -- 底部：当前卡带的名称 + 简介（分隔线 + 两行）
  local info_y = grid_top + rows_visible * cell_h
  for dx = 0, w - 1 do
    S.put(dx, info_y, "-", col(pal.dim, 0.6))
  end
  local cart = carts[sel]
  if cart then
    local name = cart.name or ""
    if cart.broken then name = name .. t.broken end
    S.print(1, info_y + 1, T.truncate(name, w - 2), col(pal.accent))
    S.print(1, info_y + 2, T.truncate(cart.desc or "", w - 2), col(pal.fg, 0.9))
  end
end

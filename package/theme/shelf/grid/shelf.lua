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

-- 跨屏滚动的动效状态存在包自己的模块局部里（跨每帧调用保留）。缓动用 ctx.time
-- 的**增量**算，与所画内容同一时基；主机每逻辑帧都会调本包，动画因此在档位上跑
local scroll = nil     -- 当前平滑首行位置（浮点，向目标行逼近）
local last_time = nil  -- 上一帧的架子时钟（秒）
local EASE_RATE = 16   -- 指数逼近速率：约 0.12s 基本到位（与帧率无关，不跳变）

-- 网格带（内容区局部坐标的上下界）：滚动动画中行会移出带外，逐笔裁剪，
-- 免得盖到顶部标题行或底部信息区。所有网格内的写入都走这两个裁剪原语
local band_top, band_bottom = 0, 0
local function bput(x, y, ch, color)
  if y >= band_top and y < band_bottom then S.put(x, y, ch, color) end
end
local function bprint(x, y, text, color)
  if y >= band_top and y < band_bottom then S.print(x, y, text, color) end
end

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
            bput(x + math.floor(col_i / step), y + dy, ch, c)
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
  bput(cx - 4, y + 0, ".", c)
  bprint(cx - 3, y + 0, "------", c)
  bput(cx + 3, y + 0, ".", c)
  bput(cx - 4, y + 1, "|", c)
  bprint(cx - 2, y + 1, "####", c)
  bput(cx + 3, y + 1, "|", c)
  bprint(cx - 4, y + 2, "'------'", c)
end

-- 名称居中、按显示宽度截断（中文一列算 2 格：#str 是字节数，不能用）
local function center_text(x, y, w, text, fg)
  local t = T.truncate(text, w)
  local pad = math.floor((w - T.width(t)) / 2)
  if pad < 0 then pad = 0 end
  bprint(x + pad, y, t, fg)
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

  -- 让选中项始终可见：目标首行滑到选中行附近（整数目标）
  local sel = cursor
  local sel_row = math.floor((sel - 1) / cols)
  local first_row = sel_row - math.floor(rows_visible / 2)
  local max_first = math.max(0, total_rows - rows_visible)
  if first_row < 0 then first_row = 0 end
  if first_row > max_first then first_row = max_first end

  -- 平滑滚动：一条浮点首行位置指数逼近目标（约 0.12s 基本到位），不硬跳。
  -- 只用 ctx.time 增量，动画速度与帧率无关；首帧直接落到目标，避免开场滑一段
  local now = ctx.time or 0
  local dt = 0
  if last_time then dt = now - last_time end
  last_time = now
  if dt < 0 then dt = 0 end
  if dt > 0.1 then dt = 0.1 end
  if scroll == nil then scroll = first_row end
  scroll = scroll + (first_row - scroll) * (1 - math.exp(-EASE_RATE * dt))
  if math.abs(first_row - scroll) < 0.01 then scroll = first_row end

  -- 相对静态布局的整体纵向位移（0 时与旧版逐格一致）
  local yoff = math.floor((first_row - scroll) * cell_h + 0.5)

  local grid_w = cols * cell_w
  local origin_x = math.floor((w - grid_w) / 2)

  band_top = grid_top
  band_bottom = grid_top + rows_visible * cell_h

  -- 选中框的"呼吸"：轻微明暗起伏，幅度小、不刺眼（跨屏滑动时另加位置动效）
  local breath = 0.78 + 0.22 * (0.5 + 0.5 * math.sin(now * 6.28318 / 1.6))

  -- 上下各多画一行：滚入/滚出的一行也参与滑动（带外由 bput/bprint 裁掉）
  for rr = -1, rows_visible do
    local row_index = first_row + rr
    if row_index >= 0 and row_index < total_rows then
      local y = grid_top + rr * cell_h + yoff
      for c = 0, cols - 1 do
        local i = row_index * cols + c + 1
        if i > count then break end
        local cart = carts[i]
        local selected = (i == sel)
        local x = origin_x + c * cell_w

        local border = selected and col(pal.accent, breath) or col(pal.dim, 0.7)
        local fg = selected and col(pal.fg) or col(pal.dim)
        local bright = selected and 1.0 or 0.55

        -- 边框
        for dx = 1, cell_w - 2 do
          bput(x + dx, y, "-", border)
          bput(x + dx, y + cell_h - 1, "-", border)
        end
        for dy = 1, cell_h - 2 do
          bput(x, y + dy, "|", border)
          bput(x + cell_w - 1, y + dy, "|", border)
        end
        bput(x, y, "+", border)
        bput(x + cell_w - 1, y, "+", border)
        bput(x, y + cell_h - 1, "+", border)
        bput(x + cell_w - 1, y + cell_h - 1, "+", border)

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

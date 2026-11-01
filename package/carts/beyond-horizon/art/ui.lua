-- art/ui.lua —— 界面装饰元素（文本框 / 资源条 / 历史面板 / 噪点 / 边框角标）。
--
-- 只提供"装饰"：文字、数值、焦点仍由程序画（phos.ui.render / phos.screen）。
-- 所有块都用 util 的语义色键（换主题自动换色），行只含 ASCII（任何字体方案都不缺字）。
--
-- 稳定 id 一览（程序用 Art.draw_id 或 Art.blocks 取）：
--   ui.textbox        78x17  对话文本框外框（含说话人牌位与底部键位栏）
--   ui.history        78x40  历史面板外框 + 右侧滚动轨
--   ui.choice_on      42x1   选中选项行（> 标记 + 点线引导）
--   ui.choice_off     42x1   未选中选项行
--   ui.bar_frame      20x1   资源条外框 [..........]
--   ui.bar_low        20x1   低值资源条（! 标记）
--   ui.hud_rule       80x1   顶部 HUD 下的仪器刻线
--   ui.divider_label  70x1   带标签槽的分隔线 ----[ 标签 ]----
--   ui.alert_banner   60x3   警示斜纹横幅
--   ui.map_node       9x3    地图房间节点框（框内留给程序画名字/图标）
--   ui.corner_tl/tr/bl/br 5x3  四角取景框角标
--   ui.scanlines      80x1   CRT 扫描线（隔行稀疏点）
--   ui.glitch_a/b/c   39x2 / 36x2 / 26x3  故障噪点条
--   ui.icon.o2/pwr/str/san 5x3 资源图标（O/P/S/M），另有 UIm.icons 字符表
local U = require("art.util")

local LINE = { ["+"] = "line", ["-"] = "line", ["|"] = "line",
               [","] = "panel", ["'"] = "panel", ["["] = "line", ["]"] = "line" }
local function merge(...)
  local out = {}
  for _, src in ipairs({ ... }) do
    if src then for k, v in pairs(src) do out[k] = v end end
  end
  return out
end

-- ---------------------------------------------------------------- 对话框 78x17
local function build_textbox()
  local c = U.canvas(78, 17)
  -- 顶边：左侧留出说话人牌（[          ]），其余是单线
  local top = ",--[          ]" .. string.rep("-", 78 - 15 - 1) .. ","
  for x = 1, 78 do U.cput(c, x - 1, 0, top:sub(x, x)) end
  U.cvline(c, 0, 1, 15, "|")
  U.cvline(c, 77, 1, 15, "|")
  -- 正文区与键位栏之间的内部分隔线
  U.chline(c, 1, 13, 76, "-")
  U.cput(c, 0, 13, "+")
  U.cput(c, 77, 13, "+")
  -- 底边
  U.chline(c, 0, 16, 78, "-")
  U.cput(c, 0, 16, "'")
  U.cput(c, 77, 16, "'")
  -- 键位栏左侧的小刻度（只是仪器感，键位文字由程序画）
  U.cput(c, 1, 14, "+")
  U.cput(c, 76, 14, "+")
  U.chline(c, 2, 14, 74, " ")
  local b = U.canvas_block("ui.textbox", c, merge(LINE, {
    ["("] = "line", [")"] = "line",
  }), { note = "78x17 对话文本框：说话人牌 + 正文区 + 键位栏" })
  -- 程序用的槽位（相对文本框左上角）
  b.slots = {
    speaker = { x = 5, y = 0, w = 10 },   -- 说话人名字（半角 10 列；CJK 约 5 字）
    body = { x = 3, y = 2, w = 72, h = 10 },  -- 正文（每行 72 列，最多 3 行）
    hint = { x = 2, y = 14, w = 74 },     -- 键位提示
  }
  return b
end

-- ---------------------------------------------------------------- 历史面板 78x40
local function build_history()
  local c = U.canvas(78, 40)
  U.crect(c, 0, 0, 78, 40)
  -- 顶边中间开一个标题槽
  local title = "--[ LOG ]"
  for x = 1, #title do U.cput(c, 32 + x - 1, 0, title:sub(x, x)) end
  -- 右侧滚动轨：外框内两列
  U.cvline(c, 73, 1, 38, "|")
  U.cvline(c, 74, 1, 38, " ")
  for y = 2, 37, 2 do U.cput(c, 74, y, "-") end
  local b = U.canvas_block("ui.history", c, merge(LINE, U.ascii_ink(), { ["L"] = "ice", ["O"] = "ice", ["G"] = "ice" }),
    { note = "78x40 历史面板：外框 + 右侧滚动轨" })
  b.slots = {
    body = { x = 2, y = 2, w = 69, h = 35 },   -- 历史条目区
    rail = { x = 73, y = 2, w = 2, h = 35 },   -- 滚动轨（程序画游标）
  }
  return b
end

-- ---------------------------------------------------------------- 选项行 42x1
local function build_choice(selected)
  local prefix = selected and "> " or "  "
  local row = prefix .. string.rep(" ", 2)
  -- 点线引导到右侧标记槽
  row = row .. string.rep(",", 30) .. " "
  row = row .. (selected and "[*]" or "[ ]")
  if #row < 42 then row = row .. string.rep(" ", 42 - #row) end
  local b = U.block{
    id = selected and "ui.choice_on" or "ui.choice_off",
    rows = { row },
    colors = { [">"] = "ice", [","] = "panel", ["["] = "line", ["]"] = "line",
               ["*"] = "ice", [" "] = "void" },
    anchor = "top-left",
    note = selected and "42x1 选中选项行（前缀 + 点线 + 标记）"
                      or "42x1 未选中选项行",
  }
  b.slots = { label = { x = 3, y = 0, w = 32 }, mark = { x = 38, y = 0, w = 4 } }
  return b
end

-- ---------------------------------------------------------------- 资源条 20x1
local function build_bar(low)
  local cells = low and (string.rep("#", 3) .. string.rep("-", 14) .. "!")
                     or (string.rep("#", 8) .. string.rep("-", 10))
  local row = "[" .. cells .. "]"
  local b = U.block{
    id = low and "ui.bar_low" or "ui.bar_frame",
    rows = { row },
    colors = { ["["] = "line", ["]"] = "line", ["#"] = low and "alert" or "signal",
               ["-"] = "panel", ["!"] = "alert" },
    anchor = "top-left",
    note = low and "20x1 低值资源条（末格 ! 提示）" or "20x1 资源条外框",
  }
  b.slots = { fill = { x = 1, y = 0, w = 18 } }   -- 18 格 = 20 宽去掉两端括号
  return b
end

-- ---------------------------------------------------------------- 硬件装饰
local function build_hud_rule()
  local c = U.canvas(80, 1)
  for x = 0, 79 do U.cput(c, x, 0, (x % 6 == 0) and "+" or "-") end
  return U.canvas_block("ui.hud_rule", c, { ["+"] = "line", ["-"] = "line" },
    { note = "80x1 HUD 仪器刻线（每 6 列一档）" })
end
local HUD_RULE = build_hud_rule()

local DIVIDER_LABEL = U.block{
  id = "ui.divider_label",
  art = [==[
-----+------[          ]------+---------------------------------------
]==],
  colors = { ["-"] = "line", ["+"] = "line", ["["] = "line", ["]"] = "line" },
  anchor = "top-left",
  note = "70x1 带标签槽的分隔线（标签由程序打印）",
}
DIVIDER_LABEL.slots = { label = { x = 15, y = 0, w = 10 } }

local ALERT_BANNER = U.block{
  id = "ui.alert_banner",
  art = [==[
/ / / / / / / / / / / / / / / / / / / / / / / / / / / / / / /
 / / / / / / / / / / / / / / / / / / / / / / / / / / / / / /
/ / / / / / / / / / / / / / / / / / / / / / / / / / / / / / /
]==],
  colors = { ["/"] = "warn" }, anchor = "top-left",
  note = "60x3 警示斜纹横幅（红/黄由 overrides 换）",
}

local MAP_NODE = U.block{
  id = "ui.map_node",
  art = [==[
+-------+
|       |
+-------+
]==],
  colors = { ["+"] = "line", ["-"] = "line", ["|"] = "line" },
  anchor = "top-left", note = "9x3 地图房间节点框（名字/图标由程序画）",
}
MAP_NODE.slots = { label = { x = 1, y = 1, w = 7 } }

local CORNER_TL = U.block{
  id = "ui.corner_tl",
  art = [==[
+----
|
|
]==],
  colors = { ["+"] = "line", ["-"] = "line", ["|"] = "line" },
  anchor = "top-left", note = "6x3 取景框左上角标",
}
local CORNER_TR = U.block{
  id = "ui.corner_tr",
  art = [==[
----+
    |
    |
]==],
  colors = { ["+"] = "line", ["-"] = "line", ["|"] = "line" },
  anchor = "top-left", note = "6x3 取景框右上角标",
}
local CORNER_BL = U.block{
  id = "ui.corner_bl",
  art = [==[
|
|
+----
]==],
  colors = { ["+"] = "line", ["-"] = "line", ["|"] = "line" },
  anchor = "top-left", note = "6x3 取景框左下角标",
}
local CORNER_BR = U.block{
  id = "ui.corner_br",
  art = [==[
    |
    |
----+
]==],
  colors = { ["+"] = "line", ["-"] = "line", ["|"] = "line" },
  anchor = "top-left", note = "6x3 取景框右下角标",
}

local function build_scanlines()
  local row = {}
  for x = 0, 79 do row[x + 1] = (x % 2 == 0) and "," or " " end
  return U.block{ id = "ui.scanlines", rows = { table.concat(row) },
                  colors = { [","] = "panel" }, anchor = "top-left",
                  note = "80x1 隔格稀疏点（CRT 扫描线/尘埃，叠在画面上）" }
end
local SCANLINES = build_scanlines()

local GLITCH_A = U.block{
  id = "ui.glitch_a",
  art = [==[
  %  &   , %   &  ,   % &  ,  %   &   ,
 &   ,  %  &   % ,  &   %  ,   &  %  &
]==],
  colors = { ["%"] = "glitch", ["&"] = "ghost", [","] = "panel" },
  anchor = "top-left", note = "40x2 故障噪点（轻）",
}

local GLITCH_B = U.block{
  id = "ui.glitch_b",
  art = [==[
 &%   %,&  &   %  , %&  %   , &  %  
   &  %  ,  &%  ,   %  &  %   ,  %&
]==],
  colors = { ["%"] = "glitch", ["&"] = "glitch", [","] = "panel" },
  anchor = "top-left", note = "30x2 故障噪点（中）",
}

local GLITCH_C = U.block{
  id = "ui.glitch_c",
  art = [==[
 %&&,  % &,   && %  ,&  %&
,  &  %,  &&  , %  &%  , &
 &%  ,&&  %  &,  %&  &  %,
]==],
  colors = { ["%"] = "glitch", ["&"] = "glitch", [","] = "panel" },
  anchor = "top-left", note = "24x3 故障噪点（强）",
}

-- ---------------------------------------------------------------- 资源图标 5x3
local function res_icon(id, sym, key)
  return U.block{
    id = "ui.icon." .. id,
    art = [==[
,---,
| S |
'---'
]==],
    rows = { ",---,", "| " .. sym .. " |", "'---'" },
    colors = merge(LINE, { [sym] = key }),
    anchor = "top-left",
    note = "5x3 资源图标 " .. id,
  }
end

local UI = {
  textbox = build_textbox(),
  history = build_history(),
  choice_on = build_choice(true),
  choice_off = build_choice(false),
  bar_frame = build_bar(false),
  bar_low = build_bar(true),
  hud_rule = HUD_RULE,
  divider_label = DIVIDER_LABEL,
  alert_banner = ALERT_BANNER,
  map_node = MAP_NODE,
  corner_tl = CORNER_TL,
  corner_tr = CORNER_TR,
  corner_bl = CORNER_BL,
  corner_br = CORNER_BR,
  scanlines = SCANLINES,
  glitch_a = GLITCH_A,
  glitch_b = GLITCH_B,
  glitch_c = GLITCH_C,
  icons = { o2 = "O", pwr = "P", str = "S", san = "M" },
  blocks = {},
}

UI.icon = {
  o2 = res_icon("o2", "O", "ice"),
  pwr = res_icon("pwr", "P", "warn"),
  str = res_icon("str", "S", "signal"),
  san = res_icon("san", "M", "ghost"),
}

for key, block in pairs(UI) do
  if type(block) == "table" and block.id then UI.blocks[block.id] = block end
end
for key, block in pairs(UI.icon) do UI.blocks["ui.icon." .. key] = block end
return UI
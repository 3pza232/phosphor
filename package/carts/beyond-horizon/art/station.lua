-- art/station.lua —— 界外站（HORIZON-1）的房间图标、缩略图、站点示意图与星图。
--
-- 坐标：块的左上角由程序决定；块内的 node 坐标相对该块左上角。
-- 图样只含 ASCII（仪器铭文/编号是装饰，不是可本地化文案；房间名由程序画）。
-- 注意：'.' 是 sprite 的透明字符，图样里一律不用它当墨（本文件用 , ' 代替点）。
local U = require("art.util")

-- ---------------------------------------------------------------- 小工具
local function merge(...)
  local out = {}
  for _, src in ipairs({ ... }) do
    if src then for k, v in pairs(src) do out[k] = v end end
  end
  return out
end

-- 一段文字用的颜色表：每个非空字符同一语义色（仪器铭文常用）
local function chars(str, key)
  local out = {}
  for i = 1, #str do
    local ch = str:sub(i, i)
    if ch ~= " " then out[ch] = key end
  end
  return out
end

local FRAME = { [","] = "line", ["'"] = "line", ["|"] = "line", ["-"] = "line",
                ["+"] = "line" }

-- ---------------------------------------------------------------- 房间图标（5x3）
-- 框用 , ' |；内芯一个字符，颜色按房间语义给。程序在节点处贴它即可。
local function icon(sym, key)
  local b = U.block{
    art = [==[
,---,
| Z |
'---'
]==],
    colors = merge(FRAME, { [sym] = key }),
    note = "5x3 节点图标",
  }
  b.rows = { ",---,", "| " .. sym .. " |", "'---'" }
  return b
end

-- ---------------------------------------------------------------- 房间缩略图（18x7）
local THUMB_W = 18
local function thumb(id, inner, colors)
  local rows = { "," .. string.rep("-", THUMB_W - 2) .. "," }
  for i = 1, 5 do
    local line = inner[i] or ""
    if #line > THUMB_W - 2 then line = line:sub(1, THUMB_W - 2) end
    rows[#rows + 1] = "|" .. line .. string.rep(" ", THUMB_W - 2 - #line) .. "|"
  end
  rows[#rows + 1] = "'" .. string.rep("-", THUMB_W - 2) .. "'"
  return U.block{ id = "station.thumb." .. id, rows = rows, colors = colors,
                  note = "18x7 房间缩略图" }
end

local CRYO_THUMB = thumb("cryo", {
  "+--+   +--+",
  "|##|   |##|",
  "|##|   |##|",
  "+--+   +--+",
  "  |      |",
}, merge(FRAME, { ["+"] = "ice", ["#"] = "deep" }))

local OBS_THUMB = thumb("observation", {
  "   ,------,",
  "  /  *    \\",
  " |    o    |",
  "  \\  ,--,  /",
  "   '------'",
}, merge(FRAME, { ["*"] = "body", ["o"] = "ice", ["/"] = "line", ["\\"] = "line" }))

local REACTOR_THUMB = thumb("reactor", {
  "  ,------,",
  "  |######|",
  "  |######|",
  "  '------'",
  "  ||||||||",
}, merge(FRAME, { ["#"] = "warm" }))

local MED_THUMB = thumb("medbay", {
  "     |    ",
  "   +-+-+  ",
  "   | + |  ",
  " ,-+---+  ",
  " |=====|  ",
}, merge(FRAME, { ["+"] = "ice", ["="] = "panel" }))

local COMMS_THUMB = thumb("comms", {
  "     ,--, ",
  "    (    )",
  "     '--' ",
  "  ,--,    ",
  "  '--'    ",
}, merge(FRAME, { ["("] = "line", [")"] = "line" }))

local BRIDGE_THUMB = thumb("bridge", {
  " ,----------,",
  " |  *  *  * |",
  " '----------'",
  "   ,--, ,--,",
  "   '--' '--'",
}, merge(FRAME, { ["*"] = "body" }))

local AIRLOCK_THUMB = thumb("airlock", {
  "  ,--------,",
  " /  |    |  \\",
  " |  |    |  |",
  " \\  '----'  /",
  "  '--------'",
}, merge(FRAME, { ["/"] = "line", ["\\"] = "line" }))

local UNKNOWN_THUMB = thumb("unknown", {
  "  ,--------,",
  " /  ?  %  ?\\",
  " | %  ?  % |",
  " \\ ?  %  ? /",
  "  '--------'",
}, merge(FRAME, { ["?"] = "glitch", ["%"] = "ghost", ["/"] = "line", ["\\"] = "line" }))

-- ---------------------------------------------------------------- 房间表
local ROOM_DEFS = {
  { id = "cryo", name_zh = "休眠舱", name_en = "CRYO BAY", sym = "z", key = "ice",
    thumb = CRYO_THUMB },
  { id = "observation", name_zh = "观测甲板", name_en = "OBSERVATION DECK", sym = "*",
    key = "body", thumb = OBS_THUMB },
  { id = "reactor", name_zh = "反应堆", name_en = "REACTOR", sym = "@", key = "warm",
    thumb = REACTOR_THUMB },
  { id = "medbay", name_zh = "医疗舱", name_en = "MED BAY", sym = "+", key = "ice",
    thumb = MED_THUMB },
  { id = "comms", name_zh = "通信阵列", name_en = "COMM ARRAY", sym = "~", key = "signal",
    thumb = COMMS_THUMB },
  { id = "bridge", name_zh = "舰桥", name_en = "BRIDGE", sym = "^", key = "body",
    thumb = BRIDGE_THUMB },
  { id = "airlock", name_zh = "气闸", name_en = "AIRLOCK", sym = "O", key = "ice",
    thumb = AIRLOCK_THUMB },
  { id = "unknown", name_zh = "未知舱室", name_en = "UNKNOWN BAY", sym = "?",
    key = "glitch", thumb = UNKNOWN_THUMB },
}

local rooms = {}
local room_order = {}
for i, def in ipairs(ROOM_DEFS) do
  local ic = icon(def.sym, def.key)
  ic.id = "station.icon." .. def.id
  rooms[def.id] = {
    id = def.id,
    name_zh = def.name_zh,
    name_en = def.name_en,
    icon = ic,
    thumb = def.thumb,
  }
  room_order[i] = def.id
end

-- ---------------------------------------------------------------- 站点示意图（64x22）
-- 8 个房间方框 + 中央核心；框内不写字，程序按 nodes 坐标画房间名/图标/状态。
-- 方框 9x3：名字可画在 (x+1, y+1)，图标可画在 (x+1, y+1) 起 5x1。
local MAP = U.block{
  id = "station.map",
  art = [==[

    +-------+               |                +-------+
    |       |+--------------|----------------+       |
    +-------+               |                +-------+
                            |
                            |
    +-------+               |                +-------+
    |       |+--------------|----------------+       |
    +-------+               |                +-------+
                       +---------+
                       |    O    |
    +-------+          +---------+           +-------+
    |       |+--------------|----------------+       |
    +-------+               |                +-------+
                            |
                            |
    +-------+               |                +-------+
    |       |+--------------|----------------+       |
    +-------+               |                +-------+
                            |

]==],
  colors = merge(FRAME, { ["O"] = "ice" }),
  note = "54x21 站点示意图：中央脊柱 + 八舱室节点 + 核心标记",
}

-- 节点坐标（相对 station.map 左上角）：w/h 是方框尺寸，框内可画名字/图标。
MAP.nodes = {
  cryo = { x = 4, y = 0, w = 9, h = 3 },
  observation = { x = 45, y = 0, w = 9, h = 3 },
  medbay = { x = 4, y = 5, w = 9, h = 3 },
  comms = { x = 45, y = 5, w = 9, h = 3 },
  reactor = { x = 4, y = 10, w = 9, h = 3 },
  bridge = { x = 45, y = 10, w = 9, h = 3 },
  airlock = { x = 4, y = 15, w = 9, h = 3 },
  unknown = { x = 45, y = 15, w = 9, h = 3 },
}
MAP.core = { x = 23, y = 8, w = 11, h = 3 }

-- ---------------------------------------------------------------- 星图（80x24）
-- 深空观测盘读数：星场 + 右下黑洞 + 站点轨道 + 边缘刻度。
-- 铭文是 ASCII 仪器标记（"-" 标尺、"BH-1"/"40 rs" 读数），不参与本地化。
-- 铭文字符统一给一个兜底色，避免逐字列颜色表（也保证漏一个也不会掉到 accent）
local INSTRUMENT = {}
for ch in ("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789[]/:"):gmatch(".") do
  INSTRUMENT[ch] = "panel"
end

local STARMAP = U.block{
  id = "station.starmap",
  art = [==[
+-----------+-----------+-----------+-----------+-----------+-----------+------+

    *       ,      *    ''        ,                    *         ,           *
 *  **    *    * ,                     '    '  *               '    ,      ',
            *       |                , *                             '
          ,         | '  *         **                                  *    '
             *
       *    *    ---+---     *                   *
           '''                '                         OOOOO           *
                  *        *                  ==  ==****O   O====-- *-- '
         *  '    ' '        *     '         === ***    O     o    === ---
  '                           ' *       *  =   *       o     o       =  ,-*
               *            ,    *,     * ,== =*****   o     o   =====- --
      ' *      *          ,, , ,, ,,',, ,, ,, =====*** =o   o- ===-----
          *       * ,, ,,        ,  '         ,,        ooooo        *     *
           *   , ,,                           '                     '  '  *
    [H1]    , , '                  '           '                            *
    '   *  , '      *  *               *       *  *                       *   '
              *          *    '  ,                ''             *
   HORIZON-1 / ORBIT 40 rs                                                  '
   BH-1  3E8 MSUN             ,                     ,   **
   RANGE 9E11 M

+-----------+-----------+-----------+-----------+-----------+-----------+------+
]==],
  colors = merge(FRAME, INSTRUMENT, {
    ["*"] = "body", ["'"] = "panel", [","] = "panel",
    ["O"] = "body", ["o"] = "ice", ["="] = "ice",
  }, chars("3E8", "warn")),
  note = "80x24 星图：星场 + 黑洞（环/吸积盘）+ 轨道与读数铭文",
}

STARMAP.markers = {
  station = { x = 4, y = 16 },
  blackhole = { x = 58, y = 11 },
  reticle = { x = 20, y = 7 },
}

-- ---------------------------------------------------------------- 站点剪影（56x14）
-- 远处看到的界外站：环 + 中央轴 + 一盏还亮着的窗（远景/舰桥窗外用）。
local SILHOUETTE = U.block{
  id = "station.silhouette",
  art = [==[
                    ,--------,
              ,----'          '----,
          ,--'                    '--,
      ,--'     ,---------------,      '--,
   ,-'        /  ,----------,   \        '-,
  /          |  /   ,----,   \  |          \
 |           | |   |  o  |   | |           |
  \          |  \  '----'  /  |          /
   '-,        \  '--------'  /        ,-'
      '-,       '-----------'       ,-'
          '-,                    ,-'
              '-,            ,-'
                  '----------'
]==],
  colors = merge(FRAME, { ["-"] = "panel", ["/"] = "panel", ["\\"] = "panel",
                          ["o"] = "ice" }),
  note = "56x14 远景站点剪影（窗是唯一亮部）",
}

local S = {
  rooms = rooms,
  room_order = room_order,
  map = MAP,
  starmap = STARMAP,
  silhouette = SILHOUETTE,
  blocks = {},
}
S.blocks["station.map"] = MAP
S.blocks["station.starmap"] = STARMAP
S.blocks["station.silhouette"] = SILHOUETTE
for id, room in pairs(rooms) do
  S.blocks["station.icon." .. id] = room.icon
  S.blocks["station.thumb." .. id] = room.thumb
end
return S
-- art/rooms.lua —— 12 个房间的 80x25 房间画面（探索界面 y=2..26 的美术槽）。
--
-- 每间房 = 共用舱室壳（顶灯/墙板/地板格）+ 本房间道具；同一份代码确定性生成，
-- 每帧贴出来完全一样（文字基线稳定）。房间名/状态/交互标记由程序画在画面之上。
--
-- 稳定 id：room.cryo / .med / .hub / .galley / .maint / .reactor / .obs / .bridge /
--          .array / .null / .pod / .airlock
-- 变体（同为 80x25 的独立块，直接替换基底画）：后缀 .open/.lit/.flare/.body/.alert/
--          .contact/.locked/.quiet
local U = require("art.util")

local function merge(...)
  local out = {}
  for _, src in ipairs({ ... }) do
    if src then for k, v in pairs(src) do out[k] = v end end
  end
  return out
end

-- 舱室壳：80x25；code 是门牌（ASCII 仪器铭文，非本地化文案）
local function shell(code)
  local c = U.canvas(80, 25)
  -- 外框
  U.chline(c, 0, 0, 80, "-")
  U.chline(c, 0, 24, 80, "-")
  U.cput(c, 0, 0, "+") U.cput(c, 79, 0, "+")
  U.cput(c, 0, 24, "+") U.cput(c, 79, 24, "+")
  U.cvline(c, 0, 1, 23, "|")
  U.cvline(c, 79, 1, 23, "|")
  -- 顶灯：四段冷光带 + 光晕下溢
  for _, x in ipairs({ 5, 25, 49, 69 }) do
    U.chline(c, x, 1, 7, "=")
    U.cput(c, x + 3, 2, "~")
  end
  -- 门牌（右上，等程序画房间名时不会撞：它在第 1 行、靠右）
  local sign = code
  local x = 78 - #sign
  for i = 1, #sign do U.cput(c, x + i - 1, 1, sign:sub(i, i)) end
  -- 墙板缝（左右各两条纵缝）
  for y = 3, 20, 6 do
    U.cput(c, 2, y, "|") U.cput(c, 77, y, "|")
  end
  -- 地板：一条踢脚线 + 网格
  U.chline(c, 1, 22, 78, "'")
  for x = 2, 76, 3 do U.cput(c, 23, x, ":") end
  return c
end

-- 画完壳后：贴道具 / 再统一变成块
local function finish(id, c, extra_colors, note)
  return U.canvas_block(id, c, merge(U.ascii_ink(), {
    ["="] = "ice", ["~"] = "deep", ["o"] = "ice", ["O"] = "body",
    ["#"] = "white", ["*"] = "body", ["'"] = "panel", [":"] = "panel",
    ["!"] = "alert", ["?"] = "warn", ["@"] = "warm", ["%"] = "ghost",
    ["&"] = "glitch", ["|"] = "line", ["-"] = "line",
  }, extra_colors), { note = note })
end

local ROOMS = {}

-- ---------------------------------------------------------------- cryo
local function room_cryo(mode)
  local c = shell("CRYO-03")
  -- 三个冷冻舱：竖槽 + 观察窗 + 霜
  for i = 0, 2 do
    local x = 8 + i * 22
    U.cstamp(c, x, 4, [==[
,------,
|      |
| ,--, |
| |@@| |
| '--' |
|      |
|      |
'------'
]==])
    if mode == "open" then
      -- 舱盖开启：窗变成空槽，霜退到边缘
      U.cstamp(c, x + 3, 7, [==[
,----,
|    |
|    |
'----'
]==])
      U.cstamp(c, x + 1, 12, "/ / /")
    else
      U.cstamp(c, x + 3, 7, [==[
,----,
| ~~ |
| ~  |
'----'
]==])
      U.cstamp(c, x + 1, 12, "%% %")
    end
  end
  -- 右侧状态板
  U.cstamp(c, 56, 15, [==[
+------------------+
| O2 61  PWR 38    |
| VIT OK  T-07:12  |
+------------------+
]==])
  return finish("room.cryo" .. (mode == "open" and ".open" or ""), c, nil,
    mode == "open" and "80x25 休眠舱（舱盖已开、霜退）" or "80x25 休眠舱：三具冷冻舱与状态板")
end

-- ---------------------------------------------------------------- med
local function room_med(mode)
  local c = shell("MED-B")
  for i = 0, 1 do
    local y = 6 + i * 7
    U.cstamp(c, 6, y, [==[
,-----------,
|           |
+-----------+===,
|###########|   |
+-----------+---+
]==])
    U.cstamp(c, 20, y - 2, "|")
    U.cstamp(c, 20, y - 1, "v")
  end
  -- 药柜 + 十字
  U.cstamp(c, 58, 5, [==[
+--------+
|   ++   |
|  +##+  |
|   ++   |
|        |
|  ====  |
|  ====  |
+--------+
]==])
  -- 监护仪
  U.cstamp(c, 42, 4, [==[
,-.
| |
'-'
]==])
  U.cstamp(c, 40, 7, [==[
+----------+
| VIT --   |
|          |
| ~~~-~~~- |
+----------+
]==])
  if mode == "body" then
    -- 遗体：盖着保温毯的轮廓停在靠里的台上
    U.cstamp(c, 9, 8, [==[
,----------,
|  ,---,   |
| (     )  |
|  '~~~'   |
| ~~~~~~~  |
'----------'
]==])
  end
  return finish("room.med" .. (mode == "body" and ".body" or ""), c, nil,
    mode == "body" and "80x25 医疗舱（台上有盖着保温毯的遗体）" or "80x25 医疗舱：两张台、药柜、监护仪")
end

-- ---------------------------------------------------------------- hub
local function room_hub(mode)
  local c = shell("HUB-0")
  -- 环形地面标记 + 四条通道口
  local cx, cy = 40, 12
  for deg = 0, 359, 6 do
    local a = math.rad(deg)
    local x = math.floor(cx + 22 * math.cos(a) + 0.5)
    local y = math.floor(cy + 7 * math.sin(a) + 0.5)
    U.cput(c, x, y, "-")
  end
  U.cstamp(c, 14, 10, [==[
,----,
|    |
|    |
'----'
]==])
  U.cstamp(c, 62, 10, [==[
,----,
|    |
|    |
'----'
]==])
  U.cstamp(c, 37, 3, [==[
,----,
|    |
'----'
]==])
  U.cstamp(c, 37, 19, [==[
,----,
|    |
'----'
]==])
  -- 中央总控台
  U.cstamp(c, 33, 10, [==[
+----------+
|  HUB-0   |
+----------+
]==])
  if mode == "alert" then
    U.cstamp(c, 30, 2, "!/!  ALERT  !/!")
  end
  return finish("room.hub" .. (mode == "alert" and ".alert" or ""), c, nil,
    mode == "alert" and "80x25 中央环廊（告警态）" or "80x25 中央环廊：环形地面标 + 四向通道 + 总控台")
end

-- ---------------------------------------------------------------- galley
local function room_galley(mode)
  local c = shell("HAB-1")
  -- 藻床制氧管
  for i = 0, 2 do
    local x = 8 + i * 13
    U.cstamp(c, x, 4, [==[
.-----.
| === |
| === |
| === |
| === |
| ..... |
'-----'
]==])
  end
  -- 餐桌 + 杯
  U.cstamp(c, 32, 15, [==[
,----------------,
|  o             |
|                |
'----------------'
]==])
  U.cstamp(c, 52, 13, [==[
+--------+
|  o     |
|        |
+--------+
]==])
  -- 壁挂私人录音机
  U.cstamp(c, 70, 5, [==[
+---+
| > |
+---+
]==])
  return finish("room.galley", c, nil, "80x25 生活舱：藻床制氧管 + 餐桌 + 录音机")
end

-- ---------------------------------------------------------------- maint
local function room_maint(mode)
  local c = shell("MAINT-2")
  -- 顶部管线
  for x = 3, 76 do U.cput(c, x, 3, (x % 4 == 0) and "+" or "=") end
  for x = 3, 76 do U.cput(c, x, 4, (x % 4 == 2) and "o" or "~") end
  -- 竖梯
  for y = 5, 20 do U.chline(c, 12, y, 6, "-") end
  U.cvline(c, 11, 5, 16, "|")
  U.cvline(c, 18, 5, 16, "|")
  -- 检修舱门 + 抓痕
  U.cstamp(c, 56, 8, [==[
,--------,
|        |
|   /\   |
|  /  \  |
|        |
'--------'
]==])
  U.cstamp(c, 30, 16, "/ / / /")
  U.cstamp(c, 40, 18, "//  //")
  return finish("room.maint", c, nil, "80x25 维护隧道：管线、竖梯、检修门与抓痕")
end

-- ---------------------------------------------------------------- reactor
local function room_reactor(mode)
  local c = shell("RX-4")
  -- 中央反应堆柱
  U.cstamp(c, 30, 4, [==[
,--------------,
|::::::::::::::|
|==============|
|##############|
|==============|
|::::::::::::::|
|==============|
|##############|
|==============|
|::::::::::::::|
'--------------'
]==])
  -- 两侧配电线
  for y = 6, 19 do
    U.cput(c, 24, y, (y % 3 == 0) and "o" or "|")
    U.cput(c, 55, y, (y % 3 == 1) and "o" or "|")
  end
  -- 仪表排
  U.cstamp(c, 62, 6, [==[
+------+
| ? !  |
| O  O |
+------+
]==])
  U.cstamp(c, 8, 6, [==[
+------+
| O  O |
| ?  ? |
+------+
]==])
  if mode == "lit" then
    U.cstamp(c, 36, 9, "  ##  ")
    U.cstamp(c, 35, 10, " ##### ")
    U.cstamp(c, 36, 11, "  ##  ")
  end
  return finish("room.reactor" .. (mode == "lit" and ".lit" or ""), c, nil,
    mode == "lit" and "80x25 反应堆（已通电，核心亮起）" or "80x25 反应堆：配电柱与仪表（默认偏暗）")
end

-- ---------------------------------------------------------------- obs
local function room_obs(mode)
  local c = shell("OBS-2")
  -- 大面积观测窗：外部深空 + 远处吸积盘
  U.cstamp(c, 6, 3, [==[
,---------------------------------------------------,
|  *        '          *        ,        *          |
|       *          ,        *        *           '  |
|   '        *          *        *        *          |
|        ,        ,------------------,          *    |
|  *        *    /     OB-1           \        '    |
|       *      |        o              |    *       |
|   '           \       '              /        ,    |
|        *        '-------------------'      *       |
|  *        *          *        ,        *           |
|       '        *          *        *          *   |
'---------------------------------------------------'
]==])
  -- 望远镜基座（前景）
  U.cstamp(c, 30, 17, [==[
,--------,
|   ||   |
|   ||   |
|  /  \  |
'--------'
]==])
  if mode == "flare" then
    -- 耀斑：窗口外多出一圈亮弧
    U.cstamp(c, 12, 6, [==[
    ,-.
  ,'   '.
 /  ***  \
 '.,   ,'
]==])
  end
  return finish("room.obs" .. (mode == "flare" and ".flare" or ""), c, { ["*"] = "body" },
    mode == "flare" and "80x25 观测甲板（窗外正在耀斑）" or "80x25 观测甲板：观测窗 + 望远镜基座")
end

-- ---------------------------------------------------------------- bridge
local function room_bridge(mode)
  local c = shell("BRIDGE")
  -- 前窗：星空
  U.cstamp(c, 8, 3, [==[
,-----------------------------------------------------------,
|   *        '          *        ,        *         '        |
|        *          *        *        *        *             |
|   '        *          ,        *        *        *         |
|        *          *        *        *        *        *    |
'-----------------------------------------------------------'
]==])
  -- 左右控制台
  U.cstamp(c, 4, 13, [==[
,--------------,
| [] [] [] []  |
| [] [] [] []  |
'--------------'
]==])
  U.cstamp(c, 56, 13, [==[
,--------------,
| [] [] [] []  |
| [] [] [] []  |
'--------------'
]==])
  -- 指挥椅
  U.cstamp(c, 34, 15, [==[
,--------,
|        |
|        |
'--------'
]==])
  if mode == "contact" then
    U.cstamp(c, 24, 4, "  << RAVEN LINK >>  ")
  end
  return finish("room.bridge" .. (mode == "contact" and ".contact" or ""), c,
    { ["*"] = "body" }, mode == "contact" and "80x25 舰桥（渡鸦号接通）" or "80x25 舰桥：前窗 + 控制台 + 指挥椅")
end

-- ---------------------------------------------------------------- array
local function room_array(mode)
  local c = shell("ARRAY-B")
  -- 阵列碟（透过窗看到的大结构）
  U.cstamp(c, 10, 3, [==[
,--------------------------------------------,
|      ,--------,                            |
|     /          \        *        '        |
|    |    ,--,    |      *        *         |
|    |    '--'    |           *             |
|     \          /                          |
|      '--------'                            |
|        ||                                  |
|        ||                                  |
'--------------------------------------------'
]==])
  -- 解调台 + 波形
  U.cstamp(c, 16, 15, [==[
+----------------------------------+
| :::: :::: :::: :::: ::::          |
|    ,---,   ,---,   ,---,           |
| ~~'     '~~'     '~~'     '~~      |
|                                    |
+----------------------------------+
]==])
  if mode == "locked" then
    U.cstamp(c, 50, 6, "SIGNAL LOCK")
    U.cstamp(c, 50, 7, "===========")
  end
  return finish("room.array" .. (mode == "locked" and ".locked" or ""), c, nil,
    mode == "locked" and "80x25 通信阵列（信号锁定）" or "80x25 通信阵列：碟形结构与解调台")
end

-- ---------------------------------------------------------------- null
local function room_null(mode)
  local c = shell("NULL-0")
  -- 密封圆门
  U.cstamp(c, 26, 4, [==[
,------------------,
|  ,------------,  |
| /              \ |
| |    ,----,     | |
| |   /      \    | |
| |  |        |   | |
| |   \      /    | |
| |    '----'     | |
| \              / |
|  '------------'  |
'------------------'
]==])
  -- 门禁槽 + 结霜 + 杂散线缆
  U.cstamp(c, 33, 12, "[  ##  ]")
  U.cstamp(c, 10, 6, "%% %")
  U.cstamp(c, 62, 6, "% %%")
  U.cstamp(c, 8, 18, "~~~~~~~~~~~~")
  U.cstamp(c, 52, 18, "~~~~~~~~~~")
  if mode == "open" then
    U.cstamp(c, 34, 10, [==[
|    |
| ~  |
|    |
]==])
  end
  return finish("room.null" .. (mode == "open" and ".open" or ""), c, nil,
    mode == "open" and "80x25 零号观测室（门已开启）" or "80x25 零号观测室：密封门、门禁槽、结霜")
end

-- ---------------------------------------------------------------- pod
local function room_pod(mode)
  local c = shell("POD-1")
  -- 吊舱与挂架
  U.cstamp(c, 28, 4, [==[
,--------,
|  ,---, |
|  |   | |
|  '---' |
'--------'
]==])
  for y = 5, 12 do U.cput(c, 27, y, "|") end
  for y = 5, 12 do U.cput(c, 38, y, "|") end
  U.cstamp(c, 24, 12, [==[
,--------------------------,
|   ____                   |
|  /    \     POD-1        |
|  \____/                  |
|  ||  ||    T-00:42       |
'--------------------------'
]==])
  if mode == "ready" then
    U.cstamp(c, 32, 16, "[READY]")
    U.cstamp(c, 40, 16, ">>")
  end
  return finish("room.pod" .. (mode == "ready" and ".ready" or ""), c, nil,
    mode == "ready" and "80x25 视界吊舱（已就绪）" or "80x25 视界吊舱：吊架、舱体与倒计时")
end

-- ---------------------------------------------------------------- airlock
local function room_airlock(mode)
  local c = shell("AIR-2")
  -- 圆形舱门
  U.cstamp(c, 24, 4, [==[
,--------------------,
|  ,--------------,  |
| /                \ |
| |    ,------,     | |
| |   |   **   |    | |
| |   |  *  *  |    | |
| |   |   **   |    | |
| |    '------'     | |
| \                / |
|  '--------------'  |
'--------------------'
]==])
  -- 压力表 + 服挂钩
  U.cstamp(c, 60, 5, [==[
,------,
| 0.0  |
|  P   |
'------'
]==])
  U.cstamp(c, 6, 5, [==[
+----+
| || |
| || |
| || |
+----+
]==])
  U.cstamp(c, 6, 12, [==[
+----+
| || |
| || |
| || |
+----+
]==])
  if mode == "raven" then
    U.cstamp(c, 34, 8, "  <>  ")
    U.cstamp(c, 32, 9, " /==\\ ")
    U.cstamp(c, 33, 10, "  <>  ")
  end
  return finish("room.airlock" .. (mode == "raven" and ".raven" or ""), c, nil,
    mode == "raven" and "80x25 气闸（渡鸦号对接中）" or "80x25 气闸：圆形舱门、压力表、舱外服挂钩")
end

-- ---------------------------------------------------------------- 注册
local BUILDERS = {
  cryo = { nil, "open" }, med = { nil, "body" }, hub = { nil, "alert" },
  galley = { nil }, maint = { nil }, reactor = { nil, "lit" },
  obs = { nil, "flare" }, bridge = { nil, "contact" }, array = { nil, "locked" },
  null = { nil, "open" }, pod = { nil, "ready" }, airlock = { nil, "raven" },
}
local FN = {
  cryo = room_cryo, med = room_med, hub = room_hub, galley = room_galley,
  maint = room_maint, reactor = room_reactor, obs = room_obs, bridge = room_bridge,
  array = room_array, null = room_null, pod = room_pod, airlock = room_airlock,
}
local ORDER = { "cryo", "med", "hub", "galley", "maint", "reactor",
                "obs", "bridge", "array", "null", "pod", "airlock" }
for _, id in ipairs(ORDER) do
  local modes = BUILDERS[id]
  ROOMS[id] = FN[id](nil)
  for i = 2, #modes do ROOMS[id .. "." .. modes[i]] = FN[id](modes[i]) end
end

-- 扁平索引
local blocks = {}
for id, block in pairs(ROOMS) do blocks["room." .. id] = block end

-- 同时暴露直接键（Art.rooms.obs）与 rooms 表（Art.rooms.rooms["obs"]），程序两种写法都能用
local R = {}
for id, block in pairs(ROOMS) do R[id] = block end
R.rooms = ROOMS
R.order = ORDER
R.blocks = blocks
return R
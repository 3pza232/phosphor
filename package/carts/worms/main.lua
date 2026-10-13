-- main.lua —— 总装配：模式菜单 + 两队虫子 + 瞄准发射 + 相机 + 回合流转 + AI
--
-- 分工（见 DESIGN.md 第 9 节）：玩法判断在各自模块里，这里只做三件事——
-- 把输入翻成"意图"、把模块串起来、把状态画出来。
-- 坐标一律是**子格**（1 字符格 = 2x2 子格），只有绘制前沿才换算成字符格。
--
-- 操作（对局中，按 K 会在画面中央弹出完整键位表）：
--   ←→ 走 / 蓄力时调力度      ↑↓ 调角度（按住可连调，最小 -60°）
--   A  进出蓄力状态（蓄力时走不动，再按一次退出、力度留着）
--   空格 按当前力度发射        X 下一件武器 / Z 上一件
--   B 跳跃                    , . 镜头左右平移（可看到视野外的敌人）
--   ' / 镜头上下平移（可看到地下的深处）

local Terrain = require("terrain")
local Camera = require("camera")
local Physics = require("physics")
local Worms = require("worms")
local Weapons = require("weapons")
local Turn = require("turn")
local AI = require("ai")
local Hud = require("hud")
local Panel = require("panel")
local Music = require("music")
local Weather = require("weather")
local Supply = require("supply")

-- 视口尺寸（字符格）。下面的默认值只在 refresh_view 取值之前用一下，
-- 真正生效的值来自 phos.screen.playfield()——**不能写死 80x45**：
-- 声明 22 格侧栏后内容区只有 58 格宽，画到 58 列之后的像素会被主机裁掉，
-- 世界右侧那一截就永远看不见（"最右边的敌人不见了"就是这么来的）
local VIEW_CW, VIEW_CH = 80, 45

-- 各层的绘制区域（层在 init 里建）。区域随**可玩区**重建：展开/收起侧栏会改宽度，
-- 区域不跟着改就会把右半屏裁掉。浮窗需要时自己现建一块
local r_base, r_fx, r_aim, r_actors, r_weather, r_hud
local function refresh_regions()
	local _, _, pw, ph_ = phos.screen.playfield()
	if not (pw and pw > 8 and ph_ and ph_ > 8) then
		return
	end
	-- 底层也走区域：于是所有绘制函数都拿到"一块画布"，
	-- 内部统一用冒号调用（phos.screen 的方法是普通函数，区域的方法是方法，包一层就统一了）
	if not r_base then
		local cw, ch = phos.screen.size()
		r_base = phos.ui.region(0, 0, cw, ch)
	end
	r_fx = phos.ui.region(0, 0, pw, ph_, { layer = "fx" })
	r_aim = phos.ui.region(0, 0, pw, ph_, { layer = "aim" })
	r_actors = phos.ui.region(0, 0, pw, ph_, { layer = "actors" })
	r_weather = phos.ui.region(0, 0, pw, ph_, { layer = "weather" })
	r_hud = phos.ui.region(0, 0, pw, ph_, { layer = "hud" })
end
local BYTE_ONE = string.byte("1")
local HIT_R2 = Worms.HIT_RADIUS * Worms.HIT_RADIUS
local DEFAULT_POWER = 0.75 -- 开局力度：满力度也不是无敌，七成半正好上手
local ANGLE_MIN, ANGLE_MAX = -60, 180
-- 瞄准线的采样：AIM_STEP_SUB 子格走一步（正好 1 字符格）；
-- 前 AIM_NEAR_SUB 子格算"近身段"，逐格点，让炮口朝向看得准
local AIM_STEP_SUB, AIM_NEAR_SUB = 2, 24

-- 瞄准手感：**点一下走一格，按住才加速**。点按负责精准、长按负责跨度，两者共用一个键。
-- 基准速率刻意压低、RAMP_T 拉长：一次"轻按"（约 0.1~0.2 秒）只该动 1~2 度 / 1~2%，
-- 要大幅度就按住等它加速到位——否则微调会被按住的几帧推过头
local TAP_POWER = 0.01 -- 力度：点一下 1%
local POWER_RATE, POWER_RATE_MAX = 0.05, 0.45
local TAP_ANGLE = 1 -- 角度：点一下 1°
local ANGLE_RATE, ANGLE_RATE_MAX = 3, 32
local RAMP_T = 1.3 -- 从"慢"加到"快"所用时间（秒）

-- 长按加速：t 秒内从 base 线性升到 top。单位随调用处（力度/秒、度/秒、血/秒）
local function accel(t, base, top)
	return base + (top - base) * math.min(1, t / RAMP_T)
end
local PANEL_W = 22 -- manifest 里声明的侧栏宽度（菜单/键位浮板时临时收起）

-- 调色板在 init 里建：卡带加载时 phos 还没装配完，模块顶层碰它不稳
local COL = {}
local function build_palette()
	COL = {
		top = phos.color.rgb(52, 132, 72), -- 地表：压暗过的绿，比纯绿耐看
		water = phos.color.rgb(26, 66, 130),
		spark = phos.color.rgb(255, 232, 150),
		smoke = phos.color.rgb(96, 96, 104),
		-- 「浮层底板」：M 地图 / K 键位表用它盖住世界、自成一块面板。
		-- 取色板的 black（随主题）：浅色主题下底板变浅、字（white）变深墨，一起翻
		plate = phos.color.black,
	}
	-- 天色、云、星与降水都归 weather.lua：它们由**游戏内时钟**推出来
end

local terrain, camera, worms, turn
local projectiles, floats, fx, fires
local weather, supply -- 时间/天气（weather.lua）与空投补给（supply.lua）
local death_queue = {} -- 待处理的阵亡爆炸：排队而不是在伤害函数里递归（见 update）
local death_blasts = 0 -- 已经结算过几次阵亡爆炸（观察口用）
local supplies_taken, supply_last = 0, "-" -- 补给被领了几次 / 最近一次是谁领的什么
local last_round = 0 -- 上一帧的回合数：天气与补给的推进钩子
local burst = nil -- 点射队列（机枪）：每 burst 秒出一发，全打完才算这一炮结束
local strikes = {} -- 天基炮：等待中的落点与正在释放的光柱
local active = {} -- active[team] = 当前操作的虫子
local captains = {} -- 每队队长（human + ally_ai 时唯一还归人操作的那只），开局定死，见 worm_is_human
local aim_power, charge_mode, switch_delay, ai_delay, winner
local pass_turn -- 跳过本回合（不发射就换手）：人用 N，AI 在被埋且没有划算的一炮时也用（定义见回合流转段）
local weapon_index, ai_plan
local ai_decided, ai_walk_t, ai_walk_dir = false, 0, nil -- AI 是否已决定走位 / 还要走多久 / 往哪走（捡补给用）
local ai_walk_from_x, ai_walk_total = 0, 0 -- 本次走位的起点 x 与总时长（判"是不是撞了死胡同"用）
local ai_reason, ai_run_away = nil, false -- 走位理由（观察口用）/ 是否在往后撤
local ai_repositioned = false -- 本回合是否已经为"够不着"换过一次位置
local ai_friendly_tried = false -- 本回合是否已为"避免误伤队友"挪过一次位
local ai_last = "-" -- 上一次 AI 的决策摘要（观察口用）
local cam = { x = 0, y = 0, hold = 0, focus = nil, pan = 0, pan_y = 0 }

-- 镜头状态的**唯一构造点**：开局落位。字段只在这里列一次——
-- 分两处各写一份的话，加字段就会漏掉一处，update_camera 立刻拿到 nil
local function reset_cam(wx, wy)
	cam.x, cam.y = wx, wy
	cam.hold, cam.focus = 0, nil
	cam.pan, cam.pan_y = 0, 0
end

-- 平移偏移归零（换手时用）：它是**相对当前目标**的偏移，不跨回合保留
local function reset_pan()
	cam.pan, cam.pan_y = 0, 0
end
local strike_dbg = nil -- 上一次天基炮的落点与开火时的地表高度（观察口用）
local tp_info = {} -- 上一次传送搜索的实况（观察口用，见 fire_teleport）
local laser_dbg = {} -- 光束每帧的位置与"离最近的敌虫多远"（观察口用）

local function spend_ammo(worm, weapon)
	if not worm.ammo then
		return
	end
	local n = worm.ammo[weapon.id]
	if n == nil or n < 0 then
		return
	end
	worm.ammo[weapon.id] = math.max(0, n - 1)
end
local flash = 0 -- 闪烁计时（当前虫子的标记用它，不用主机时间）
local screen = "menu" -- menu / play
local help_open = false
local map_open = false -- M：地图总览（不暂停）
-- 模式与队伍模型。红队 = [1]、蓝队 = [2]，颜色、UI、判定全按队来。
-- `mode` 只决定"菜单怎么往这张表里填"：PVE=红队人+蓝队AI；PVP=两队都人。
--   human   —— 这队是否有人操作（PVE 的蓝队 = false）
--   ally_ai —— 队友（非队长）是否交给 AI（沿用原有"队友交给 AI"，现在每队各有）
local mode = "pve" -- pve / pvp（lan 见后续阶段）
local teams = {
	[1] = { count = 4, human = true, ally_ai = false },  -- 红队
	[2] = { count = 4, human = false, ally_ai = false }, -- 蓝队
}
local LINEUP = { [1] = "red", [2] = "blue" } -- 队伍名的本地化 key（红/蓝）
local lan = nil -- 局域网大厅状态（定义见文件后部；这里先声明，init/菜单/主循环都要用）
local lan_pause = false -- 联机对局中的"菜单"浮层：非暂停（游戏照常走），只是遮住输入
local lan_pause_sel = 1
-- 红队是哪一边（1 左 / 2 右）：PVE/PVP 恒 1；联机开局随机左右
local red_side = 1

-- 联机对局（P3）：输入中继锁步。见 DESIGN.md §13.5。
--   frame  = 已推进的逻辑帧号（两端一致；同一帧号 ⇒ 同一局面）
--   active = 处于"观看远端操作"状态：本帧输入来自远端快照，而非本机键盘
-- 未联机（PVE/PVP）时 active 恒 false，in_* 直接透传 phos.input —— 对局逻辑完全不变
local NET_KEYS = { "left", "right", "up", "down", "a", "space", "b", "x", "z", "n" }
-- 输入延迟（帧）：本帧采到的按键按 frame+延迟 广播；模拟第 frame 帧时用的正是"延迟之前发出、
-- 现在早已到达"的那份。等包因此几乎从不落空，逻辑帧不会因等对端输入而丢拍。
-- 代价是固定多几帧操作延迟（本作无手感影响）。
local NET_DELAY = 4
local netframe = { active = false, down = {}, prev = {}, dur = {} }
local mnet = nil -- 联机对局状态：{ frame, remote = { [frame] = downset } }

local function in_down(k)
	if netframe.active then return netframe.down[k] == true end
	return phos.input.down(k)
end
local function in_pressed(k)
	if netframe.active then return netframe.down[k] == true and netframe.prev[k] ~= true end
	return phos.input.pressed(k)
end
local function in_released(k)
	if netframe.active then return netframe.down[k] ~= true and netframe.prev[k] == true end
	return phos.input.released(k)
end
local function in_duration(k)
	if netframe.active then return (netframe.dur[k] or 0) / 60 end
	return phos.input.duration(k)
end
-- 难度档位：顺序即菜单里左右键的顺序，diff 存的是下标
local DIFFS = { "easy", "normal", "hard" }
-- 地图宽窄：宽度相对标准的倍率，顺序同样是菜单里左右键的顺序；
-- MAP_KEYS 只用来取本地化名字（小 / 中 / 大）
local MAPS = { 0.5, 1, 2 }
local MAP_KEYS = { "small", "normal", "large" }
-- ─── 界面文案 ────────────────────────────────────────────────────────────
-- 所有写给玩家看的句子都从这里取：主机语言是英文时，写死的中文会原样显示。
-- 排版一律用 phos.text.width 量宽度 —— 汉字 2 列、字母 1 列，
-- 给中文写死的列号在英文下必然错位
local Text = {
	zh = {
		subtitle = "回合制炮击 · 用有限弹药把对面轰进海里",
		menu_title = "选择模式",
		mode = { pve = "PVE 人机对战", pvp = "PVP 同机对战", lan = "局域网联机" },
		label = { mode = "模式", red = "红队人数", blue = "蓝队人数",
		          red_ai = "红队队友 AI", blue_ai = "蓝队队友 AI",
		          hp = "生命值", diff = "难度", map = "地图宽窄" },
		start = "开始游戏",
		menu_hint = "↑↓ 选择   ←→ 调整   回车 确定",
		yes = "是", no = "否",
		diff = { easy = "简单", normal = "普通", hard = "困难" },
		map = { small = "小", normal = "中", large = "大" },
		help_title = "键位说明（K 关闭）",
		help_head = "对局中",
		help = {
			{ "←→", "走路；蓄力时调力度" },
			{ "↑↓", "调角度（可到 -60° 朝下）" },
			{ "A", "进出蓄力状态（力度保留）" },
			{ "空格", "按当前力度发射" },
			{ "N", "跳过本回合（不开炮）" },
			{ "X Z", "下一件 / 上一件武器" },
			{ "B", "跳跃" },
			{ ", .", "镜头左右平移" },
			{ "' /", "镜头上下平移" },
			{ "K", "开关这张表（暂停）" },
			{ "回车", "结算后回菜单" },
			{ "Esc", "返回卡带架" },
		},
		map_title = "地图总览",
		map_info = "回合 %d    风 %s    轮到 %s    空中 %d",
		side = { "红队", "蓝队" },
		flying = "弹药飞行中",
		win = { "红队胜利", "蓝队胜利" },
		win_hint = "按 ENTER 回菜单",
		no_ammo = "没弹药了",
		no_tp = "无法传送",
		drowned = "落海",
		raised = "地形 +%d",
		orbital = "天基炮!",
		burning = "燃烧",
		death = "阵亡爆炸",
		got = "%s x%d",
		-- 局域网大厅（见 DESIGN.md §13）
		lan = {
			nick = "昵称", create = "创建房间", search = "搜索房间", overview = "房间总览",
			nick_empty = "先取个名字才能联机",
			create_title = "创建房间", red_cap = "红队上限", blue_cap = "蓝队上限",
			search_title = "搜索房间", code_prompt = "房间码",
			overview_title = "房间总览", no_room = "没有找到房间", searching = "搜索中…",
			room_title = "房间", red = "红队", blue = "蓝队", you = "（你）",
			start = "开始游戏", start_hint = "",
			disband = "退格 解散", leave = "退格 退出房间", leave_team = "退格 退出队伍",
			join_hint = "← → 选队   回车 加入", waiting = "等待房主开始…",
			joined = "已加入 %s 队",
			enter = "回车 搜索", refresh = "R 刷新", players = "人",
			host_tag = "房主", in_game = "房间游戏中，无法加入", wait_teams = "等待所有玩家入队",
			busy = "游戏中",
			paused_title = "菜单", resume = "继续游戏", leave_room = "退出房间",
			paused_hint = "↑↓ 选择   回车 确定",
		},
	},
	en = {
		subtitle = "Turn-based artillery: shell the other team into the sea",
		menu_title = "MATCH SETUP",
		mode = { pve = "PVE vs CPU", pvp = "PVP hot-seat", lan = "LAN play" },
		label = { mode = "MODE", red = "RED SQUAD", blue = "BLUE SQUAD",
		          red_ai = "RED ALLY AI", blue_ai = "BLUE ALLY AI",
		          hp = "HP", diff = "DIFFICULTY", map = "MAP WIDTH" },
		start = "START MATCH",
		menu_hint = "↑↓ SELECT   ←→ CHANGE   ENTER OK",
		yes = "YES", no = "NO",
		diff = { easy = "EASY", normal = "NORMAL", hard = "HARD" },
		map = { small = "SMALL", normal = "NORMAL", large = "LARGE" },
		help_title = "CONTROLS (K closes)",
		help_head = "IN MATCH",
		help = {
			{ "←→", "walk; adjust power while charging" },
			{ "↑↓", "aim angle (down to -60°)" },
			{ "A", "enter / leave charging (power kept)" },
			{ "SPACE", "fire with current power" },
			{ "N", "skip your shot (pass the turn)" },
			{ "X Z", "next / previous weapon" },
			{ "B", "jump" },
			{ ", .", "pan camera left / right" },
			{ "' /", "pan camera up / down" },
			{ "K", "toggle this panel (pauses)" },
			{ "ENTER", "back to menu once settled" },
			{ "Esc", "eject to cartridge shelf" },
		},
		map_title = "MAP OVERVIEW",
		map_info = "TURN %d    WIND %s    %s    AIRBORNE %d",
		side = { "RED", "BLUE" },
		flying = "SHELL IN FLIGHT",
		win = { "RED WINS", "BLUE WINS" },
		win_hint = "PRESS ENTER FOR MENU",
		no_ammo = "NO AMMO",
		no_tp = "CANNOT TELEPORT",
		drowned = "DROWNED",
		raised = "TERRAIN +%d",
		orbital = "ORBITAL!",
		burning = "BURNING",
		death = "KIA BLAST",
		got = "%s x%d",
		lan = {
			nick = "NAME", create = "CREATE ROOM", search = "FIND ROOM", overview = "ROOMS",
			nick_empty = "Pick a name first",
			create_title = "CREATE ROOM", red_cap = "RED CAP", blue_cap = "BLUE CAP",
			search_title = "FIND ROOM", code_prompt = "ROOM CODE",
			overview_title = "ROOMS", no_room = "No rooms found", searching = "searching…",
			room_title = "ROOM", red = "RED", blue = "BLUE", you = "(you)",
			start = "START", start_hint = "",
			disband = "BACKSPACE disband", leave = "BACKSPACE leave", leave_team = "BACKSPACE leave team",
			join_hint = "← → pick team   ENTER join", waiting = "Waiting for host…",
			joined = "JOINED %s",
			enter = "ENTER search", refresh = "R refresh", players = "p",
			host_tag = "host", in_game = "Room in progress, cannot join", wait_teams = "waiting for all players",
			busy = "in game",
			paused_title = "MENU", resume = "RESUME", leave_room = "LEAVE ROOM",
			paused_hint = "↑↓ select   ENTER ok",
		},
	},
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end


-- 生命值那一行：上下限与步长。长按的速率是"每秒多少点"，最后统一取整成 10 的倍数
local HP_MIN, HP_MAX, HP_STEP = 10, 800, 10
local HP_RATE, HP_RATE_MAX = 30, 240

-- 菜单只是"往队伍模型里填值"的一张草稿：t1=红队、t2=蓝队，各带人数与"队友交给 AI"。
-- 真正生效的模型是 teams（start_match 时把这里的选择拷进去）
local menu = { row = 1, mode = "pve",
               t1 = { count = 4, ally_ai = false },
               t2 = { count = 4, ally_ai = false },
               map = 2, diff = 2, hp = 100 }
local menu_flash = 0
local hp_frac = 0 -- 菜单里按住 ←→ 时"不足一步的余量"（按住多久由 phos.input.duration 给）

-- 血量只能落在 10 的倍数上：点按、长按加速、上下限夹取全走这一个入口
local function set_menu_hp(v)
	menu.hp = math.max(HP_MIN, math.min(HP_MAX, v - v % HP_STEP))
end

local function pick_active(team, after)
	active[team] = worms:next_of_team(team, after)
	return active[team]
end

-- 菜单态下这局还没开始（turn/worms 都是 nil），所以这里必须容错：
-- 观察口与"是不是该我操作"都会在开局前问一遍，抛异常会让 agent 什么都看不到
local function current_worm()
	return turn and active[turn.team] or nil
end
local function selected_weapon()
	return Weapons.LIST[weapon_index]
end

-- 谁在操作这只虫：看它所属队伍的 human / ally_ai（唯一真源，见 teams）。
-- 队长**开局就定死**，不是"当前第一个活着的"：队长阵亡后全队归 AI，
-- 若拿"第一个活着的"当队长，玩家会在阵亡后接管下一只队友
local function worm_is_human(w)
	if not w or not worms then
		return false
	end
	-- 联机：只认"这只虫属于本机玩家"（owner 由开局名册分配）
	if mode == "lan" then
		return w.owner ~= nil and w.owner == phos.net.self_id()
	end
	local team = teams[w.team]
	if not team or not team.human then
		return false
	end
	if not team.ally_ai then
		return true
	end
	return w == captains[w.team]
end

local function human_turn()
	return worm_is_human(current_worm())
end

-- 队伍配色（红队 = 红系、蓝队 = 蓝系）。**当前行动队亮、其余暗**，一眼分出轮到谁。
-- HUD、侧栏、虫标、地图各画各的，但取色都从这里来，改一处全局一致
local function team_color(C, team, active)
	if team == red_side then
		return active and C.red or C.orange
	end
	return active and C.blue or C.purple
end

-- ---------- 特效 ----------

local function add_fx(x, y, r)
	local rad = math.max(2, r or 3)
	fx[#fx + 1] = { kind = "ring", x = x, y = y, r = rad, t = 0.35, life = 0.35 }
	-- 火星：炸开时朝四周飞出，受一点重力，画成亮点
	for _ = 1, 7 do
		local a = math.rad(phos.sys.random(0, 359))
		local sp = phos.sys.random(18, 52) / 10
		fx[#fx + 1] = {
			kind = "spark",
			x = x,
			y = y,
			vx = math.cos(a) * sp,
			vy = math.sin(a) * sp - 2.0,
			t = 0.5,
			life = 0.5,
		}
	end
	-- 烟：慢慢上飘、越飘越淡（用亮度变化表示"淡"，因为字只有一格）
	for _ = 1, 5 do
		fx[#fx + 1] = {
			kind = "smoke",
			x = x + phos.sys.random(-4, 4),
			y = y - phos.sys.random(0, 3),
			vx = phos.sys.random(-10, 10) / 10,
			vy = -1.6,
			t = 0.9,
			life = 0.9,
		}
	end
end

-- 伤害浮字：受击点上方冒出来。text 只在没有数字时用（落海、燃烧这类）。
-- lift 是再往上抬几格：补给的报账要停在**血条上方**，压着血条就白报了。
-- **颜色的规矩只在这里**：带伤害数字的一律红（挨打要一眼看出来），治疗与报账由调用方
-- 显式给绿；不给色又不带数字的（落海、燃烧、天基炮预告）也由调用方显式给色
local function add_float(wx, wy, damage, text, color, lift)
	if not color and damage and damage >= 1 then color = phos.color.red end
	local cx, cy = camera:cell_of(wx, wy)
	local f = { x = cx + 1, y = cy - 1 - (lift or 0), damage = damage, text = text, color = color, t = 1.2 }
	floats[#floats + 1] = f
	return f
end

-- 捡到补给：在拾取者血条上方报一账（"火箭筒 x1"），1 秒后消失。
-- 比伤害浮字短一点是刻意的：它是报账，不是打击反馈
local function on_supply_pickup(w, spec, count)
	supplies_taken = supplies_taken + 1
	supply_last = string.format("%s x%d ->队%d", spec.id, count, w.team)
	local f = add_float(w.x, w.y, 0, string.format(L().got, phos.lang.pick(spec.name), count), phos.color.green, 3)
	if f then
		f.t = 1.0
	end
	phos.audio.beep(880, 0.08, { wave = "square", sweep = 200, volume = 0.18 })
end

-- ---------- 开局与菜单 ----------

-- 视口 = 本卡带真正能画的区域（侧栏已扣掉）。init 与开局各取一次
local function refresh_view()
	local _, _, pw, ph_ = phos.screen.playfield()
	if pw and pw > 8 and ph_ and ph_ > 8 then
		VIEW_CW, VIEW_CH = pw, ph_
	end
	-- 降水与星按**屏幕格**铺：视口一变就要重新平铺（展开/收起侧栏会改视口）
	if weather then
		weather:resize(VIEW_CW, VIEW_CH)
	end
	refresh_regions()
end

function init()
	build_palette()
	-- 可调参数交给 `~` 调试台（phos.debug.number）：常挂心的数挂上，边打边调（中英双语，随界面语言切换）
	-- 顶层：虫子自己的几个数
	phos.debug.number({ zh = "虫虫生命", en = "Worm HP" }, function() return Worms.MAX_HP end,
	                  function(v) Worms.MAX_HP = v end, { min = 10, max = 500, step = 10 })
	phos.debug.number({ zh = "爬行速度", en = "Crawl speed" }, function() return Worms.WALK_SPEED end,
	                  function(v) Worms.WALK_SPEED = v end, { min = 2, max = 30, step = 0.5 })
	phos.debug.number({ zh = "跳跃力", en = "Jump power" }, function() return Worms.JUMP_VY end,
	                  function(v) Worms.JUMP_VY = v end, { min = -30, max = -3, step = 1 })
	-- 武器：一个大折叠（"武器"）下、每件武器一个小折叠。**遍历武器表、登记它真正有的字段**——
	-- 每件武器特性不同（机枪的弹丸数/连发间隔、激光的粗度/速度、治疗弹给的是治疗量、
	-- 天基炮的光柱参数……），于是将来加武器、加字段都会自动出现在面板里，不必改这里
	local FIELDS = {
		{ "damage",    "伤害",     "Damage",        0,    200,  1,    true  },
		{ "radius",    "爆炸半径", "Blast radius",  0,    12,   0.5,  false },
		{ "wind",      "受风度",   "Wind factor",   0,    2,    0.05, false },
		{ "ammo",      "弹药",     "Ammo",          -1,   20,   1,    true  },  -- -1 = 无限
		{ "fuse",      "引信",     "Fuse",          0.5,  6,    0.1,  false },
		{ "shells",    "弹丸数",   "Pellets",       1,    20,   1,    true  },
		{ "spread",    "散射角",   "Spread",        0,    40,   0.5,  false },
		{ "burst",     "连发间隔", "Burst gap",     0.02, 0.5,  0.01, false },
		{ "supply",    "补给量",   "Supply",        1,    5,    1,    true  },
		{ "heal",      "治疗量",   "Heal",          0,    200,  5,    false },
		{ "raise",     "造地半径", "Mound radius",  1,    20,   1,    true  },
		{ "burn",      "燃烧时长", "Burn time",     0,    10,   0.5,  false },
		{ "speed",     "飞行速度", "Speed",         100,  2000, 10,   true  },
		{ "width",     "粗度",     "Width",         1,    12,   0.5,  false },
		{ "turn_rate", "转向速率", "Turn rate",     10,   180,  1,    false },
		{ "splits",    "分裂数",   "Split count",   1,    12,   1,    true  },
		{ "ai_mult",   "AI 评分倍数", "AI score mult", 1,  5,    1,    true  },
	}
	local register_field = function(owner, path, f)
		if owner[f[1]] == nil then return end  -- 这件武器没这个字段：不登记
		local opts = { group = path, min = f[4], max = f[5], step = f[6] }
		local getter = function() return owner[f[1]] end
		local setter = function(v) owner[f[1]] = v end
		if f[7] then
			phos.debug.integer({ zh = f[2], en = f[3] }, getter, setter, opts)
		else
			phos.debug.number({ zh = f[2], en = f[3] }, getter, setter, opts)
		end
	end
	local WEAPONS_GROUP = { zh = "武器", en = "WEAPONS" }
	for _, w in ipairs(Weapons.LIST) do
		local path = { WEAPONS_GROUP, w.name }
		for _, f in ipairs(FIELDS) do register_field(w, path, f) end
		if w.orbital then  -- 天基炮的光柱参数是嵌套表：再套一层小折叠
			local opath = { WEAPONS_GROUP, w.name, { zh = "光柱", en = "BEAM" } }
			register_field(w.orbital, opath, { "delay",       "标记延迟",   "Mark delay",      0,    6,   0.1,  false })
			register_field(w.orbital, opath, { "life",        "光柱时长",   "Beam life",       0.5,  8,   0.1,  false })
			register_field(w.orbital, opath, { "tick",        "结算间隔",   "Tick interval",   0.1,  2,   0.05, false })
			register_field(w.orbital, opath, { "damage",      "每次伤害",   "Damage/tick",     0,    100, 1,    true })
			register_field(w.orbital, opath, { "width",       "光柱宽度",   "Beam width",      2,    16,  1,    true })
			register_field(w.orbital, opath, { "descend",     "穿空气速度", "Air descend",     10,   300, 5,    true })
			register_field(w.orbital, opath, { "descend_dig", "入土速度",   "Dig descend",     1,    40,  1,    true })
		end
	end
	-- 分层：天空与地形照旧画**底层**（phos.screen），前景（特效/瞄准/角色/雨雪）一层、
	-- 读数与浮字一层、浮窗一层，按 z 叠上去。
	-- 层的空白格是透明的，而"保留底色"在**同一层内**照样成立（层内先铺底板再画边框，
	-- 与直接写屏同一套先后规则），所以分层与直接写屏画出来的画面一致
	-- 图层按**类别**分，不只是"前后"：世界（天空 + 地形 + 水）写底层，
	-- 其余每类各一层。同类的东西再也不会因为"谁后写"互相擦掉，
	-- 新加一块绘制也知道该往哪一层放
	phos.layer.create("fx", { z = 10 })         -- 爆炸、燃烧、光柱、弹迹
	phos.layer.create("aim", { z = 15 })        -- 瞄准线、炮口符号、力度读数
	phos.layer.create("actors", { z = 20 })     -- 虫子本体与血条
	phos.layer.create("weather", { z = 25 })    -- 雨雪、热浪、闪电
	phos.layer.create("hud", { z = 30 })        -- 顶部读数、胜负横幅
	phos.layer.create("overlay", { z = 40 })    -- 地图 / 键位表浮窗
	refresh_view()
	-- 菜单不放音乐：进卡带先静音，等真的开局（start_match）再起 BGM。
	-- 菜单是一个"让人读说明、选人数"的地方，有鼓点反而吵
	screen, menu_flash, help_open = "menu", 0, false
	menu.row = 1
	-- 昵称输入框（局域网用）：过滤、按码点退格、限长都在主机的文本缓冲里做。
	-- 缓冲跨多次编辑保留，所以"改一下名字"不必从头敲
	menu.field = phos.input.field({ filter = "printable", max = 8 })
	menu.nick_edit, menu.nick_err = false, false
	lan = nil
	phos.panel.resize(0) -- 菜单不需要侧栏：留着那条竖线会压住浮窗
end

-- 真正起一局：队伍模型与 hp/map 都已定好，这里只负责建世界。PVE / PVP / LAN 共用
local function begin_game(hp, map)
	phos.panel.resize(PANEL_W)
	refresh_view()
	phos.audio.music(Music) -- 正式开局才起 BGM（换卡时主机会自动停）
	-- 血量上限必须在造虫子**之前**设好：每只虫的初始血量取自它
	Worms.MAX_HP = hp
	terrain = Terrain.new(MAPS[map]) -- 宽度按菜单选的三档；高度与海平面不变
	camera = Camera.new(terrain.W, terrain.H, VIEW_CW * 2, VIEW_CH * 2)
	worms = Worms.new(terrain, { teams[1].count, teams[2].count })
	-- 每队队长在**这里**定死（该队第一只）：只有"人操作 + 队友交给 AI"时才用到。
	-- 不能每次现算，否则队长一死玩家就换人（见 worm_is_human）
	captains = {}
	for i = 1, 2 do
		captains[i] = teams[i].human and worms:of_team(i)[1] or nil
	end
	turn = Turn.new()
	projectiles, floats, fx, fires = {}, {}, {}, {}
	aim_power, charge_mode, weapon_index, ai_plan = DEFAULT_POWER, false, 1, nil
	switch_delay, ai_delay, winner = nil, 1.2, nil
	active = {}
	-- 每只虫的默认力度由这里给（worms.lua 不做"手感"决定）
	for _, m in ipairs(worms.list) do
		m.power = DEFAULT_POWER
	end
	-- 天气与补给：都跟着"第几回合"走（见 update 里的回合钩子），开局各建一份。
	-- 云、星、天色全在 weather 里，这里只持有一份
	weather = Weather.new(terrain)
	weather:resize(VIEW_CW, VIEW_CH)
	supply = Supply.new()
	death_queue, last_round, death_blasts = {}, turn.round, 0
	supplies_taken, supply_last = 0, "-"
	-- 阵亡爆炸：worms.lua 只报死讯，伤害与特效在这里统一处理。
	-- 排队而不是当场炸——爆炸可能再炸死人，当场递归既难懂又容易失控
	worms.on_death = function(dead)
		death_queue[#death_queue + 1] = { x = dead.x, y = dead.y }
	end
	local w = pick_active(1)
	pick_active(2)
	if w then
		reset_cam(w.x, w.y)
		camera:center(w.x, w.y)
	end
	screen = "play"
end

-- PVE / PVP：把菜单选择填进队伍模型，再起局
local function start_match()
	mode = menu.mode
	red_side = 1      -- 单机左右固定：红队恒在左
	mnet = nil        -- 非联机
	-- PVE 的蓝队永远是 AI（human=false）
	teams[1] = { count = menu.t1.count, human = true, ally_ai = menu.t1.ally_ai }
	teams[2] = {
		count = menu.t2.count,
		human = (mode == "pvp"),
		ally_ai = menu.t2.ally_ai,
	}
	begin_game(menu.hp, menu.map)
	-- 单机也把名字挂在虫身上：侧栏与顶栏一律读 w.name，联机用名册里的真名，这里用
	-- P1 / P2 / AI —— 显示层只认一个字段，不必到处判"是不是联机"
	for _, w in ipairs(worms.list) do
		if not w.name then
			w.name = (not worm_is_human(w)) and "AI" or (w.team == 1 and "P1" or "P2")
		end
	end
end

-- 局域网大厅的函数定义在文件后部（要用到 box 等）；这里先声明，供模式菜单与主循环引用
local lan_enter, menu_lan_input, lan_update, lan_draw, lan_match_over

local function clamp_count(n)
	return math.max(1, math.min(8, n))
end

-- 菜单（红/蓝队模型）。**每一行都得登记在 rows 里**，漏一行就永远选不到它（连同它后面的"开始"）。
-- 行序随模式变，第 3~5 行的含义不同：
--   PVE：1 模式  2 红队人数  3 蓝队人数  4 红队队友AI  5 难度  6 地图  7 血量  8 开始
--   PVP：1 模式  2 红队人数  3 红队队友AI  4 蓝队人数  5 蓝队队友AI  6 地图  7 血量  8 开始
local HP_ROW = 7
local function menu_input(dt)
	if menu.mode == "lan" then
		menu_lan_input(dt)
		return
	end
	local pvp = (menu.mode == "pvp")
	-- 上下移动的**视觉顺序**：PvE 面板里"红队队友 AI"（row 4）画在"蓝队人数"（row 3）之前，
	-- 所以导航顺序得是 1,2,4,3,…，照逻辑行号 1,2,3,4 走会在屏幕上跳来跳去
	local rows = pvp and { 1, 2, 3, 4, 5, 6, 7, 8 } or { 1, 2, 4, 3, 6, 7, 5, 8 }
	local function move(dir)
		local at = 1
		for i, r in ipairs(rows) do
			if r == menu.row then
				at = i
			end
		end
		at = ((at - 1 + dir) % #rows) + 1
		menu.row = rows[at]
		phos.audio.beep(420, 0.04, { wave = "square", volume = 0.14 })
	end
	if phos.input.pressed("up") then
		move(-1)
	end
	if phos.input.pressed("down") then
		move(1)
	end

	local step = 0
	if phos.input.pressed("left") then
		step = -1
	end
	if phos.input.pressed("right") then
		step = 1
	end
	if step ~= 0 then
		if menu.row == 1 then
			-- 模式三选循环：左右各自"上一个 / 下一个"（左不再是又一个"下一个"）
			local order = { "pve", "pvp", "lan" }
			local at = 1
			for i, m in ipairs(order) do if m == menu.mode then at = i end end
			menu.mode = order[((at - 1 + step) % #order) + 1]
			menu.row = 1
		elseif menu.row == 2 then
			menu.t1.count = clamp_count(menu.t1.count + step)
		elseif menu.row == 3 then
			if pvp then
				menu.t1.ally_ai = not menu.t1.ally_ai
			else
				menu.t2.count = clamp_count(menu.t2.count + step)
			end
		elseif menu.row == 4 then
			if pvp then
				menu.t2.count = clamp_count(menu.t2.count + step)
			else
				menu.t1.ally_ai = not menu.t1.ally_ai
			end
		elseif menu.row == 5 then
			if pvp then
				menu.t2.ally_ai = not menu.t2.ally_ai
			else
				menu.diff = ((menu.diff - 1 + step) % #DIFFS) + 1
			end
		elseif menu.row == 6 then
			menu.map = ((menu.map - 1 + step) % #MAPS) + 1
		elseif menu.row == 7 then
			-- 点一下 ±一步（单发点按）；长按加速见下
			set_menu_hp(menu.hp + step * HP_STEP)
		end
		phos.audio.beep(520, 0.04, { wave = "square", volume = 0.14 })
	end

	-- 生命值那一行：点一下 10 点，**按住**则越快越快（与炮弹蓄力同一套加速曲线）。
	-- 累成整步再加，所以无论按多快，血量永远是 10 的倍数
	if menu.row == HP_ROW then
		local dir = phos.input.down("left") and -1 or (phos.input.down("right") and 1 or 0)
		if dir ~= 0 and not phos.input.pressed("left") and not phos.input.pressed("right") then
			-- "按住多久"直接问主机（phos.input.duration）：不必自己攒计时，
			-- 也就不会有"松开忘了清零"那类 bug
			local held = (dir < 0) and phos.input.duration("left") or phos.input.duration("right")
			hp_frac = hp_frac + accel(held, HP_RATE, HP_RATE_MAX) * dt
			local steps = math.floor(hp_frac / HP_STEP)
			if steps > 0 then
				hp_frac = hp_frac - steps * HP_STEP
				set_menu_hp(menu.hp + dir * steps * HP_STEP)
			end
		end
	else
		hp_frac = 0
	end

	-- 回车（虚拟键 "start"）：在"开始游戏"上开局；在"队友交给 AI"行上开关。
	-- 确认键用回车而不是 A：A 是字母键，昵称输入框里它要用来打字，不该兼作确定
	if phos.input.pressed("start") then
		if menu.row == 8 then
			start_match()
		elseif (menu.row == 3 and pvp) or (menu.row == 4 and not pvp) then
			menu.t1.ally_ai = not menu.t1.ally_ai
		elseif menu.row == 5 and pvp then
			menu.t2.ally_ai = not menu.t2.ally_ai
		end
	end
end

-- ---------- 输入 → 意图 ----------

-- 换武器：只跳过**已经打光**（余弹 0）的那几件。一炮一个机会，不能浪费在
-- "选了也打不出去"的武器上；全都没得选时保持当前，让玩家看见原因
local function cycle_weapon(dir, w)
	local n = #Weapons.LIST
	for step = 1, n do
		local i = (weapon_index - 1 + dir * step) % n + 1
		local spec = Weapons.LIST[i]
		if Weapons.has_ammo(w, spec) and turn:ready(spec.id) then
			weapon_index = i
			phos.audio.beep(600, 0.04, { wave = "square", volume = 0.14 })
			return
		end
	end
end

-- 打光了就自动落回普通炮弹（无限），不然玩家会对着空武器反复按发射
local function ensure_weapon(w)
	local spec = selected_weapon()
	if spec and Weapons.has_ammo(w, spec) then
		return spec
	end
	weapon_index = 1
	return Weapons.LIST[1]
end

local function player_input(dt)
	local w = current_worm()
	if not w or not w.alive or turn.phase ~= "aim" or turn.shots_left <= 0 or winner then
		return
	end

	-- N：跳过本回合（不发射就换手）。被地形埋住又没角度 / 没治疗弹时，不必空耗整回合
	if in_pressed("n") then
		pass_turn()
		return
	end

	-- 输入一律走 in_*：本机键盘 or 远端快照（联机观看时）。见文件顶部 netframe
	-- A：进出蓄力状态。蓄力时不走路——左右键专门用来调力度条，
	-- 这样"走到位再瞄"和"微调力度"是两个不会互相打架的动作
	if in_pressed("a") then
		charge_mode = not charge_mode
		phos.audio.beep(charge_mode and 660 or 440, 0.05, { wave = "square", volume = 0.16 })
	end

	-- 左右：蓄力态调力度（点按 1%、长按加速），非蓄力态走路
	local left, right = in_down("left"), in_down("right")
	if charge_mode then
		-- 按住的那一个键已经按了多久，加速曲线就用多久（松手即 0，不必自己清零）
		local held = left and in_duration("left") or in_duration("right")
		local rate = accel(held, POWER_RATE, POWER_RATE_MAX)
		if in_pressed("left") then
			aim_power = Physics.clamp_power(aim_power - TAP_POWER)
		elseif in_pressed("right") then
			aim_power = Physics.clamp_power(aim_power + TAP_POWER)
		elseif left then
			aim_power = Physics.clamp_power(aim_power - rate * dt)
		elseif right then
			aim_power = Physics.clamp_power(aim_power + rate * dt)
		end
	else
		if left then
			worms:move(w, -1, dt)
		end
		if right then
			worms:move(w, 1, dt)
		end
	end

	-- 上下：点按 1°、长按越走越快。下限 -60° 表示"朝下打"
	local up, down = in_down("up"), in_down("down")
	local held = up and in_duration("up") or in_duration("down")
	local ad = 0
	if in_pressed("up") then
		ad = TAP_ANGLE
	elseif in_pressed("down") then
		ad = -TAP_ANGLE
	elseif up then
		ad = accel(held, ANGLE_RATE, ANGLE_RATE_MAX) * dt
	elseif down then
		ad = -accel(held, ANGLE_RATE, ANGLE_RATE_MAX) * dt
	end
	if ad ~= 0 then
		w.angle = math.max(ANGLE_MIN, math.min(ANGLE_MAX, w.angle + ad))
	end

	if in_pressed("b") then
		worms:jump(w)
	end
	if in_pressed("x") then
		cycle_weapon(1, w)
	end
	if in_pressed("z") then
		cycle_weapon(-1, w)
	end

	-- 空格：按当前力度发射
	if in_pressed("space") then
		if fire(w, ensure_weapon(w)) then
			charge_mode = false
		end
	end
	w.power = aim_power
end

-- ---------- 命中判定 ----------

-- p 是**发这枚弹的弹丸**：命中判定要跳过它自己的射手。炮口就在射手身上
-- （见 Physics.muzzle_of），不跳过的话出膛那一帧就"撞到自己"
local function probe(x, y, p)
	-- 左右出界与地面以下都算撞上；**顶部不算** —— 天空是敞开的，
	-- 打太高就让它飞出去再落回来，不该在半空被凭空引爆
	if x < 1 or x > terrain.W or y > terrain.H then
		return "out"
	end
	if y < 1 then
		return nil
	end
	if terrain:solid(math.floor(x), math.floor(y)) then
		return "terrain"
	end
	if y >= terrain.WATER_Y then
		return "water"
	end
	for _, w in ipairs(worms.list) do
		if w.alive and w ~= (p and p.shooter) then
			local dx, dy = w.x - x, w.y - y
			if dx * dx + dy * dy <= HIT_R2 then
				return "worm", w
			end
		end
	end
	return nil
end

-- ---------- 开炮 ----------

-- 当场结算的那条路（定义在下面）：先声明，fire 才能引用它
local fire_teleport

-- 第 i 枚（共 n 枚）相对瞄准线的偏角：等分铺在 weapon.spread 的总角度内。
-- 等分而不是随机：覆盖范围必须可预期，否则同样的瞄准每次结果都不同
local function spread_angle(weapon, i, n)
	if n <= 1 then
		return 0
	end
	local s = weapon.spread or 0
	return s * (i - 1) / (n - 1) - s / 2
end

-- 某一列的地表行：从地表候选处往下找第一个实心格。光柱挖地要用它，
-- 自测"到底挖下去多少"也要用它——同一个判据，两处不各写一遍
local function surface_at(x)
	local gy = 1
	while gy < terrain.WATER_Y and not terrain:solid(x, gy) do
		gy = gy + 1
	end
	return gy
end

-- 天基炮：等待期（落点标记闪烁）→ 光柱释放 3 秒（每 tick 结算一次伤害）→ 熄灭。
-- 伤害按"位置"算而不是按"人"：光柱有多宽，站在里面的都会被打到，
-- 所以它逼人离开掩体，而不是"追踪某只虫"
local function update_strikes(dt)
	for i = #strikes, 1, -1 do
		local s = strikes[i]
		local spec = s.spec
		if s.t > 0 then
			s.t = s.t - dt
			if s.t <= 0 then
				-- 点亮：镜头交给 update_camera 里的"特效优先"规则，这里只管声音。
				-- 不用倒计时抢镜头——倒计时会在光柱还没烧完时就放镜头走人
				s.age, s.next_tick = 0, 0
				phos.audio.beep(60, 0.5, { wave = "noise", volume = 0.3, release = 0.3 })
			end
		else
			s.age = s.age + dt
			-- 光柱**从世界顶端往下扫**（spec.descend 子格/秒），沿途把一切破开。
			-- 这是"天基"二字要紧的地方：柱子一瞬间贯到底的话，头顶的屋檐会被无视，
			-- 看着像隔着屋顶打人；让它真的扫下来，先破开的必然是头顶那一层
			-- 光柱的**世界列**：列数先定死（宽度 ÷ 2 格），再居中放到落点上。
			-- 写成"从 x−半宽 到 x+半宽 取整"的话，落点的子格奇偶一变列数就在 3 与 4
			-- 之间跳 —— 同一件武器，有时显得宽、有时显得窄（实测到的现象）。
			-- 挖地与判伤都只认这一对**世界子格**边界：相机是"看"的事，不参与
			local cols = math.max(1, math.floor(((spec.width or 6) + 1) / 2))
			local c0 = math.floor(s.x / 2) - math.floor((cols - 1) / 2)
			local c1 = c0 + cols - 1
			local x0, x1 = c0 * 2, c1 * 2 + 1
			s.c0, s.c1, s.x0, s.x1 = c0, c1, x0, x1

			-- 柱尖下落：穿空气快、破土慢。速度分档是刻意的 —— "从天而降"要看得见，
			-- 破土则要慢到不至一炮把山削平
			-- 判"有没有碰到土"要看**柱尖下面那一行**：柱尖自己那一行刚被它挖空，
			-- 拿它当判据的话，下一帧就以为身处空气、恢复高速 —— 等于没减速，一路钻穿地图
			local ahead = math.floor(s.tip) + 1
			local digging = false
			for x = x0, x1 do
				if terrain:solid(x, ahead) then
					digging = true
					break
				end
			end
			local speed = digging and (spec.descend_dig or 4) or (spec.descend or 90)
			local prev = s.tip
			s.tip = math.min(terrain.H, s.tip + speed * dt)
			if s.tip > prev then
				terrain:carve_rect(x0, math.floor(prev), x1, math.floor(s.tip))
			end

			s.next_tick = s.next_tick - dt
			if s.next_tick <= 0 then
				s.next_tick = spec.tick
				-- 伤害只给**光柱已经扫过**的：柱尖越过它头顶才算命中。
				-- 判据是**世界坐标**：站在那一列子格里（x0..x1）且被柱尖扫过头顶。
				-- 用相机格去判的话，这条规则会随镜头位置变化 —— "打到谁"不该取决于
				-- 玩家把镜头挪到哪，而且相机原点奇数时还会与挖出来的洞差半格
				for _, q in ipairs(worms.list) do
					if q.alive and q.x >= x0 and q.x <= x1 then
						local head = math.floor(q.y) - Worms.BODY_H
						if s.tip >= head then
							worms:damage(q, spec.damage)
							add_float(q.x, q.y, spec.damage)
						end
					end
				end
				add_fx(s.x, s.tip, 3)
				phos.audio.beep(160, 0.08, { wave = "square", sweep = 60, volume = 0.2 })
			end
			if s.age >= spec.life then
				table.remove(strikes, i)
			end
		end
	end
end

-- 点射（机枪）：每 burst 秒出膛一发，全部打完才让上层认为"这一炮结束"。
-- 装填发生在 update 里而不是一次性发完：连发要的是节奏，不是同时出膛
local function update_burst(dt)
	if not burst then
		return
	end
	burst.t = burst.t - dt
	if burst.t > 0 then
		return
	end
	burst.done = burst.done + 1
	local keep = burst.shooter.angle
	burst.shooter.angle = burst.base + spread_angle(burst.weapon, burst.done, burst.total)
	local p = Weapons.fire(burst.weapon, burst.shooter)
	burst.shooter.angle = keep
	p.trail = {}
	projectiles[#projectiles + 1] = p
	burst.t = burst.weapon.burst
	add_fx(p.x, p.y, 1)
	phos.audio.beep(320, 0.03, { wave = "square", sweep = 120, volume = 0.14 })
	if burst.done >= burst.total then
		burst = nil
	end
end

-- 这一炮真的打完了吗：炮弹没了、连发队列空了，燃烧与天基炮这些**后续特效**
-- 也都结束了，缺一不可。判定必须**每帧做一次**（见 update 末尾）：
-- 只在"炮弹消失"那一帧判的话，燃烧/天基炮这类"落地之后才开始"的特效
-- 当场就会被判成"还没完"，而此后没有任何地方会回头再判 —— 回合永远停在 flying
local function shot_finished()
	return #projectiles == 0 and not burst and #strikes == 0 and #fires == 0
end

-- 结算换手：唯一入口。延迟 0.8 秒，让爆炸与音效落地再切手
local function settle_shot()
	turn:end_shot()
	switch_delay = 0.8
end

function fire(shooter, weapon)
	if not Weapons.has_ammo(shooter, weapon) then
		add_float(shooter.x, shooter.y, 0, L().no_ammo, phos.color.orange)
		phos.audio.beep(120, 0.05, { wave = "square", volume = 0.16 })
		return false
	end
	if not turn:ready(weapon.id) then
		phos.audio.beep(120, 0.05, { wave = "square", volume = 0.16 })
		return false
	end
	shooter.power = aim_power

	local instant = false
	if weapon.kind == "utility" then
		if not fire_teleport(shooter, weapon) then
			add_float(shooter.x, shooter.y, 0, L().no_tp, phos.color.orange)
			return false
		end
		instant = true
	elseif weapon.kind == "spread" then
		-- 散射：把 N 枚**普通炮弹**按等分角打出去（有抛物线、受风，不是瞬时射线）。
		-- 带 burst 的（机枪）这次只出一发，剩下的交给 update_burst 按间隔点射
		local n = weapon.shells or 1
		local now = weapon.burst and 1 or n
		for i = 1, now do
			local keep = shooter.angle
			if n > 1 then
				shooter.angle = keep + spread_angle(weapon, i, n)
			end
			local p = Weapons.fire(weapon, shooter)
			shooter.angle = keep
			p.trail = {}
			projectiles[#projectiles + 1] = p
		end
		if weapon.burst and n > 1 then
			burst = { weapon = weapon, shooter = shooter, base = shooter.angle, done = 1, total = n, t = weapon.burst }
		end
	elseif weapon.kind == "laser" then
		-- 激光是一条**会飞的光束**：初速拉到很高、不受重力、不落不炸，
		-- 一路烧穿地形并伤到碰到的人，直到飞出地图边界（镜头一路跟着它）
		local a = math.rad(shooter.angle)
		local sp = weapon.speed or 900
		local mx, my = Physics.muzzle_of(shooter)
		local p =
			Physics.new_projectile(mx, my, math.cos(a) * sp * shooter.facing, -math.sin(a) * sp, { no_gravity = true })
		p.weapon, p.shooter, p.trail, p.hit = weapon, shooter, {}, {}
		projectiles[#projectiles + 1] = p
	else
		local p = Weapons.fire(weapon, shooter)
		p.trail = {}
		projectiles[#projectiles + 1] = p
	end

	spend_ammo(shooter, weapon)
	-- 让侧栏与读数跟着**开火单位**显示它选的武器：队友或敌人开炮时，
	-- 玩家也能看清对面在用哪件道具（这是"谁在用道具"的唯一线索）
	for i, spec in ipairs(Weapons.LIST) do
		if spec == weapon then
			weapon_index = i
		end
	end
	turn:begin_shot()
	phos.audio.beep(180, 0.08, { wave = "square", sweep = 90, volume = 0.25 })
	if instant then
		settle_shot()
	end -- 传送这类"当场结算"的也走同一个换手入口
	return true
end

-- 传送：角度定方向、力度定距离，落点必须站得住。
-- 找不到落点时**要说出来**（浮字"无法传送"）——只"嘟"一声玩家会以为道具坏了
function fire_teleport(shooter, weapon)
	local a = math.rad(shooter.angle)
	local dx, dy = math.cos(a) * shooter.facing, -math.sin(a)
	local dist = 20 + Physics.speed_of(aim_power) * 3
	tp_info = {
		angle = shooter.angle,
		facing = shooter.facing,
		dist = math.floor(dist),
		bounds = "?",
		tried = 0,
		tx = 0,
		ty = 0,
		gx = -1,
		gy = -1,
	}
	for d = dist, 4, -4 do
		local tx, ty = math.floor(shooter.x + dx * d), math.floor(shooter.y + dy * d)
		tp_info.tried = tp_info.tried + 1
		tp_info.tx, tp_info.ty = tx, ty
		if tx > 2 and tx < terrain.W - 2 then
			-- 朝上瞄准时目标点会飞出世界顶部：夹回来再往下找地。
			-- 用 ground_below（向下），不是 find_ground（向上）——方向错了永远落不了地
			ty = math.max(3, math.min(ty, terrain.WATER_Y - 3))
			tp_info.bounds = "ok"
			local gx, gy = terrain:ground_below(tx, ty)
			tp_info.gx, tp_info.gy = gx or -1, gy or -1
			if gx and math.abs(gx - shooter.x) + math.abs(gy - shooter.y) > 3 then
				add_fx(shooter.x, shooter.y, 4)
				shooter.x, shooter.y = gx, gy
				shooter.on_ground, shooter.vy, shooter.fall_from = true, 0, nil
				add_fx(gx, gy, 4)
				return true
			end
		elseif tp_info.bounds == "?" then
			tp_info.bounds = string.format("越界 tx=%d ty=%d", tx, ty)
		end
	end
	return false
end

-- 弹药落地/引信到点：挖地形、按距离伤血、必要时分裂或留下火
local function resolve(p)
	local w = p.weapon or {}
	add_fx(p.x, p.y, w.radius)
	-- 镜头在爆炸处多停一会儿：立刻切回虫子会让人看不清"到底炸成什么样了"
	cam.focus, cam.hold = { p.x, p.y }, 1.3
	-- 治疗弹不炸、不挖地：只给**自己队**回血（敌人治敌人、队友治队友）。
	-- 直击目标已在命中时结算过全额，这里只补溅射范围内的其他队友；
	-- 实际回血量由 Worms:heal 给出，血满即为 0，不冒数字
	if (w.heal or 0) > 0 then
		local r = w.radius or 3
		for _, q in ipairs(worms.list) do
			if q.alive and q ~= p.direct and q.team == (p.shooter and p.shooter.team or -1) then
				local d = math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2)
				if d <= r then
					local got = worms:heal(q, w.heal * math.max(0.4, 1 - d / r))
					if got >= 1 then
						add_float(q.x, q.y, 0, "+" .. math.floor(got + 0.5), phos.color.green)
					end
				end
			end
		end
	elseif w.effect == "dig" then
		-- 地消弹：只挖地形，**不伤人、不推人**（不带冲量，免得 0 伤害的爆炸仍把人推进水里）。
		-- 传空目标表 = 只走 terrain:blast 那条挖地路径
		Physics.blast(p.x, p.y, w.radius or 0, 0, {}, terrain)
	elseif (w.radius or 0) > 0 then
		local events = {}
		-- p.direct 已在撞虫那一刻拿过全额伤害，这里把它排除在距离衰减之外
		worms:apply_blast(p.x, p.y, w.radius, w.damage, events, p.direct)
		for _, e in ipairs(events) do
			if e.damage and e.damage >= 1 then
				add_float(e.worm.x, e.worm.y, e.damage)
			end
		end
		-- 记下"这一炸扫到了谁"：AI 下一轮据此判断自己是不是站在危险位置
		for _, q in ipairs(worms.list) do
			if q.alive and math.abs(q.x - p.x) <= (w.radius or 0) * 1.5 then
				q.exposed = turn.round
			end
		end
	end
	-- 地形弹：不伤人不挖地，落点长出一块圆形地形
	if (w.raise or 0) > 0 then
		local grew = terrain:fill_circle(math.floor(p.x), math.floor(p.y), w.raise)
		add_float(p.x, p.y, 0, string.format(L().raised, grew), COL.top)
	end
	-- 天基炮：登记一次打击（等待 spec.delay 秒后开始释放，见 update_strikes）
	if w.orbital then
		strikes[#strikes + 1] = { x = p.x, y = p.y, t = w.orbital.delay, age = 0, next_tick = 0,
		                          tip = 0, spec = w.orbital }
		-- 记下落点与"开火时那一列的地表高度"：光柱烧完再量一次，
		-- 就能读出它到底挖下去多少（观察口用）
		strike_dbg = { x = math.floor(p.x), top0 = surface_at(math.floor(p.x)) }
		add_float(p.x, p.y, 0, L().orbital, phos.color.cyan)
	end
	if w.burn then
		fires[#fires + 1] = { x = p.x, y = p.y, radius = w.radius or 3, life = w.burn }
		add_float(p.x, p.y, 0, L().burning, phos.color.orange)
	end
	if w.splits then
		for _, q in ipairs(Weapons.split(w, p.x, p.y, w.splits - 1)) do
			q.trail = {}
			projectiles[#projectiles + 1] = q
		end
	end
	if phos.audio.available and phos.audio.available() then
		phos.audio.beep(90, 0.18, { wave = "noise", volume = 0.3, release = 0.12 })
	end
end

-- ---------- 回合流转 ----------

local function after_settle()
	if worms:team_wiped(1) then
		turn:finish(2)
		winner = 2
		return
	end
	if worms:team_wiped(2) then
		turn:finish(1)
		winner = 1
		return
	end
	-- 继承：刚开炮的这只虫把**力度 / 角度 / 朝向 / 选的弹药**全记在身上，
	-- 下次轮到它时原样恢复——每个人记得自己的手感，也省得每轮重新瞄一遍
	local fired = active[turn.team]
	if fired then
		-- 只记"这一炮实际用了多少力度、选的哪件武器"。角度与朝向瞄准时已经写在
		-- w 身上了，再赋一遍是自赋值，什么也不做
		fired.power, fired.weapon = aim_power, weapon_index
	end
	turn:next_team()
	-- 换到该队的**下一只活虫**。起点必须是**新换上的这一队自己**上一次上场的那只：
	-- 拿对面队伍的虫当起点的话永远匹配不到，结果每回合都回到第一只
	pick_active(turn.team, active[turn.team])
	-- 轮到谁就恢复谁上次的力度/朝向/弹药；第一轮用默认值
	local now = current_worm()
	aim_power, charge_mode = (now and now.power) or DEFAULT_POWER, false
	-- 这只虫**第一次**轮到自己时回到普通炮弹（列表第一件）。
	-- 不能沿用上一个开火者选的武器：那会让还没开过炮的虫子端着别人的弹药开打
	weapon_index = (now and now.weapon) or 1
	cam.focus, cam.hold = nil, 0
	reset_pan()
	ai_delay = 1.2
	ai_plan = nil
	ai_decided, ai_walk_t = false, 0 -- 新回合重新决定"要不要先走位"
	ai_walk_dir = nil
	ai_walk_from_x, ai_walk_total = 0, 0
	ai_reason, ai_run_away = nil, false
	ai_repositioned = false
	ai_friendly_tried = false
	burst = nil -- 换手时旧的连发队列必须清掉
	-- "按住时长"不在这里清：它由主机按按键状态给（松手即 0）。
	-- 于是换手时按着不放就继续快，松开自然回到慢速微调——比硬清零更合手感
end

-- 跳过本回合：不发射，直接把回合交给对面。走的是与"开炮结算"同一条路径（after_settle），
-- 所以胜负判断、换手、AI 重置都一并在里面——不留第二条换手分支。
-- 人用 N 键触发；AI 被地形完全埋住、且这一炮要么没用要么会把自己炸死时也调它（见 update_ai）。
function pass_turn()
	after_settle()
end

-- AI 这一炮能用的武器：有弹药，且武器表声明给电脑用（`spec.ai` 不是 false/self）。
-- "这局势值不值得用这一件"不在这里判——那是评分的事（见 ai.lua 的 AI.WEIGHTS）
local function ai_weapons(w)
	local out = {}
	for _, spec in ipairs(Weapons.LIST) do
		-- 谁能进候选由**武器表自己**声明（spec.ai）：throw 参战 / self 只对自己用 / false 不用。
		-- 加一件武器只需在武器表写下这一项；值不值得用、扎堆打划不划算，
		-- 由 ai.lua 的评分按"世界变化量"说了算
		if spec.ai ~= false and spec.ai ~= "self" and Weapons.has_ammo(w, spec) then
			out[#out + 1] = spec
		end
	end
	return out
end

-- 离这只虫最近的活敌人：赶路朝它走，躲藏背对它。一个活敌人都没有就返回 nil
local function nearest_enemy(w)
	local best, bd = nil, math.huge
	for _, e in ipairs(worms.list) do
		if e.alive and e.team ~= w.team then
			local d = math.abs(e.x - w.x)
			if d < bd then
				best, bd = e, d
			end
		end
	end
	return best
end

-- 这只虫在 dir 方向上、这一带是否撞过死胡同。记录存在**虫身上**（w.blocked[dir] = 撞墙处的 x），
-- 因此跨回合保留：同一张图里不同虫的遭遇不同，也不至于"下回合又钻进同一个死胡同"
local function blocked_here(w, dir)
	local bx = w.blocked and w.blocked[dir]
	return bx ~= nil and math.abs(w.x - bx) < AI.STUCK_NEAR
end

-- 开始一段走位：**所有走位的唯一入口**。集中在这里记录起点 x 与总时长（死胡同检测要用），
-- 否则几个调用点各写一份、漏掉一处就会漏检。dir 传 nil 表示"按朝向决定"（逃跑 / 躲藏）
-- 传送脱困（供被埋的 AI 用）：朝最近敌人方向、抬一点角度，让 fire_teleport 在**实地上**
-- 找一个落点把虫挪出去（传送能穿过地形，正是"埋住还能跑"的手段）。找不到落点返回 false——
-- fire 会冒"无法传送"且**不消耗弹药**，调用方据此继续走别的脱困分支
local function try_teleport_escape(w)
	local tp = Weapons.by_id("teleport")
	if not tp or not Weapons.has_ammo(w, tp) then return false end
	local foe = nearest_enemy(w)
	if foe then w.facing = (foe.x >= w.x) and 1 or -1 end
	w.angle, aim_power = 30, 0.5
	return fire(w, tp)
end

local function begin_walk(w, dir, duration, reason, run_away)
	ai_walk_from_x, ai_walk_total = w.x, duration
	ai_walk_t, ai_walk_dir, ai_run_away = duration, dir, run_away or false
	ai_reason = reason
end

local function update_ai(dt)
	if turn.phase ~= "aim" or winner then
		return
	end
	ai_delay = ai_delay - dt
	if ai_delay > 0 then
		return
	end
	local w = current_worm()
	if not w or not w.alive then
		turn:next_team()
		pick_active(1)
		ai_delay = 1.2
		return
	end
	-- 先朝向最近的敌人，再让 AI 规划（同一份 physics 粗预演）
	local foe = (turn.team == 1) and 2 or 1
	local best, bestd = nil, 1e9
	for _, e in ipairs(worms:of_team(foe)) do
		local d = math.abs(e.x - w.x)
		if d < bestd then
			best, bestd = e, d
		end
	end
	if best then
		w.facing = (best.x >= w.x) and 1 or -1
	end

	-- 走位只在**两种能说出理由**的情况下发生（不是随机挪）：
	--   exposed：上一轮挨过炸，先离开原地（难度越高越肯躲）
	--   blocked：算完了发现最好的落点离敌人还差得远（预测线被地形挡住 / 够不着）
	local cfg = AI.DIFFICULTY[DIFFS[menu.diff]] or AI.DIFFICULTY.normal
	if not ai_decided then
		ai_decided = true
		-- 捡补给排在躲避之前：箱子是**够得着才去**（判据见 supply:reachable），
		-- 够不着就照常开炮——为捡不到的东西绕路，比不捡更蠢。
		-- 走位时长按距离算，走到为止：固定的 walk_time 走不到 20 格外的箱子
		-- 被埋住时一律不安排走位（走不动，供给 / 躲避都到不了），留给后面的"开炮还是跳过"
		if w.buried then
			-- 被埋：不安排走位
		elseif supply and supply:reachable(w, terrain) then
			local c = supply.crate
			begin_walk(w, (c.x >= w.x) and 1 or -1,
			           math.abs(c.x - w.x) / Worms.WALK_SPEED + 0.4, "supply", false)
		elseif w.exposed and w.exposed >= turn.round - 1 and phos.sys.random(1, 100) <= cfg.dodge then
			begin_walk(w, nil, cfg.walk_time, "exposed", true)
		end
	end
	if ai_walk_t > 0 then
		ai_walk_t = ai_walk_t - dt
		local dir = ai_walk_dir or (ai_run_away and -w.facing or w.facing)
		-- 走不动就跳：跳是为了翻过挡住路的坡（走/跳的判据都在 worms.lua，同一个口径）
		if not worms:move(w, dir, dt) then
			worms:jump(w)
		end
		-- **死胡同检测**：走了 STUCK_T 秒净位移还很小，就认定这个方向走不通，立刻收手
		-- （不再把整段走位时间耗在拱墙上）。若这次是"赶路"（far / blocked），把方向与位置
		-- 记在虫身上：下一回合经过这里时不再往同一个死胡同里钻，先试反方向或干脆躲
		if ai_walk_total - ai_walk_t >= AI.STUCK_T
			and math.abs(w.x - ai_walk_from_x) < AI.STUCK_MOVE then
			if ai_walk_dir and (ai_reason == "far" or ai_reason == "blocked") then
				w.blocked = w.blocked or {}
				w.blocked[ai_walk_dir] = w.x
			end
			ai_walk_t, ai_walk_dir = 0, nil
			ai_reason, ai_last = "dead_end", "死胡同 收手"
		end
		return
	end

	-- 规划是**分帧推进**的：一次算完几百组预演会触发主机的 100 毫秒看门狗
	if not ai_plan then
		ai_plan = AI.plan_begin(w, worms.list, terrain, turn.wind, DIFFS[menu.diff], ai_weapons(w))
		if not ai_plan then
			-- 换手要按**新换上的那一队**选虫：写死 1 会把对面那只换错
			turn:next_team()
			pick_active(turn.team)
			ai_delay = 1.2
			return
		end
	end
	if not ai_plan:advance(AI.BATCH) then
		return
	end
	local plan = ai_plan:result()
	ai_plan = nil
	-- 误伤自省：这一炮会打到队友、时间还够、本回合还没为此挪过 —— 先挪一小段再重新瞄，
	-- 尽量避开（**一次为限**：挪不出干净角度就照打，误伤不是硬禁止）。方向取"背离会被
	-- 打到的那名队友"，挪完下一帧的重规划会重新挑角度 / 换武器 / 换目标
	if plan and plan.mate and not w.buried and turn.left > AI.WALK_LEAVE and not ai_friendly_tried then
		ai_friendly_tried = true
		local dir = (plan.mate_x and plan.mate_x >= w.x) and -1 or 1
		begin_walk(w, dir, AI.WALK_CHUNK, "friendly", false)
		ai_last = "避队友 挪位"
		return
	end
	-- 被地形**完全埋住**：走不动，走位逻辑无从谈起。此时按"损失优先"的**脱困优先序**挑一步
	-- （这也是 AI 会用到地消弹 / 激光 / 传送的地方）：
	--   ① 无损脱困：地消弹挖开 / 激光穿地命中（自伤 = 0）
	--   ② 传送：无损换位（AI 平时不规划它，见 weapons.lua 的 ai=self）
	--   ③ 自炸脱困：自伤 ≤ AI.BURIED_SELF_MAX × 当前血量（血够厚才赌）
	--   ④ 治疗：血不够自炸时先回血，**下回合血够了再自炸脱困**；血满不回（不空扔）
	--   ⑤ 都不行 → 跳过 —— 死了不如赖活着，卡在土里至少能耗敌人弹药
	if w.buried then
		local bo = (plan and plan.best_of) or {}
		local dig, beam, blast, heal = bo.dig, bo.beam, bo.blast, bo.heal
		local beam_hits = beam and (beam.delta.damage or 0) > 0
		local blast_safe = blast and (blast.delta.own_damage or 0) <= w.hp * AI.BURIED_SELF_MAX
		local function go(c)
			-- best_of 里存的是规划器的**候选**（瞄法在 c.aim 下），不是 result() 的成品（那才有顶层 angle/power）
			w.angle, aim_power = c.aim.angle, c.aim.power
			ai_last = string.format("%s（被埋自救）", c.reason or c.weapon.id)
			fire(w, c.weapon)
		end
		if dig then
			go(dig)
		elseif beam_hits then
			go(beam)
		elseif try_teleport_escape(w) then
			ai_last = "被埋 传送脱困"
		elseif blast_safe then
			go(blast)
		elseif heal and w.hp < Worms.MAX_HP then
			go(heal)
		else
			ai_last = "被埋 跳过"
			pass_turn()
		end
		return
	end
	-- 这一炮算不算"打得到"：被地形挡住，或者落点离目标差得远，都算够不着。
	-- 挡住这条必须在这里判：被挡的炮往往炸在自己脚边，"落点差"看着不大，
	-- 但那一炮等于白打 —— 预演阶段已经把 blocked 报出来了（见 ai.lua 的 preview）
	-- "被挡"只对**爆炸类**算白打：它的价值全在落点上，撞在山坡上就没了。
	-- 治疗弹不在此列 —— 它撞在山坡上也可能正好罩住趴在那儿的伤员
	-- （实测里就有"被挡但落点差 1"的治疗弹，那是好炮，不该赶着它去别处）
	local reach = plan and ((plan.blocked and plan.weapon.effect == "blast")
		or (plan.near and plan.near > cfg.good_dist))
	local enemy = nearest_enemy(w)
	-- 够不着、而且**时间还够**：接着往敌人那边赶路，而不是随便打一发。
	-- 大地图上用完激光这类远程手段之后，站在原地把无限普通弹打出去就是白费回合：
	-- 一回合有 60 秒，走到射程里再打才是这一回合该干的事。
	-- 每段只走 WALK_CHUNK 秒就回来重算一遍 —— 一次走太久会冲过射程，也没机会改主意
	if reach and enemy and turn.left > AI.WALK_LEAVE then
		local dir = (enemy.x >= w.x) and 1 or -1
		-- 这个方向、这一带上次撞过死胡同：先试往反方向绕；两头都堵死就别硬耗，就地对空躲
		-- （与其把整回合拱在墙上，不如留着时间看下回合地形 / 战况有没有变）
		if blocked_here(w, dir) then
			if blocked_here(w, -dir) then
				begin_walk(w, nil, turn.left, "dead_end", true)
				ai_last = "死胡同 原地躲"
				return
			end
			dir, ai_reason = -dir, "around"
		else
			ai_reason = plan.blocked and "blocked" or "far"
		end
		ai_repositioned = true
		begin_walk(w, dir, AI.WALK_CHUNK, ai_reason, false)
		return
	end
	if plan and not reach then
		w.angle, aim_power = plan.angle, plan.power
		-- 理由串里已经有武器名（见 ai.lua 的 reason_of），这里不再重复一遍
		ai_last = string.format(
			"%s %d° 力%d 落点差%d",
			plan.reason or plan.weapon.id,
			math.floor(plan.angle + 0.5),
			math.floor(plan.power * 100 + 0.5),
			math.floor((plan.near or -1) + 0.5)
		)
		fire(w, plan.weapon)
	elseif plan then
		-- 时间不够了、又确实够不着：**消极处理**。这一炮不开（乱打只会伤到队友），
		-- 背向敌人挪一点就地躲起来，走满剩下的时间，回合到点自然换手
		begin_walk(w, enemy and ((enemy.x >= w.x) and -1 or 1) or -w.facing, turn.left, "hide", true)
		ai_last = "够不着 躲起来"
		return
	else
		turn:next_team()
		pick_active(turn.team)
		ai_delay = 1.2
	end
end

-- ---------- 主循环 ----------

local function update_fires(dt)
	for i = #fires, 1, -1 do
		local f = fires[i]
		f.life = f.life - dt
		if f.life <= 0 then
			table.remove(fires, i)
		else
			for _, w in ipairs(worms.list) do
				if w.alive then
					local dx, dy = w.x - f.x, w.y - f.y
					if dx * dx + dy * dy <= f.radius * f.radius then
						worms:damage(w, Physics.BURN_DPS * dt)
					end
				end
			end
		end
	end
end

local function update_particles(dt)
	for i = #fx, 1, -1 do
		local f = fx[i]
		f.t = f.t - dt
		if f.t <= 0 then
			table.remove(fx, i)
		else
			if f.kind == "spark" then
				f.vy = f.vy + 26 * dt
				f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt
			elseif f.kind == "smoke" then
				f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt
			end
		end
	end
end

-- 还在跑的特效里最该看的那个：天基炮优先于燃烧。
-- 镜头**从特效推导目标**，不靠"倒计时抢镜头"——倒计时只会在特效演一半时放走镜头
local function effect_focus()
	if strikes[1] then
		return strikes[1].x, strikes[1].y
	end
	if fires[1] then
		return fires[#fires].x, fires[#fires].y
	end
	return nil
end

-- 镜头优先级：飞行中的弹药 → 还在跑的特效 → 爆炸后的短暂停留 → 当前虫子。
-- , . 左右、' / 上下平移；平移是**相对当前目标的偏移**，不设上限
-- （只受世界边缘约束），否则视野外的敌人与地下的深处都看不到
local function update_camera(dt)
	if phos.input.down("comma") then
		cam.pan = cam.pan - 130 * dt
	end
	if phos.input.down("period") then
		cam.pan = cam.pan + 130 * dt
	end
	if phos.input.down("apostrophe") then
		cam.pan_y = cam.pan_y - 130 * dt
	end
	if phos.input.down("slash") then
		cam.pan_y = cam.pan_y + 130 * dt
	end
	if cam.hold > 0 then
		cam.hold = cam.hold - dt
	end

	local p = projectiles[1]
	local tx, ty
	if p then
		tx, ty = p.x, p.y
	else
		tx, ty = effect_focus()
		if not tx and cam.hold > 0 and cam.focus then
			tx, ty = cam.focus[1], cam.focus[2]
		end
		if not tx then
			local w = current_worm()
			if w and w.alive then
				tx, ty = w.x, w.y
			end
		end
	end
	if tx then
		local k = 1 - math.exp(-dt * 6)
		cam.x, cam.y = cam.x + (tx - cam.x) * k, cam.y + (ty - cam.y) * k
	end
	camera:center(cam.x + cam.pan, cam.y + cam.pan_y)
end

-- ---- 联机对局同步（P3，见 DESIGN.md §13.5）：输入中继锁步 ----
-- 两端同 seed 跑同一份模拟；只有"当前行动者"的机器广播它的输入，其余端缓冲重放。
-- AI 回合不交换输入（两端各自确定性运行）。

-- 联机中某个对端退出（掉线或被断开）：它的虫**直接判负**（不再交给 AI），标记"已退出"，
-- 侧栏照常显示一行。若因此把整队打光就当场分胜负；若恰好轮到它，就把回合交给对面。
-- 只做"安静地死"：不触发阵亡爆炸，免得退出还牵连炸伤旁边的人。
local function retire_owned(peer)
	if not worms or winner then return end
	for _, wm in ipairs(worms.list) do
		if wm.owner == peer and wm.alive then
			wm.alive, wm.hp, wm.left = false, 0, true
		end
	end
	if not turn then return end
	if worms:team_wiped(1) then turn:finish(2); winner = 2; return end
	if worms:team_wiped(2) then turn:finish(1); winner = 1; return end
	if turn.phase == "aim" then
		local cur = current_worm()
		if not cur or not cur.alive then after_settle() end
	end
end

local function mnet_abort()
	phos.net.stop()
	phos.sys.capture_escape(false)
	mnet = nil
	netframe.active = false
	lan = nil
	lan_pause = false
	help_open = false
	winner = nil
	screen = "menu"
	menu.row = 1
	phos.panel.resize(0)
	phos.audio.stop_music()
end

local function mnet_poll()
	for _, e in ipairs(phos.net.events()) do
		if e.type == "disconnected" then
			if phos.net.role() ~= "host" and e.peer == phos.net.host_id() then
				mnet_abort() -- 房主掉线：整局作废，回菜单
				return
			end
			mnet.peers[e.peer] = nil -- 不再等它的帧包（否则两边都卡死）
			retire_owned(e.peer)     -- 掉线者的虫视为死亡，并标记"已退出"
			if phos.net.role() == "host" then
				phos.net.broadcast("wns.gone", { peer = e.peer }) -- 让其他客人也一致地看它退出
			end
		end
	end
	for _, m in ipairs(phos.net.poll()) do
		if m.kind == "wns.in" and m.data and m.data.f then
			local map = mnet.remote[m.from]
			if not map then map = {}; mnet.remote[m.from] = map end
			map[m.data.f] = m.data.k or {}
		elseif m.kind == "wns.gone" and m.data and m.data.peer then
			retire_owned(m.data.peer)
		end
	end
end

-- 输入中继锁步的**帧门**：每个对端每帧都发一个包（行动者发真实按键，其余发空包），
-- 双方都**等齐所有对端第 frame 帧的包**才推进 —— 谁都不许抢跑。
--
-- 关键：**本机操作时也走 netframe（不再直接读 phos.input 的边沿）**。原因是引擎的按键
-- 边沿检测按逻辑帧走，而停留（等包）时逻辑帧仍在走 —— 若直接读引擎边沿，行动方可能会
-- 在一次停留里"漏掉"一次按下，而观看方从 down 序列里看得出来，两端就此分叉。
-- 所以两端都用"每帧 down 集合"推导 pressed/released/duration，口径必然一致。
local function mnet_begin_frame()
	local w = current_worm()
	local me = phos.net.self_id()
	local owner = (w and w.alive) and w.owner or nil
	local own = (owner == me)
	local remote_human = owner and owner ~= 0 and owner ~= me

	-- ① 采集本机按键，记在 frame+延迟 上广播（本机操作发真实按键；其余发空包对齐节奏）。
	-- **发出哪份、推进第 frame 帧时就用哪份** —— 存进 mnet.sent[frame+延迟]，
	-- 轮到模拟那一帧时取同一份；否则"发早、用晚"会让两端输入对不上
	local send_f = mnet.frame + NET_DELAY
	if not mnet.sent[send_f] then
		local d = {}
		if own and not lan_pause then -- 菜单浮层打开时本机不发按键（游戏照常，只是我不操作）
			for _, k in ipairs(NET_KEYS) do d[k] = phos.input.down(k) end
		end
		phos.net.broadcast("wns.in", { f = send_f, k = d })
		mnet.sent[send_f] = d
	end
	-- ② 等齐所有对端**本帧**的包（它们在延迟帧之前就发出了，正常早已到位，几乎不必等）
	for peer in pairs(mnet.peers) do
		local map = mnet.remote[peer]
		if not (map and map[mnet.frame]) then return false end
	end
	-- ③ 定本帧 down 集合：本机操作 = 发出去的那份；远端人 = 它的快照；AI = 全松
	local nd = {}
	if own then
		local d = mnet.sent[mnet.frame] or {}
		for _, k in ipairs(NET_KEYS) do nd[k] = d[k] == true end
	elseif remote_human then
		local snap = (mnet.remote[owner] and mnet.remote[owner][mnet.frame]) or {}
		for _, k in ipairs(NET_KEYS) do nd[k] = snap[k] == true end
	end
	local dur = {}
	for _, k in ipairs(NET_KEYS) do dur[k] = nd[k] and ((netframe.dur[k] or 0) + 1) or 0 end
	netframe.prev, netframe.down, netframe.dur = netframe.down, nd, dur
	-- 只有在"人操作"时才打开 netframe（AI 回合要留给 update_ai，不能走 replay）
	netframe.active = own or remote_human
	return true
end

function update(dt)
	flash = flash + dt
	if screen == "lobby" then
		lan_update(dt) -- 局域网大厅：面板自己驱动，不进对局循环
		return
	end
	-- 联机对局中的 Esc：**非暂停**浮层（继续游戏 / 退出房间）。Esc 由卡带接管
	-- （phos.sys.capture_escape），所以这里能收到；浮层打开时本机不发按键，游戏照常走
	if mnet then
		if phos.input.pressed("escape") then
			lan_pause = not lan_pause
			lan_pause_sel = 1
			phos.audio.beep(lan_pause and 540 or 380, 0.04, { wave = "square", volume = 0.14 })
		end
		if lan_pause then
			if phos.input.pressed("up") then lan_pause_sel = 1 end
			if phos.input.pressed("down") then lan_pause_sel = 2 end
			if phos.input.pressed("start") then
				if lan_pause_sel == 1 then
					lan_pause = false
				else
					mnet_abort() -- 退出房间：停网、回菜单（房主即解散）
					return
				end
			end
		end
	end
	-- 联机帧门：必须在**任何**模拟推进之前（点射 / 天基炮 / 天气 / 物理都在它后面）——
	-- 否则"本帧不推进"时，前面那几样仍会各走一步，两端就分叉了
	if mnet then
		mnet_poll()
		if mnet == nil then return end          -- mnet_abort 已回菜单
		if not mnet_begin_frame() then return end -- 等对端本帧包：整帧不推进
	end
	update_burst(dt) -- 点射（机枪）：先把该出膛的那一发补上
	update_strikes(dt) -- 天基炮：等待/释放/结算
	-- M：地图总览浮窗。**不暂停**——它只是"看一眼地图"，
	-- 不该打断正在飞的弹药与回合计时
	if phos.input.pressed("m") then
		map_open = not map_open
		phos.audio.beep(map_open and 600 or 380, 0.04, { wave = "square", volume = 0.14 })
	end
	if phos.input.pressed("k") then
		help_open = not help_open
		-- 联机时**不**改面板/暂停/重建区域：那会消耗一次随机数或改可玩区，
		-- 只在一端发生就会让两端的模拟分叉（键位表在联机里只作浮层）
		if not mnet then
			phos.audio.paused(help_open) -- 看键位表时连音乐一起停
			phos.panel.resize(help_open and 0 or PANEL_W)
			refresh_regions() -- 可玩区宽度变了：前景与读数的区域要跟着重建
		end
	end
	if screen == "menu" then
		menu_flash = menu_flash + dt
		menu_input(dt)
		return
	end

	-- 天气与补给：只在**对局中**推进（菜单态还没有 terrain / turn，放在上面会当场崩）。
	-- 回合推进的**唯一钩子**也在这里：天气与补给都跟着"第几回合"走，
	-- 比对上一帧的回合数即可——换手有好几条路（结算、超时、AI 弃权），
	-- 散到每个换手点去改，漏掉任何一条天气就会停住
	if turn.round ~= last_round then
		last_round = turn.round
		weather:advance_round(turn.wind)
		supply:advance_round(turn.round, terrain)
	end
	weather:update(dt, turn.wind)
	supply:update(dt, turn.round, terrain, worms, on_supply_pickup)

	if winner then
		-- 分出胜负就停乐：回到菜单后应当安静（重开一局时 start_match 会再起）
		phos.audio.stop_music()
		if mnet then
			lan_match_over() -- 联机：分出胜负后留在房间里，房间重新开放
			return
		end
		if phos.input.pressed("start") then
			screen = "menu"
			menu_flash = 0
			phos.panel.resize(0)
		end
		return
	end
	if help_open and not mnet then
		return
	end -- 键位表打开时整局暂停（联机里不暂停，见上）

	if human_turn() then
		player_input(dt)
	elseif netframe.active then
		player_input(dt) -- 观看远端人操作：把快照当输入重放
	else
		update_ai(dt)
	end

	for i = #projectiles, 1, -1 do
		local p = projectiles[i]
		if p.weapon.kind == "track" then
			local best, bestd = nil, 1e9
			local my_team = p.shooter and p.shooter.team or 0
			for _, w in ipairs(worms.list) do
				if w.alive and w.team ~= my_team then
					local d = (w.x - p.x) ^ 2 + (w.y - p.y) ^ 2
					if d < bestd then
						best, bestd = w, d
					end
				end
			end
			if best then
				Weapons.steer(p, best, dt)
			end
		end
		if p.weapon.kind == "laser" then
			-- 光束每帧从上一处烧到当前处（不采样会留下断点），沿途伤到人；
			-- 只在地图边界停下——所以不能再走 probe（那会在撞到地形/人时就断）
			local px, py = p.x, p.y
			p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
			local steps = math.max(1, math.floor((math.abs(p.vx) + math.abs(p.vy)) * dt / 2))
			for s = 1, steps do
				local k = s / steps
				local bx, by = px + (p.x - px) * k, py + (p.y - py) * k
				Physics.blast(bx, by, p.weapon.width or 1, 0, {}, terrain)
				for _, w in ipairs(worms.list) do
					-- 判定是**躯体胶囊**：虫子从脚下往上约 9 子格都算被打到。
					-- 每只虫对同一条光束**只伤一次**——光束每帧都在扫，
					-- 不加这条的话一束光就把人打成筛子
					if w.alive and not p.hit[w] and math.abs(w.x - bx) < 2.5 and by >= w.y - 9 and by <= w.y + 1 then
						p.hit[w] = true
						worms:damage(w, p.weapon.damage)
						add_float(w.x, w.y, p.weapon.damage)
					end
				end
			end
			-- 观测用：记下光束位置与最近的敌虫（判定对不对要拿这两个数说话）
			local nf, nd = nil, 1e9
			for _, w in ipairs(worms.list) do
				if w.alive and w.team ~= (p.shooter and p.shooter.team or 0) then
					local d = math.abs(w.x - p.x)
					if d < nd then
						nf, nd = w, d
					end
				end
			end
			local nh = 0
			for _ in pairs(p.hit) do
				nh = nh + 1
			end
			laser_dbg = {
				x = math.floor(p.x),
				y = math.floor(p.y),
				fx = nf and math.floor(nf.x) or -1,
				fy = nf and math.floor(nf.y) or -1,
				dx = math.floor(nd),
				hits = nh,
			}
			if p.x < 1 or p.x > terrain.W or p.y < 1 or p.y > terrain.H then
				resolve(p)
				table.remove(projectiles, i)
			end
			local last = p.trail[#p.trail]
			if not last or (p.x - last[1]) ^ 2 + (p.y - last[2]) ^ 2 > 16 then
				p.trail[#p.trail + 1] = { p.x, p.y }
				if #p.trail > 90 then
					table.remove(p.trail, 1)
				end
			end
		else
			local result, point = Physics.step(p, dt, turn.wind, probe)
			local last = p.trail[#p.trail]
			if not last or (p.x - last[1]) ^ 2 + (p.y - last[2]) ^ 2 > 16 then
				p.trail[#p.trail + 1] = { p.x, p.y }
				if #p.trail > 60 then
					table.remove(p.trail, 1)
				end
			end
			if result then
				-- 直接命中（撞到虫身上）：按面板伤害**全额**结算。
				-- 命中判定用的是躯体半径（HIT_RADIUS = 3 子格），弹着点离虫脚最远也有 3，
				-- 只用爆炸的距离衰减去算的话，擦着打中的那发会被削到保底 10%——打中等于没打中
				if result == "worm" and point then
					if (p.weapon.heal or 0) > 0 then
						-- 治疗弹直击：只对**自己队**生效（打在对面身上什么都不发生）
						if point.team == (p.shooter and p.shooter.team or -1) then
							local got = worms:heal(point, p.weapon.heal)
							if got >= 1 then
								add_float(point.x, point.y, 0, "+" .. math.floor(got + 0.5), phos.color.green)
							end
						end
					else
						worms:damage(point, p.weapon.damage or 0)
						add_float(point.x, point.y, p.weapon.damage or 0)
					end
					p.direct = point
				end
				resolve(p)
				table.remove(projectiles, i)
			end
		end
	end

	local events = worms:update(dt)
	for _, e in ipairs(events) do
		if e.kind == "drowned" then
			add_float(e.worm.x, e.worm.y, 0, L().drowned, phos.color.blue)
		elseif e.kind == "landed" then
			-- 摔伤也是伤害：不给色 → add_float 按"有伤害数字"给红
			add_float(e.worm.x, e.worm.y, e.damage)
		end
	end

	-- 阵亡爆炸：谁倒下就炸一下（半径与伤害见 Worms.DEATH_*），波及身边单位。
	-- 换成新表处理，所以"爆炸又炸死了人"会在**下一帧**接着结算：
	-- 没有层层递归，连锁反应照样有
	local deaths = death_queue
	death_queue = {}
	for _, d in ipairs(deaths) do
		death_blasts = death_blasts + 1
		add_fx(d.x, d.y, 5)
		add_float(d.x, d.y, 0, L().death, phos.color.orange)
		local blast_events = {}
		worms:apply_blast(d.x, d.y, Worms.DEATH_RADIUS, Worms.DEATH_DAMAGE, blast_events)
		for _, e in ipairs(blast_events) do
			if e.damage and e.damage >= 1 then
				add_float(e.worm.x, e.worm.y, e.damage)
			end
		end
		phos.audio.beep(70, 0.3, { wave = "noise", volume = 0.28, release = 0.2 })
	end

	update_fires(dt)
	update_particles(dt)

	for i = #floats, 1, -1 do
		floats[i].t = floats[i].t - dt
		if floats[i].t <= 0 then
			table.remove(floats, i)
		end
	end

	-- 这一炮打完了吗：**每帧判一次**，判据只有 shot_finished() 一处。
	-- 放在这里（而不是炮弹消失那一刻）是因为"落地"与"结束"不是同一件事：
	-- 燃烧、天基炮光柱都是落地之后才开始的
	if turn.phase == "flying" and not switch_delay and not winner and shot_finished() then
		settle_shot()
	end

	-- 弹药结算后的换手延迟：必须**与阶段无关**地倒数
	if switch_delay and not winner then
		switch_delay = switch_delay - dt
		if switch_delay <= 0 then
			switch_delay = nil
			after_settle()
		end
	end

	if turn.phase == "aim" and not winner and not switch_delay then
		-- 当前这只虫已经不在了（坠落、落海、被炸死）：**立刻换手**。
		-- 不换的话，玩家会对着"已经不存在的那只虫"干等完 60 秒倒计时 ——
		-- 看着就是卡死；而"全队阵亡该分胜负"也只在结算时才查，最后一只死了同样卡
		local cur = current_worm()
		if not (cur and cur.alive) then
			after_settle()
			return
		end
		-- 回合计时只在"轮到我瞄准"时走：开炮期间停下来是刻意的
		local t = turn:tick(dt)
		if t.timeout then
			after_settle()
		end
	end

	update_camera(dt)
	-- 本帧已推进：清掉已用/过期的包，帧号 +1（两端一致）
	if mnet then
		mnet.sent[mnet.frame] = nil
		for _, map in pairs(mnet.remote) do
			for f in pairs(map) do if f <= mnet.frame then map[f] = nil end end
		end
		mnet.frame = mnet.frame + 1
	end
end

-- ---------- 绘制 ----------

local function in_view(i, j)
	return i >= 0 and i < VIEW_CW and j >= 0 and j < VIEW_CH
end

-- 世界坐标（子格）画一格
local function put_at(S, wx, wy, ch, col)
	local i, j = camera:cell_of(wx, wy)
	if in_view(i, j) then
		S:put(i, j, ch, col)
		return true
	end
	return false
end

-- 天空：整块交给 weather.lua —— 天色、日月、星、云都由**游戏内时钟**与天气推出来，
-- 这里只把相机原点递过去，不再自己摊一遍。风痕、降水与闪电不在这里：
-- 它们是前景（要压在人与地形上），画在天气层，见 draw
local function draw_sky(S, C)
	local cx, cy = camera:origin()
	weather:draw_sky(S, C, cx, cy)
end

local function draw_world(S, C)
	local cx, cy = camera:origin()
	local rows = terrain.rows
	-- 取格法与 camera:cell_of 必须**同一套**：视口格 i 覆盖子格 2i 与 2i+1。
	-- 差一格（例如写成 2*i+1）就会"画的是一处、判的是另一处"——
	-- "看着还有空间却走不过去""贴着墙能挤进去半格"都是这么来的
	for j = 0, VIEW_CH - 1 do
		local y0 = cy + 2 * j
		local r0, r1 = rows[y0], rows[y0 + 1]
		local water = y0 >= terrain.WATER_Y
		-- 深处逐格变暗：整屏一个颜色太单调，硬造一条分界线又会留下接缝，
		-- 所以按行做**连续**过渡（同一条渐变，看不出台阶）
		local t = math.max(0, math.min(1, (terrain.WATER_Y - y0) / (terrain.WATER_Y - 30)))
		-- 底色压暗过：纯"草绿"在整屏占比这么大时太亮太跳，白字压上去反而看不清
		local col = C.rgb(math.floor(18 + t * 26), math.floor(52 + t * 62), math.floor(32 + t * 34))
		for i = 0, VIEW_CW - 1 do
			local x = cx + 2 * i
			local bits = 0
			if r0 then
				if r0:byte(x) == BYTE_ONE then
					bits = bits + 1
				end
				if r0:byte(x + 1) == BYTE_ONE then
					bits = bits + 2
				end
			end
			if r1 then
				if r1:byte(x) == BYTE_ONE then
					bits = bits + 4
				end
				if r1:byte(x + 1) == BYTE_ONE then
					bits = bits + 8
				end
			end
			if bits > 0 then
				-- bits == 15 表示这一格的四个半格**全是土**：把底色也设成土色。
				-- 只设前景色的话，这格登记的底色仍然是天空色；之后在它上面画只写字形、
				-- 不动背景的字（血条、浮字、力度读数），天空色就被镶进土里，
				-- 看上去像地形被"镂"掉一块。**地形是底图，底图必须把底色也占住**。
				-- 只填满格而不填半格：地表那圈半格要留出天空，否则轮廓会变方
				if bits == 15 then
					S:fill(i, j, 1, 1, " ", col, col)
				else
					-- 位序与字形表都在引擎（phos.screen.quadrant）：卡带只报"这一格
					-- 哪几个子位是土"，字形与位序不许有第二份副本
					S:put(i, j, phos.screen.quadrant(bits), col)
				end
			elseif water then
				S:put(i, j, "≈", COL.water)
			end
		end
	end
end

-- 空投箱：吊着降落伞往下飘，落地后伞收掉、只剩箱子。
-- 落地后一闪一闪——它是有时限的东西，"还剩多久"要一眼看得出来
local function draw_crate(S, C)
	local c = supply and supply.crate
	if not c then
		return
	end
	if not c.landed then
		-- 伞：三个点当伞盖，两根绳连到箱子（一格一个字形，这样就读得出是降落伞）
		put_at(S, c.x - 2, c.y - 8, ".", C.gray)
		put_at(S, c.x, c.y - 8, "-", C.gray)
		put_at(S, c.x + 2, c.y - 8, ".", C.gray)
		for k = 0, 4 do
			put_at(S, c.x - 2, c.y - 6 + k, "|", C.gray)
			put_at(S, c.x + 2, c.y - 6 + k, "|", C.gray)
		end
	end
	local lit = (not c.landed) or (math.floor(flash * 3) % 2 == 0)
	local tone = lit and C.yellow or C.orange
	put_at(S, c.x - 3, c.y, "[", tone)
	put_at(S, c.x - 1, c.y, "#", tone)
	put_at(S, c.x + 1, c.y, "#", tone)
	put_at(S, c.x + 3, c.y, "]", tone)
end

local function draw_effects(S, C)
	draw_crate(S, C)
	for _, f in ipairs(fx) do
		local k = 1 - f.t / f.life -- 0 生 → 1 灭
		if f.kind == "ring" then
			local r = f.r * (0.35 + 0.85 * k)
			local col = (k > 0.66) and C.red or (k > 0.33 and C.orange or COL.spark)
			for a = 0, 15 do
				local ang = a * math.pi / 8
				put_at(S, f.x + math.cos(ang) * r, f.y + math.sin(ang) * r, "*", col)
			end
		elseif f.kind == "spark" then
			-- 前半程是亮点，后半程变成被掀起来的土块，落回地面色
			put_at(S, f.x, f.y, (k > 0.5) and "*" or "#", (k > 0.5) and COL.spark or COL.top)
		else
			put_at(S, f.x, f.y, "·", COL.smoke)
		end
	end
	for _, f in ipairs(fires) do
		for d = -f.radius, f.radius, 2 do
			put_at(S, f.x + d, f.y, "~", C.orange)
		end
	end
	-- 天基炮：等待期画闪烁的落点标记（要让人有机会跑开），释放期画贯天光柱
	for _, s in ipairs(strikes) do
		local half = (s.spec.width or 6) / 2
		if s.t > 0 then
			if math.floor(flash * 8) % 2 == 0 then
				-- 落点标记：比光柱窄一格（两端各收一个子格）。**纯外观** ——
				-- 挖地与判伤用的是 s.x0/s.x1 那一对世界子格，与这里无关
				for d = -half + 1, half - 1, 1 do
					put_at(S, s.x + d, s.y, (d == 0) and "V" or "-", C.cyan)
				end
			end
		else
			-- 光柱：从世界顶端贯到**柱尖此刻所在** —— 画的就是它扫下来的位置。
			-- 逐**格**画、每格同样的一笔：按子格画的话一格里会写两次，后一笔盖掉前一笔。
			-- 半格（世界格与屏幕格错开半格时）暂时不画 —— 那要引擎提供子格绘制，
			-- 卡带自己凑屏幕列只会越凑越歪（这一版就是这么错的）
			local tip = math.max(1, math.floor(s.tip))
			local c0, c1 = s.c0, s.c1
			if c0 and c1 then
				for c = c0, c1 do
					for wy = 1, tip do
						put_at(S, c * 2, wy, "|", C.cyan)
					end
				end
				-- 柱尖正在破开的那一层画一根亮横线：它跟着往下走，"下落"就看得见
				for c = c0 - 1, c1 + 1 do
					put_at(S, c * 2, tip, "=", C.white)
				end
			end
		end
	end
	-- 弹迹：越靠近弹体的点越亮（黄 → 橙 → 烟灰），尾端用底色收尾。
	-- 一律用灰白的话，白天与雨雪里压在亮背景上就整条看不见了
	for _, p in ipairs(projectiles) do
		local n = #p.trail
		for k, pt in ipairs(p.trail) do
			local t = k / math.max(1, n)
			local col = (t > 0.75 and C.yellow) or (t > 0.45 and C.orange) or COL.smoke
			put_at(S, pt[1], pt[2], "·", col)
		end
	end
end

-- 炮口符号：ASCII 表达方向就靠 - | / \ 四个（屏幕 y 向下，所以"往右上"是 /）
local function slope_glyph(ux, uy)
	if math.abs(ux) >= math.abs(uy) * 2 then
		return "-"
	end
	if math.abs(uy) >= math.abs(ux) * 2 then
		return "|"
	end
	return (ux * uy < 0) and "/" or "\\"
end

-- 瞄准线：从**炮口**沿瞄准方向点一条虚线，近密远疏，长度随力度长。
-- 它**只是一条直线**，不是弹道预测——角度看得清、落点还得自己算（DESIGN 第 7 节）。
-- 两档密度是刻意的：一个字符格 = 2x2 子格，本来就看不细；近身这一段要是也
-- 隔好几格才点一下，"炮口朝哪"就只能靠猜。
--   近身 AIM_NEAR_SUB：逐格点 + 白色，微调一度都看得出来
--   远处：隔一格点 + 武器色，只作方向示意，不去把整屏点满
-- 地形那一段**照画**，但换字形与颜色：整段跳过的话，地形会把后半条线吃掉——
-- 玩家就看不出炮口指向哪、这一炮会不会撞山。
-- 现在土里用暗色的 +、空中用亮色的 ·（一格仍只放一个字形），"线钻进山体"看得见。
-- （末端的 > < 是"力度标尺"而不是路径，所以照画、不跳过）
local function draw_aim(S, C)
	local w = current_worm()
	if not w or not w.alive or winner or not human_turn() then
		return
	end
	if turn.phase ~= "aim" then
		return
	end
	local a = math.rad(w.angle)
	local ux, uy = math.cos(a) * w.facing, -math.sin(a)
	local ox, oy = Physics.muzzle_of(w)
	local col = charge_mode and C.yellow or C.orange

	-- 炮口那格先点一个斜率符号：再密的虚线也不如一个 / 或 \ 把朝向说得清楚
	put_at(S, ox, oy, slope_glyph(ux, uy), charge_mode and C.yellow or C.white)

	local len = 12 + aim_power * 96
	for d = AIM_STEP_SUB, len, AIM_STEP_SUB do
		local x, y = ox + ux * d, oy + uy * d
		local near = d <= AIM_NEAR_SUB
		if near or (d / AIM_STEP_SUB) % 2 == 1 then
			local buried = terrain:solid(math.floor(x), math.floor(y))
			-- 钻进地形的那一段照画：换字形（+）+ 暗色，与空中的 · 一眼分得开，
			-- 地形也不再"盖住"后半条线
			put_at(S, x, y, buried and "+" or "·", buried and C.gray or (near and C.white or col))
		end
	end
	put_at(S, ox + ux * len, oy + uy * len, w.facing > 0 and ">" or "<", col)

	-- 读数贴在虫子旁边并用底色垫住：角度与力度必须是"扫一眼就知道"的东西
	local i, j = camera:cell_of(w.x, w.y - 1)
	local bar_w = 14
	local filled = math.floor(aim_power * bar_w + 0.5)
	local spec = selected_weapon()
	local left = spec and (w.ammo[spec.id] or 0) or 0
	local ammo_txt = (left < 0) and "∞" or tostring(left)
	local label =
		string.format("%4d° %3d%%  x%s", math.floor(w.angle + 0.5), math.floor(aim_power * 100 + 0.5), ammo_txt)
	local bar = "[" .. string.rep("#", filled) .. string.rep(".", bar_w - filled) .. "]"
	local lx = math.max(0, math.min(VIEW_CW - #bar - 1, i - 7))
	local ly = math.min(VIEW_CH - 2, j + 2)
	-- 两行都**不垫底板**：省略底色 = 保留该格原有的底（世界自己的色），于是读数
	-- 只是"压在画面上的一层字"，既不会挖出一块块黑方块，也没有"底比字身宽一格"
	-- 这件事。可读性靠配色：白/黄/绿与地形（偏绿、偏暗）拉得开
	S:print(lx, ly, label, charge_mode and C.yellow or C.white)
	S:print(lx, ly + 1, bar, charge_mode and C.yellow or C.green)
end

local function draw_actors(S, C)
	local ox, oy = camera:origin()
	for _, w in ipairs(worms.list) do
		if w.alive then
			local col = team_color(C, w.team, turn.team == w.team)
			-- 角色是**半格小人**：宽 1 子格、高 2 子格（与身体判定同一个尺寸）。
			-- 画法：把身体真正占的**两个子位**按所属的格分组，每格用 quadrant 合成字形。
			-- 只画它占的那两个子位 —— 用"整格高"的半块去画"只占半格"的身体，
			-- 多出来的半格会盖在土上（看着像陷进地形），脚落在格上半的角色还会比别的矮半格
			local vx2, vy2 = math.floor(w.x - ox), math.floor(w.y - oy)
			local cells = {}
			for row = vy2 - 1, vy2 do
				local gx, gy, bit = phos.screen.cell_of(vx2, row)
				if in_view(gx, gy) then
					local key = gx .. "," .. gy
					local cell = cells[key]
					if not cell then
						cell = { gx = gx, gy = gy, bits = 0 }
						cells[key] = cell
					end
					cell.bits = cell.bits + bit
				end
			end
			for _, cell in pairs(cells) do
				-- 不垫底板：blend 只落这一笔，笔画之外透出世界（土层/天空色）
				S:blend(cell.gx, cell.gy, phos.screen.quadrant(cell.bits), col)
			end
			-- 选标与血条都画在角色**上方**（血条，再上是选标）：压在角色身上会看成"角色变高了"
			local i, j = camera:cell_of(w.x, w.y)
			if in_view(i, j) then
				Hud.hp_bar(S, C, i, j - 2, w.hp / Worms.MAX_HP)
				if w == current_worm() and human_turn() then
					local blink = (math.floor(flash * 4) % 2 == 0)
					S:put(i, j - 3, blink and "V" or "^", C.white)
				end
			end
		end
	end
	for _, p in ipairs(projectiles) do
		-- 弹体**不垫底板**：只写字形、不动背景。白天与雪天靠"亮色 + 弹迹尾巴 +
		-- 高速弹的气浪"来保证看得见；在战况里挖黑方块比看不见更难看
		local i, j = camera:cell_of(p.x, p.y)
		if in_view(i, j) then
			S:put(i, j, "*", C.white)
			-- 高速弹的**气浪**：沿速度方向在弹体后面点两格，越远越淡。
			-- 慢速高抛弹不画——它本来就不"破空"，画了只会糊
			local sp = math.sqrt((p.vx or 0) ^ 2 + (p.vy or 0) ^ 2)
			if sp > 60 then
				local ux, uy = (p.vx or 0) / sp, (p.vy or 0) / sp
				put_at(S, p.x - ux * 3, p.y - uy * 3, "~", C.white)
				put_at(S, p.x - ux * 6, p.y - uy * 6, "'", C.gray)
			end
		end
	end
end

-- 在区域里画一个框（边框 + 嵌在上边的标题）：边线斜角用 + 补齐。
-- 一律用**区域局部坐标**，越界由区域自己夹住；边框只写字形、不动背景，
-- 于是它压在本区域刚铺好的底板上——与"先整块铺底、再画边框"的先后同义
local function box(r, title, tone)
	local w, h = r.w, r.h
	for i = 1, w do
		r:put(i - 1, 0, "-", tone)
		r:put(i - 1, h - 1, "-", tone)
	end
	for j = 1, h do
		r:put(0, j - 1, "|", tone)
		r:put(w - 1, j - 1, "|", tone)
	end
	r:put(0, 0, "+", tone)
	r:put(w - 1, 0, "+", tone)
	r:put(0, h - 1, "+", tone)
	r:put(w - 1, h - 1, "+", tone)
	-- 标题压在边框上：**不写底色**（保留框线那格的底），与窗体保持一致——
	-- 窗体铺了底板就沿用底板，窗体透明就跟着透明，不再单印一块异色方块
	if title then
		r:print(2, 0, " " .. title .. " ", tone)
	end
end

-- M 地图总览：整幅地形剖面 + 双方位置 + 空中弹药 + 风向。
-- 侧栏放不下这些（8v8 时光血量就占十几行），所以挪进浮窗；
-- 它**不暂停**：弹药还在飞的时候也能看一眼全局，不用牺牲一个回合
local function draw_map_overlay(C)
	local t = L()
	local mw = math.min(VIEW_CW - 8, 58)
	local mh = math.min(VIEW_CH - 14, 18)
	local x = math.floor((VIEW_CW - mw) / 2)
	local y = 4 -- 往下方放一些：上边留给状态行与瞄准读数
	-- 浮窗自己占一块区域、压在 overlay 层：坐标变成区域局部的，
	-- 越界由区域夹住；整块铺底用 clear（恒写底色 = 不透）
	local r = phos.ui.region(x, y, mw, mh + 3, { layer = "overlay" })
	r:clear(C.white, COL.plate)
	box(r, t.map_title, C.white)

	-- 地形剖面：每列向下取一次表面高度，往下画实心；水面单独一色
	local sx, sy = terrain.W / (mw - 2), terrain.H / mh
	local tops = {}
	for i = 0, mw - 3 do
		local wx = math.floor((i + 0.5) * sx) + 1
		tops[i] = 0
		for yy = 1, terrain.WATER_Y - 1 do
			if terrain:solid(wx, yy) then
				tops[i] = yy
				break
			end
		end
	end
	for j = 0, mh - 1 do
		local wy = math.floor((j + 0.5) * sy) + 1
		for i = 0, mw - 3 do
			local solid = (tops[i] > 0 and wy >= tops[i])
			if solid then
				r:put(1 + i, 1 + j, "#", COL.top)
			elseif wy >= terrain.WATER_Y then
				r:put(1 + i, 1 + j, "~", COL.water)
			end
		end
	end

	-- 虫子：正在操作的那只画成 O（其余 @），一眼知道该看谁
	for _, w in ipairs(worms.list) do
		if w.alive then
			local i = math.max(0, math.min(mw - 3, math.floor(w.x / sx)))
			local j = math.max(0, math.min(mh - 1, math.floor(w.y / sy)))
			local col = team_color(C, w.team, true)
			r:put(1 + i, 1 + j, (w == current_worm()) and "O" or "@", col, COL.plate)
		end
	end

	-- 空中弹药也要看得见：地图若只画"人站在哪"，就说不清"炮弹正往哪飞"——
	-- 而 M 之所以不暂停，正是为了在弹药飞行途中也能看一眼全局
	for _, p in ipairs(projectiles) do
		local i = math.max(0, math.min(mw - 3, math.floor(p.x / sx)))
		local j = math.max(0, math.min(mh - 1, math.floor(p.y / sy)))
		r:put(1 + i, 1 + j, "*", C.white, COL.plate)
	end

	-- 空投箱：地图上标成 P。它是走位决策的一部分——"箱在哪、在不在我这边"
	-- 光看世界是看不出来的（箱子可能在屏幕外）
	if supply and supply.crate then
		local c = supply.crate
		local i = math.max(0, math.min(mw - 3, math.floor(c.x / sx)))
		local j = math.max(0, math.min(mh - 1, math.floor(c.y / sy)))
		r:put(1 + i, 1 + j, "P", C.green, COL.plate)
	end

	r:print(2, mh + 1,
	        string.format(t.map_info, turn.round, Hud.wind_text(turn.wind),
	                      t.side[turn.team] or t.side[1], #projectiles),
	        C.white)
end

-- 键位浮板：按 K 弹出来，居中在本卡带的可玩区里（不压到侧栏）
local function draw_help(C)
	local t = L()
	local px, py, pw, ph_ = phos.screen.playfield()
	local w, h = math.min(52, pw - 2), 22
	local x = px + math.floor((pw - w) / 2)
	local y = py + math.floor((ph_ - h) / 2)
	-- 浮窗要**整块不透明**，连边框那一圈也要：只填内框的话，边框上压着地形/天空，
	-- 浮窗就成了"半透明"的（与 M 地图浮窗不一致，也读不清）。所以先 clear 整块铺底，
	-- 再往上画边框与文字——与 draw_map_overlay 同一套做法（同样落在 overlay 层）
	local r = phos.ui.region(x, y, w, h, { layer = "overlay" })
	r:clear(C.white, COL.plate)
	box(r, t.help_title, C.white)
	r:print(2, 1, t.help_head, C.yellow)
	-- 键名列按**显示宽度**补齐："空格"（4 列）与 "SPACE"（5 列）都对齐到同一列
	local KEY_W = 7
	for i, line in ipairs(t.help) do
		r:print(2, 2 + i, phos.text.pad(line[1], KEY_W), C.white)
		r:print(3 + KEY_W, 2 + i, phos.text.fit(line[2], w - KEY_W - 5), C.gray)
	end
end

-- ================= 局域网大厅（phos.net，见 DESIGN.md §13） =================
-- menu.mode=="lan" 时模式菜单显示 昵称 / 创建 / 搜索 / 总览；选中后 screen=="lobby"，
-- 由 lan 表驱动面板。房主与加入者共用同一套房间面板（权限不同）。
-- **只做传输编排**：房间码 = 主机端口，房主广播名册，加入者按名册选队。
local LAN_CODE_MIN, LAN_CODE_MAX = 20000, 60000

local function nick()
	return (menu.field and menu.field.value) or ""
end

local function lan_blank(phase)
	return {
		phase = phase, host = false, code = 0, my_team = nil, pick_team = 1,
		caps = { 5, 5 }, hp = menu.hp, map = menu.map,
		create_row = 1, search = "", rooms = {}, room_sel = 1, refresh_t = 0,
		roster = {}, remote = {}, rstate = nil, err = "", start_req = nil, leave = false,
		pending = {}, -- 开局前收到的帧包（大厅阶段），开局时交给 mnet
	}
end

-- 名册：房主在自身前面补红队（房主默认红队），其余按 remote 里已入队的人
local function lan_build_roster(self)
	local list = { { peer = phos.net.self_id(), name = nick(), team = 1 } }
	for peer, info in pairs(self.remote) do
		if info.team then
			list[#list + 1] = { peer = peer, name = info.name, team = info.team }
		end
	end
	return list
end

local function lan_caps(self)
	return self.host and self.caps or ((self.rstate and self.rstate.caps) or { 5, 5 })
end
local function lan_hp(self)
	return self.host and self.hp or ((self.rstate and self.rstate.hp) or 100)
end
local function lan_map(self)
	return self.host and self.map or ((self.rstate and self.rstate.map) or 2)
end
local function lan_count(self, team)
	local n = 0
	for _, e in ipairs(self.roster) do if e.team == team then n = n + 1 end end
	return n
end
local function lan_full(self, team)
	return lan_count(self, team) >= lan_caps(self)[team]
end

-- 能否开局：两队各 ≥1 人，且**所有已连接的对端都已入队** —— 否则那个没选队的人会被落下。
-- 房主据此灰掉"开始游戏"，并给出原因（等待所有人入队）
local function lan_can_start(self)
	if not self.host then return false end
	local connected = #phos.net.peers()
	local teamed = lan_count(self, 1) + lan_count(self, 2) - 1 -- 名册里的对端数（减去房主自己）
	return connected <= teamed and lan_count(self, 1) >= 1 and lan_count(self, 2) >= 1
end

local function lan_host_state(self)
	local caps = self.caps
	phos.net.broadcast("wns.state",
	                   { caps = { caps[1], caps[2] }, hp = self.hp, map = self.map, code = self.code })
end
local function lan_host_roster(self)
	phos.net.broadcast("wns.roster", { list = self.roster })
end

-- 收包与连接事件：房主维护名册并广播；加入者按名册推断自己的队伍
local function lan_recv(self)
	for _, e in ipairs(phos.net.events()) do
		if self.host then
			if e.type == "connected" then
				self.remote[e.peer] = { name = "?", team = nil }
				lan_host_state(self)
				lan_host_roster(self)
			elseif e.type == "disconnected" then
				self.remote[e.peer] = nil
				self.roster = lan_build_roster(self)
				lan_host_roster(self)
			end
		elseif e.type == "disconnected" then
			self.leave = true -- 房主掉线 / 被断开：回家
		end
	end
	for _, m in ipairs(phos.net.poll()) do
		local d = m.data or {}
		if m.kind == "wns.state" then
			self.rstate = { caps = d.caps, hp = d.hp, map = d.map, code = d.code }
			if d.code then self.code = d.code end
		elseif m.kind == "wns.roster" then
			self.roster = d.list or {}
		elseif m.kind == "wns.join" and self.host then
			if not self.remote[m.from] then self.remote[m.from] = { name = "?" } end
			self.remote[m.from].name = d.name or "?"
			self.remote[m.from].team = (d.team and not lan_full(self, d.team)) and d.team or nil
			self.roster = lan_build_roster(self)
			lan_host_roster(self)
		elseif m.kind == "wns.leave" and self.host then
			-- 队员主动退出队伍（回到选队）：把他从名册里摘出那队，再广播
			if self.remote[m.from] then self.remote[m.from].team = nil end
			self.roster = lan_build_roster(self)
			lan_host_roster(self)
		elseif m.kind == "wns.start" then
			self.start_req = d
		elseif m.kind == "wns.in" and d.f then
			-- 开局前（大厅阶段）先到的帧包先存着：否则接收端会"错过第 0 帧"而卡死
			local pm = self.pending[m.from]
			if not pm then pm = {}; self.pending[m.from] = pm end
			pm[d.f] = d.k or {}
		end
	end
	-- 加入者：以名册为准认自己的队伍（房主可能把我放进别队 / 拒绝）
	if not self.host and self.phase == "room" then
		local me = phos.net.self_id()
		self.my_team = nil
		for _, e in ipairs(self.roster) do
			if e.peer == me then self.my_team = e.team end
		end
	end
end

local function lan_try_host(self)
	for _ = 1, 8 do
		local code = phos.sys.random(LAN_CODE_MIN, LAN_CODE_MAX)
		if phos.net.host({ port = code, name = nick() }) then
			self.host, self.code, self.my_team, self.remote = true, code, 1, {}
			self.roster = lan_build_roster(self)
			self.phase = "room"
			return true
		end
	end
	self.err = "no free port"
	return false
end

local function lan_try_join(self, room)
	if not phos.net.join(room.address, { port = room.port, name = nick() }) then
		self.err = "join failed"
		return false
	end
	self.host, self.code, self.my_team, self.pick_team = false, room.port, nil, 1
	self.phase = "room"
	return true
end

-- 名册 → 队伍 → 起局（联机）。**先播种、再随机**：两端用同一 seed，于是随机左右、
-- 地形、天气、补给、AI 决策逐位一致 —— 这是锁步的前提。
local function start_lan_match(p)
	mode = "lan"
	phos.sys.capture_escape(true) -- 对局中 Esc 归卡带：弹非暂停的菜单而非主机暂停
	if p.seed then phos.sys.seed(p.seed) end
	red_side = phos.sys.random(1, 2) -- 红蓝随机左右（两端同 seed 必得同值）
	-- 名册按颜色分组（roster 的 team：1=红 2=蓝）
	local by_color = { {}, {} }
	for _, e in ipairs(p.roster or {}) do
		local col = (e.team == 2) and 2 or 1
		by_color[col][#by_color[col] + 1] = e
	end
	-- 颜色 → 内部边号：红队落在 red_side，蓝队落在另一边
	local side_of_color = { red_side, (red_side == 1) and 2 or 1 }
	local players_of_side = { {}, {} }
	players_of_side[side_of_color[1]] = by_color[1]
	players_of_side[side_of_color[2]] = by_color[2]
	teams[1] = { count = math.max(1, #players_of_side[1]), human = true, ally_ai = false }
	teams[2] = { count = math.max(1, #players_of_side[2]), human = true, ally_ai = false }
	begin_game(p.hp or 100, p.map or 2)
	-- 分配 owner：Worms.new 已把队内出场顺序洗牌；该边的玩家按名册顺序逐个认领。
	-- 于是"每个人控制自己那只虫"，且站位 / 出场顺序都是随机的
	for side = 1, 2 do
		local ws = worms:of_team(side)
		local players = players_of_side[side]
		for i, wm in ipairs(ws) do
			wm.owner = players[i] and players[i].peer or nil
			wm.name = players[i] and players[i].name or nil -- 侧栏与顶栏显示用
		end
	end
	-- 联机对局状态：frame 帧号 + 每个对端每帧的输入包 + 需要等待的对端集合
	mnet = { frame = 0, sent = {}, remote = {}, peers = {} }
	for _, pr in ipairs(phos.net.peers()) do mnet.peers[pr.id] = true end
	-- 接收端若在"开局消息之前"就收到过行动方的帧包（大厅阶段），搬进来，避免错过第 0 帧
	for from, map in pairs(p.pending or {}) do mnet.remote[from] = map end
	-- 预置头 NET_DELAY 帧：延迟机制里没人会主动发这几帧（本机要到 frame=0 才发 frame+延迟），
	-- 这里补空包，否则开局头几帧等不到包、直接卡住。两端都补，于是所有人都有 0..延迟-1
	for f = 0, NET_DELAY - 1 do
		if not mnet.sent[f] then
			mnet.sent[f] = {}
			phos.net.broadcast("wns.in", { f = f, k = {} })
		end
	end
end

-- 模式菜单里的 LAN 分行（昵称在文件顶部、由 menu_lan_input 处理）
function menu_lan_input(dt)
	local C = phos.color
	if menu.nick_edit then
		menu.field:feed()
		if phos.input.pressed("start") then menu.nick_edit = false end
		return
	end
	local rows = { 1, 2, 3, 4, 5 }
	local function move(dir)
		local at = 1
		for i, rr in ipairs(rows) do if rr == menu.row then at = i end end
		menu.row = rows[((at - 1 + dir) % #rows) + 1]
		phos.audio.beep(420, 0.04, { wave = "square", volume = 0.14 })
	end
	if phos.input.pressed("up") then move(-1) end
	if phos.input.pressed("down") then move(1) end
	if menu.row == 1 and (phos.input.pressed("left") or phos.input.pressed("right")) then
		menu.mode = "pve"
		menu.row = 1
		phos.audio.beep(520, 0.04, { wave = "square", volume = 0.14 })
	end
	if phos.input.pressed("start") then
		if menu.row == 2 then menu.nick_edit = true
		elseif menu.row == 3 then lan_enter("create")
		elseif menu.row == 4 then lan_enter("search")
		elseif menu.row == 5 then lan_enter("overview") end
	end
end

function lan_enter(phase)
	-- 昵称是联机的"门牌"：空着不许进大厅（明确提示，不静默失败）
	if nick() == "" then
		menu.nick_err = true
		phos.audio.beep(160, 0.08, { wave = "square", volume = 0.18 })
		return
	end
	menu.nick_err = false
	lan = lan_blank(phase)
	screen = "lobby"
	phos.panel.resize(0)
	if phase == "overview" then
		lan.rooms = phos.net.discover(0.4)
	end
end

function lan_update(dt)
	local self = lan
	if not self then screen = "menu"; return end
	lan_recv(self)
	if self.leave then
		phos.net.stop(); lan = nil; screen = "menu"; return
	end
	if self.start_req then
		local p = self.start_req
		p.pending = self.pending -- 大厅阶段先到的帧包一并带进对局
		self.start_req = nil
		self.in_match, self.phase = true, "room" -- 保留大厅对象：赛后回到这个房间
		start_lan_match(p)
		return
	end

	local back = phos.input.text():find("\b") ~= nil
	local a = phos.input.pressed("start") -- 回车确认（A 是字母键，留给昵称输入）
	local l, r = phos.input.pressed("left"), phos.input.pressed("right")
	local u, d = phos.input.pressed("up"), phos.input.pressed("down")
	local function leave()
		phos.net.stop(); lan = nil; screen = "menu"
	end

	if self.phase == "create" then
		if d then self.create_row = math.min(5, self.create_row + 1) end
		if u then self.create_row = math.max(1, self.create_row - 1) end
		local step = (r and 1 or 0) - (l and 1 or 0)
		if step ~= 0 then
			if self.create_row == 1 then self.caps[1] = clamp_count(self.caps[1] + step)
			elseif self.create_row == 2 then self.caps[2] = clamp_count(self.caps[2] + step)
			elseif self.create_row == 3 then
				self.hp = math.max(HP_MIN, math.min(HP_MAX, self.hp + step * HP_STEP))
			elseif self.create_row == 4 then self.map = ((self.map - 1 + step) % #MAPS) + 1 end
		end
		if back then leave() return end
		if a and self.create_row == 5 then lan_try_host(self) end
	elseif self.phase == "search" then
		for digit in string.gmatch(phos.input.text(), "[0-9]") do
			if #self.search < 5 then self.search = self.search .. digit end
		end
		if back then
			if #self.search > 0 then self.search = self.search:sub(1, -2) else leave() return end
		end
		if a then
			self.err = ""
			local code = tonumber(self.search)
			local found
			for _, room in ipairs(phos.net.discover(0.4)) do
				if room.port == code then found = room break end
			end
			if found and not found.open then
				self.err = L().lan.in_game
			elseif found then
				lan_try_join(self, found)
			else
				self.err = L().lan.no_room
			end
		end
	elseif self.phase == "overview" then
		-- 回车=加入选中的房间，R=手动刷新；两者不能共用回车（会误触直接进房）
		self.refresh_t = self.refresh_t - dt
		if self.refresh_t <= 0 then
			self.refresh_t = 1.5
			self.rooms = phos.net.discover(0.12)
			if self.room_sel > #self.rooms then self.room_sel = math.max(1, #self.rooms) end
		end
		if phos.input.pressed("r") then
			self.refresh_t = 1.5
			self.rooms = phos.net.discover(0.3)
			phos.audio.beep(480, 0.03, { wave = "square", volume = 0.12 })
		end
		if d and #self.rooms > 0 then self.room_sel = math.min(#self.rooms, self.room_sel + 1) end
		if u then self.room_sel = math.max(1, self.room_sel - 1) end
		if back then leave() return end
		if a then
			local room = self.rooms[self.room_sel]
			if room and not room.open then
				self.err = L().lan.in_game
			elseif room then
				lan_try_join(self, room)
			end
		end
	elseif self.phase == "room" then
		if self.host then
			if back then leave() return end
			if a and lan_can_start(self) then
				phos.net.set_room({ open = false }) -- 开局后不再接受加入（搜索方会看到"游戏中"）
				local p = { hp = self.hp, map = self.map, caps = { self.caps[1], self.caps[2] },
				            roster = self.roster, seed = phos.sys.random(1, 999999999) }
				phos.net.broadcast("wns.start", p)
				self.start_req = p
			end
		elseif self.my_team then
			-- 已入队：退格**先退出队伍**（回到选队），再按一次才离开房间
			if back then
				phos.net.send(1, "wns.leave", {})
				self.pick_team, self.my_team = self.my_team, nil
				phos.audio.beep(360, 0.04, { wave = "square", volume = 0.14 })
			end
		else
			if back then leave() return end
			if l or r then self.pick_team = (self.pick_team == 1) and 2 or 1 end
			if a and not lan_full(self, self.pick_team) then
				phos.net.send(1, "wns.join", { team = self.pick_team, name = nick() })
			end
		end
	end
end

function lan_draw()
	local C = phos.color
	local lanT = L().lan
	local self = lan
	if not self then return end
	local px, py, pw, ph_ = phos.screen.playfield()
	local function panel(title, h)
		local w = math.min(58, pw - 4)
		local x = px + math.floor((pw - w) / 2)
		local y = py + math.floor((ph_ - h) / 2)
		local r = phos.ui.region(x, y, w, h)
		r:clear(C.white, COL.plate)
		box(r, title, C.white)
		return r, w
	end

	if self.phase == "create" then
		local r = panel(lanT.create_title, 14)
		local function opt(id, line, label, value)
			local sel = (self.create_row == id)
			r:print(2, line, string.format("%s %s < %s >", sel and ">" or " ",
				phos.text.pad(label, 10), value), sel and C.yellow or C.gray)
		end
		opt(1, 2, lanT.red_cap, self.caps[1])
		opt(2, 4, lanT.blue_cap, self.caps[2])
		opt(3, 6, L().label.hp, self.hp)
		opt(4, 8, L().label.map, L().map[MAP_KEYS[self.map]])
		r:print(2, 11, (self.create_row == 5 and "> " or "  ") .. lanT.start,
		        (self.create_row == 5) and C.yellow or C.gray)
		r:print(2, 13, lanT.disband, C.dark_gray)
		if self.err ~= "" then r:print(2, 12, self.err, C.red) end
	elseif self.phase == "search" then
		local r = panel(lanT.search_title, 9)
		r:print(2, 3, lanT.code_prompt .. ": " .. self.search .. "_", C.white)
		r:print(2, 5, self.err ~= "" and self.err or lanT.enter, self.err ~= "" and C.red or C.gray)
		r:print(2, 8, lanT.disband, C.dark_gray)
	elseif self.phase == "overview" then
		local r = panel(lanT.overview_title, 16)
		if #self.rooms == 0 then
			r:print(2, 3, lanT.no_room, C.gray)
		else
			for i, room in ipairs(self.rooms) do
				if i <= 11 then
					local sel = (i == self.room_sel)
					-- 开局后的房间标"游戏中"（暗一档、一眼可分）：看得到，但加入会被拒
					local open = room.open
					local tag = open and (tostring(room.players) .. lanT.players) or lanT.busy
					local col = sel and C.yellow or (open and C.white or C.dark_gray)
					r:print(2, 2 + i, string.format("%s %s  #%d  %s", sel and ">" or " ",
						room.name, room.port, tag), col)
				end
			end
		end
		r:print(2, 14, lanT.refresh, C.dark_gray)
		r:print(2, 15, lanT.disband, C.dark_gray)
	elseif self.phase == "room" then
		local r, w = panel(lanT.room_title .. " #" .. self.code, 18)
		local me = phos.net.self_id()
		local colw = math.floor((w - 3) / 2)
		local caps = lan_caps(self)
		r:print(2, 2, string.format("%s (%d/%d)", lanT.red, lan_count(self, 1), caps[1]), C.red)
		r:print(2 + colw, 2, string.format("%s (%d/%d)", lanT.blue, lan_count(self, 2), caps[2]), C.blue)
		local y1, y2 = 3, 3
		for _, e in ipairs(self.roster) do
			local line = e.name .. ((e.peer == me) and lanT.you or "")
			if e.peer == 1 then line = line .. " [" .. lanT.host_tag .. "]" end
			if e.team == 1 then r:print(2, y1, phos.text.fit(line, colw), C.white) y1 = y1 + 1
			else r:print(2 + colw, y2, phos.text.fit(line, colw), C.white) y2 = y2 + 1 end
		end
		if self.host then
			local connected = #phos.net.peers()
			local teamed = lan_count(self, 1) + lan_count(self, 2) - 1
			local ok = lan_can_start(self)
			r:print(2, 15, (ok and "> " or "  ") .. lanT.start, ok and C.yellow or C.gray)
			if not ok and connected > teamed then r:print(2, 16, lanT.wait_teams, C.dark_gray) end
			r:print(2, 17, lanT.disband, C.dark_gray)
		elseif not self.my_team then
			r:print(2, 15, lanT.join_hint, C.white)
			-- 左右选队要有**看得见的反馈**：当前选的那队用 ">" + 高亮，满员的暗一档
			local function team_opt(x, team)
				local sel = (self.pick_team == team)
				local full = lan_full(self, team)
				local name = (team == 1) and lanT.red or lanT.blue
				local col = (team == 1) and C.red or C.blue
				local label = (sel and ">" or " ") .. " " .. name .. (full and " (full)" or "  ")
				r:print(x, 16, label, full and C.dark_gray or (sel and C.yellow or col))
			end
			team_opt(2, 1)
			team_opt(2 + colw, 2)
			r:print(2, 17, lanT.leave, C.dark_gray)
		else
			local my = (self.my_team == 1) and lanT.red or lanT.blue
			r:print(2, 15, string.format(lanT.joined, my), C.white)
			r:print(2, 16, lanT.waiting, C.gray)
			r:print(2, 17, lanT.leave_team .. " / " .. lanT.leave, C.dark_gray)
		end
	end
end

-- 对局结束（分胜负）：留在房间里，房间重新开放给别人加入。连接不动，只收掉对局状态
function lan_match_over()
	mnet = nil
	netframe.active = false
	lan_pause = false
	phos.sys.capture_escape(false) -- 回到房间面板：Esc 交还主机
	winner = nil
	help_open = false
	map_open = false
	phos.audio.stop_music()
	phos.panel.resize(0)
	if not lan then
		phos.net.stop()
		screen = "menu"
		return
	end
	lan.in_match = false
	lan.phase, lan.err = "room", ""
	if lan.host then
		-- 剔除中途掉线的人，再刷新名册并重新开放房间
		for peer in pairs(lan.remote) do
			local alive = false
			for _, pr in ipairs(phos.net.peers()) do if pr.id == peer then alive = true end end
			if not alive then lan.remote[peer] = nil end
		end
		lan.roster = lan_build_roster(lan)
		lan_host_roster(lan)
		phos.net.set_room({ open = true })
	end
	screen = "lobby"
end

-- 联机对局的"菜单"浮层（**非暂停**）：继续游戏 / 退出房间
local function draw_lan_pause(C)
	local T = L().lan
	local px, py, pw, ph_ = phos.screen.playfield()
	local w, h = 30, 7
	local x = px + math.floor((pw - w) / 2)
	local y = py + math.floor((ph_ - h) / 2)
	local r = phos.ui.region(x, y, w, h, { layer = "overlay" })
	r:clear(C.white, COL.plate)
	box(r, T.paused_title, C.white)
	local mk = function(i) return (lan_pause_sel == i) and ">" or " " end
	r:print(3, 2, mk(1) .. " " .. T.resume, (lan_pause_sel == 1) and C.yellow or C.gray)
	r:print(3, 4, mk(2) .. " " .. T.leave_room, (lan_pause_sel == 2) and C.yellow or C.gray)
	r:print(3, 6, T.paused_hint, C.dark_gray)
end

local function draw_menu()
	local C, S = phos.color, r_base
	local t = L()
	-- 不刷底色：主机每帧已经把内容区填成**当前主题的底色**（还带显像管效果），
	-- 卡带再刷一层会连主题设置一起盖掉
	S:print(2, 1, "WORMS", C.yellow)
	S:print(2, 2, t.subtitle, C.gray)

	local px, py, pw, ph_ = phos.screen.playfield()
	local w, h = math.min(52, pw - 2), 17
	local x = px + math.floor((pw - w) / 2) + 1
	local y = py + math.floor((ph_ - h) / 2) + 1
	-- 窗口画在一块区域里（锚底层：菜单底下没有别的东西要叠，不必单占一层）
	local r = phos.ui.region(x - 1, y - 1, w, h)
	box(r, t.menu_title, C.white)
	local mark = function(row)
		return (menu.row == row) and ">" or " "
	end
	local hi = function(row)
		return (menu.row == row) and C.white or C.gray
	end
	-- 一行的样子固定为 `> 标签 < 值 >`：标签按**显示宽度**补到同一列，
	-- 所以"红队人数"（8 列）与"RED SQUAD"（9 列）排出来都是齐的。
	-- row(id, line, ...)：id 是逻辑行号（供 marker/高亮），line 是面板内的行——两者解耦，
	-- 于是 PVE / PVP 两种行序都能排成同一块稳定面板
	local LABEL_W = 12
	local function row(id, line, label, value)
		r:print(1, line,
		        string.format("%s %s < %s >", mark(id), phos.text.pad(label, LABEL_W), value),
		        hi(id))
	end
	local yn = function(b) return b and t.yes or t.no end

	if menu.mode == "lan" then
		-- 局域网：模式 / 昵称 / 创建 / 搜索 / 总览（开局与队设置都在大厅里）
		row(1, 1, t.label.mode, t.mode.lan)
		local nv = (nick() == "") and "—" or nick()
		row(2, 3, t.lan.nick, nv .. (menu.nick_edit and "|" or ""))
		r:print(1, 5, mark(3) .. " " .. t.lan.create, hi(3))
		r:print(1, 6, mark(4) .. " " .. t.lan.search, hi(4))
		r:print(1, 7, mark(5) .. " " .. t.lan.overview, hi(5))
		if menu.nick_err then
			r:print(1, 9, t.lan.nick_empty, C.red)
		end
	else
		-- 面板自上而下就是"上→下"的选择顺序：不再往选项之间塞解释文字，
		-- 一行一选项，视线顺着走即可（PvE 与 PvP 的行序各自连续）
		row(1, 1, t.label.mode, menu.mode == "pve" and t.mode.pve or t.mode.pvp)
		row(2, 3, t.label.red, menu.t1.count)
		if menu.mode == "pve" then
			row(4, 4, t.label.red_ai, yn(menu.t1.ally_ai))
			row(3, 5, t.label.blue, menu.t2.count)
			row(6, 6, t.label.map, t.map[MAP_KEYS[menu.map]])
			row(7, 7, t.label.hp, menu.hp)
			row(5, 8, t.label.diff, t.diff[DIFFS[menu.diff]] or DIFFS[menu.diff])
		else
			row(3, 4, t.label.red_ai, yn(menu.t1.ally_ai))
			row(4, 5, t.label.blue, menu.t2.count)
			row(5, 6, t.label.blue_ai, yn(menu.t2.ally_ai))
			row(6, 7, t.label.map, t.map[MAP_KEYS[menu.map]])
			row(7, 8, t.label.hp, menu.hp)
		end
		r:print(1, 10, string.format("%s %s", mark(8), t.start),
		        (menu.row == 8) and C.yellow or C.gray)
	end
	r:print(3, 15, phos.text.fit(t.menu_hint, w - 4), C.dark_gray)
end

function draw()
	local C, S = phos.color, phos.screen
	if screen == "lobby" then
		lan_draw()
		return
	end
	if screen == "menu" then
		draw_menu()
		return
	end
	-- 底层：天空与地形照旧直接写 screen（这一层由主机画、也由主机清）
	draw_sky(r_base, C)
	draw_world(r_base, C)
	-- 前景一层：特效、瞄准、角色、雨雪。它们之间的先后仍在代码里（同一层内先写先叠），
	-- 只是整体压在世界之上——这样"谁在谁上面"就不必再靠注释互相提醒
	draw_effects(r_fx, C)
	-- 瞄准线、预测线、力度读数只在"轮到我、还没开炮"时出现：一发射立刻收掉，
	-- 免得玩家盯着上一炮的刻度去瞄下一炮。
	-- 它画在**角色之前**：高抛时线会穿过自己的头顶，压在血条与选标下面才不会糊成一团
	if turn.phase == "aim" and human_turn() and not winner then
		draw_aim(r_aim, C)
	end
	draw_actors(r_actors, C)
	-- 风痕与雨雪画在**角色之后**：它们是前景，要落在人与地形之上；日月云星留在地形之前，
	-- 于是它们天然只出现在山坡上方的空处，不必逐格判断。
	-- "雨滴落在地形上"能同格共存：层是**像素级**叠上去的（见 Renderer::draw_layers），
	-- 笔画之外透出地形，两种内容能同格共存
	weather:draw_wind(r_weather, C, turn.wind)
	weather:draw_precip(r_weather, C)
	-- 闪电不在这里：它与日月云同属**天空那一趟**（世界底层、地形之前），
	-- 所以山体会挡住它 —— 画在天气层上它会"照亮"山体与虫子，那是滤镜不是闪电

	local w = current_worm()
	local weapon = selected_weapon()
	local left = (weapon and w and w.ammo[weapon.id]) or 0
	-- 信息栏不铺底（见 hud.lua）：它是独立一层，按像素压在世界上，笔画之外透出世界
	Hud.draw(r_hud, C, {
		worm = w,
		wind = turn.wind,
		time_text = turn:time_text(),
		round = turn.round,
		phase = turn.phase,
		shots_left = turn.shots_left,
		weapon = weapon,
		plate = nil, -- 浮层底板一律不用（见 draw_actors 与读数处的说明）
		ammo = left,
		charge = charge_mode,
		turn_team = turn.team,
		red_side = red_side,
		human = human_turn(),
		floats = floats,
		-- 只在弹药真的在空中时提示；特效阶段（燃烧/光柱）显示"飞行中"会让玩家以为卡住
		flight_note = (#projectiles > 0 or burst) and L().flying or nil,
		-- 第 1 行右端：游戏内时钟（24 小时制）与天气。天气与时间都是**读出来的**，
		-- 所以这里只递三个值，不在这里拼字符串
		clock = weather:clock_text(),
		weather = weather:name(),
		weather_tone = weather:tone(C),
	})

	if winner then
		local t = L()
		-- 居中要按**显示宽度**算：`#msg` 数的是字节，中文/混排会被推到偏左
		local msg = (t.win[winner] or t.win[1]) .. "   " .. t.win_hint
		-- 横幅压在读数层上（底色是实的，所以它盖得住下面的一切）
		r_hud:print(VIEW_CW // 2 - phos.text.width(msg) // 2, VIEW_CH // 2, msg, C.white,
		            phos.color.black)
	end

	Panel.draw({
		terrain = terrain,
		camera = camera,
		worms = worms,
		turn = turn,
		teams = teams,
		red_side = red_side,
		weapons = Weapons.LIST,
		current = weapon,
		active = w,
		human = human_turn(),
		-- 每只虫归谁操作由这里一处判定（与对局逻辑同源）；侧栏据此画 * / A 记号
		human_of = worm_is_human,
		hp_max = Worms.MAX_HP,
	})
	if map_open then
		draw_map_overlay(C)
	end
	if help_open then
		draw_help(C)
	end
	-- 联机对局的 Esc 菜单（非暂停）：压在最上面
	if mnet and lan_pause then
		draw_lan_pause(C)
	end
end

-- agent / 自测观察口。
-- 注意：菜单态下这局还没开始，projectiles 之类的容器都还是 nil，
-- 所以一律用 `(x or {})` 取值——观察口自己抛异常，agent 就什么都看不到了。
-- 逐只速查见下面的 `units`：位置、血量、瞄准、归谁操作与队长标记都在里面
function debug_state()
	local w = current_worm()
	local list = (worms and worms.list) or {}
	local spec = selected_weapon()
	-- 站位与出场顺序：按 list 顺序（= 出场顺序）列出该队每只虫的 x。
	-- 两者都是随机的（见 Worms.new）：这串数字不是升序就说明洗牌生效了
	local function order_text(team)
		local parts = {}
		for _, m in ipairs(list) do
			if m.team == team and m.alive then
				parts[#parts + 1] = tostring(math.floor(m.x))
			end
		end
		return table.concat(parts, ",")
	end
	-- 侧栏血条现在按"队 + 血量档"上色（见 panel.lua）：把档位名报出来，
	-- 自测就能直接读到"哪只虫在哪一档"，不必对着像素猜颜色
	local function tones(team)
		local parts = {}
		local max_hp = (Worms.MAX_HP > 0) and Worms.MAX_HP or 100
		for _, m in ipairs(list) do
			if m.team == team and m.alive then
				parts[#parts + 1] = Panel.hp_tone_name((team == red_side) and 1 or 2, m.hp / max_hp)
			end
		end
		return table.concat(parts, ",")
	end
	-- 当前虫子的**限量弹**底账（观察口用）：还剩几件、共几发。
	-- "AI 偏爱普通炮弹"这种话要靠这两个数说话：剩得多却选普通弹才是真问题
	local lt_types, lt_shots = 0, 0
	if w and w.ammo then
		for _, spec in ipairs(Weapons.LIST) do
			local n = w.ammo[spec.id] or 0
			if n > 0 then
				lt_types = lt_types + 1
				lt_shots = lt_shots + n
			end
		end
	end
	local out = {
		screen = screen,
		mode = mode,
		help = help_open,
		red_count = teams[1].count,
		blue_count = teams[2].count,
		red_human = teams[1].human and 1 or 0,
		blue_human = teams[2].human and 1 or 0,
		red_ally_ai = teams[1].ally_ai and 1 or 0,
		blue_ally_ai = teams[2].ally_ai and 1 or 0,
		-- 局域网大厅实况（agent/自测用）：阶段 / 是否房主 / 房间码 / 我的队伍 / 名册人数
		lan_phase = lan and lan.phase or "-",
		lan_host = (lan and lan.host) and 1 or 0,
		lan_code = lan and lan.code or 0,
		lan_team = lan and (lan.my_team or 0) or 0,
		lan_players = lan and #lan.roster or 0,
		net_frame = mnet and mnet.frame or -1, -- 联机：已推进的逻辑帧号（两端应一致）
		lan_paused = lan_pause and 1 or 0,     -- 联机对局的 Esc 菜单是否打开
		map = MAP_KEYS[menu.map] or "-",   -- 本局地图宽窄档位（世界宽度见 world_w）
		menu_row = menu.row,
		menu_mode = menu.mode,
		hp_max = menu.hp,
		diff = DIFFS[menu.diff] or "normal",
		ai_reason = ai_reason or "-",
		ai_walking = ai_walk_t > 0,
		ai_repositioned = ai_repositioned,
		ai_last = ai_last,
		limited_types = lt_types,
		limited_shots = lt_shots,
		map_open = map_open,
		burst_left = burst and (burst.total - burst.done) or 0,
		strikes = #strikes,
		-- 雷：闪光还剩多少毫秒、这一道折线有几行、起点在第几列。
		-- 报出来才能核对"闪电真的画在天空那一趟、形状在这一闪里固定"
		flash_ms = weather and math.floor((weather.flash or 0) * 1000) or 0,
		bolt_rows = (weather and weather.bolt) and #weather.bolt or 0,
		bolt_x = (weather and weather.bolt and weather.bolt[1]) and weather.bolt[1].x or -1,
		-- 光柱的列边界（世界子格）与柱尖：画、挖、伤人共用这一对边界，
		-- 报出来就能核对"看得见的宽度 == 打得动的宽度"
		strike_x0 = (strikes[1] and strikes[1].x0) or -1,
		strike_x1 = (strikes[1] and strikes[1].x1) or -1,
		strike_tip = (strikes[1] and math.floor(strikes[1].tip)) or -1,
		-- 天气 / 时钟 / 补给 / 阵亡爆炸：新加的四样都要能在观察口里读到，
		-- 否则"天气转了没有、箱子落下来没有"就只能靠眼看
		weather = weather and weather.state or "-",
		climate = weather and weather.climate or "-",
		clock = weather and weather:clock_text() or "--:--",
		supply = (supply and supply.crate) and (supply.crate.landed and "down" or "air") or "-",
		supply_x = (supply and supply.crate) and math.floor(supply.crate.x) or -1,
		supply_w = (supply and supply.crate) and supply.crate.spec.id or "-",
		supplies_taken = supplies_taken,
		supply_last = supply_last,
		death_blasts = death_blasts,
		order1 = order_text(1),
		order2 = order_text(2),
		tones1 = tones(1),
		tones2 = tones(2),
		strike_x = strike_dbg and strike_dbg.x or -1,
		strike_top0 = strike_dbg and strike_dbg.top0 or -1,
		strike_top = (strike_dbg and terrain) and surface_at(strike_dbg.x) or -1,
		-- 浮字：条数与最后一条的内容（有文字用文字，纯伤害就把数字拼出来）。
		-- "报账准不准"靠它验，所以数字必须能读出来，不能只报"-"
		floats = #(floats or {}),
		float_last = (function()
			local f = floats and floats[#floats]
			if not f then
				return "-"
			end
			return f.text or ("-" .. tostring(math.floor((f.damage or 0) + 0.5)))
		end)(),
		team = turn and turn.team or 0,
		phase = turn and turn.phase or "-",
		wind = turn and turn.wind or 0,
		round = turn and turn.round or 0,
		shots_left = turn and turn.shots_left or 0,
		winner = winner,
		alive1 = worms and worms:alive_count(1) or 0,
		alive2 = worms and worms:alive_count(2) or 0,
		projectiles = #(projectiles or {}),
		charge = charge_mode,
		-- 相机原点（世界子格）：核对"世界 → 屏幕"换算要看它 —— 原点是奇数时，
		-- 世界的格边界落在屏幕格正中，画与挖最容易在这里差半格
		cam_x = math.floor(cam.x),
		cam_y = math.floor(cam.y),
		cam_pan = math.floor(cam.pan),
		cam_pan_y = math.floor(cam.pan_y),
		-- 相机原点的实际 y（子格）。纵向平移与边缘夹紧都要看它，不是看意图值
		cam_top = camera and math.floor(camera.y) or -1,
		tp_angle = tp_info.angle or 0,
		tp_facing = tp_info.facing or 0,
		tp_dist = tp_info.dist or 0,
		tp_tried = tp_info.tried or 0,
		tp_bounds = tp_info.bounds or "-",
		tp_tx = tp_info.tx or 0,
		tp_ty = tp_info.ty or 0,
		tp_gx = tp_info.gx or -1,
		tp_gy = tp_info.gy or -1,
		lg_x = laser_dbg.x or 0,
		lg_y = laser_dbg.y or 0,
		lg_fx = laser_dbg.fx or -1,
		lg_fy = laser_dbg.fy or -1,
		lg_dx = laser_dbg.dx or -1,
		lg_hits = laser_dbg.hits or 0,
		weapon = spec and spec.id or "",
		ammo = (spec and w and w.ammo and w.ammo[spec.id]) or 0,
		human = human_turn(),
	}
	if w then
		out.worm_x, out.worm_y = math.floor(w.x), math.floor(w.y)
		out.angle, out.power, out.hp = math.floor(w.angle), math.floor(aim_power * 100), math.floor(w.hp)
		out.worm_team = w.team
		for i, m in ipairs(list) do
			if m == w then
				out.worm_id = i
			end
		end
	end
	out.hp1, out.hp2 = {}, {}
	for _, m in ipairs(list) do
		local side = (m.team == 1) and out.hp1 or out.hp2
		side[#side + 1] = m.alive and math.floor(m.hp) or -1
	end
	-- 每只虫**逐只**的位置与状态。算弹道、判命中都要 (x, y)：只给 x 的话，调用方
	-- 想知道炮弹落在哪就得去读地图反推地形，又慢又不准。数组顺序 =
	-- 出场顺序 = worm_id/order1/order2 的下标，于是"第 i 只虫"在所有字段里指的是同一只。
	-- ground 是它脚下那一列的地表高度：炮口与落点都以它为基准，比"只给个 y"更好用
	out.units = {}
	for i, m in ipairs(list) do
		out.units[#out.units + 1] = {
			id = i,
			team = m.team,
			alive = m.alive,
			x = math.floor(m.x),
			y = math.floor(m.y),
			ground = surface_at(math.floor(m.x)),
			hp = m.alive and math.floor(m.hp) or -1,   -- 与 hp1/hp2 同口径：阵亡报 -1
			angle = math.floor(m.angle or 0),
			facing = m.facing or 0,
			power = math.floor((m.power or 0) * 100),  -- AI 的虫可能还没存过力度
			human = worm_is_human(m) and 1 or 0,       -- 归谁操作：1 = 玩的人，0 = 电脑
			buried = m.buried and 1 or 0,              -- 身体在土里（被埋住）：走不动跳不动，只能炸开
			leader = (captains[m.team] == m) and 1 or 0, -- 队长：本队"队友交给 AI"时唯一还归玩家的
		}
	end
	-- 地表剖面：每 GROUND_STEP 个子格取一次高度。**这是让 agent 能自己瞄准的那一项** ——
	-- 光有双方坐标还不够，还得知道中途中地形多高，否则算不出炮弹会不会撞山、落在哪
	-- 与 units 同样是数组：深度 4 序列化下，
	-- 纯数组就是真正的 JSON 数组，agent 直接当列表读
	local GROUND_STEP = 8
	out.ground_step = GROUND_STEP
	out.ground = {}
	if terrain then
		for gx = 0, terrain.W - 1, GROUND_STEP do
			out.ground[#out.ground + 1] = surface_at(gx)
		end
	end
	-- 世界尺寸 + 各队 x 的跨度。字段名直说是什么：宽度就是宽度、队别就是队别 ——
	-- 名字骗人比没有字段更糟（这一组是 agent 算弹道要用的，读错一个字就全盘错）
	out.world_w, out.world_h = terrain and terrain.W or 0, terrain and terrain.H or 0
	local function x_span(team)
		local lo, hi = nil, nil
		for _, m in ipairs(list) do
			if m.team == team and m.alive then
				lo = (lo == nil) and m.x or math.min(lo, m.x)
				hi = (hi == nil) and m.x or math.max(hi, m.x)
			end
		end
		return math.floor(lo or -1), math.floor(hi or -1)
	end
	out.team1_x_min, out.team1_x_max = x_span(1)
	out.team2_x_min, out.team2_x_max = x_span(2)
	return out
end

-- main.lua —— 入口：装配模块、把输入翻成"意图"、把状态画出来。
-- 规则全在 game.lua（它不读键、不画、不出声）；这里只做三件事。
--
-- 操作（DESIGN §7）：方向键移光标 / A 建或升级 / B 取消 / Z X 上·下一个塔型 /
-- C 空袭 / D 拆除 / P 切优先级 / 空格 提前放波 / , . 调速 / 退格 回菜单 / Enter 暂停。
-- 所有提示用 phos.input.key_name 求真键名，不写死手柄叫法。

local Game = require("game")
local View = require("view")
local Hud = require("hud")
local Panel = require("panel")
local Sfx = require("sfx")
local Music = require("music")
local Towers = require("towers")

local PANEL_W = 22

-- 菜单行号登记表：每一项都是一个可选行（漏登记 = 那一行永远选不到，DESIGN §5.0）。
-- 用命名常量而不是裸数字，改行序时只改这里。
menu_rows = { DIFF = 1, MAP = 2, ENDLESS = 3, START = 4 }

local Text = {
	zh = {
		title = "磁芯防线",
		subtitle = "砌塔成迷宫 · 拉电供能 · 挡住 20 波",
		diff = "难度", map = "地图", start = "开始",
		endless = "无尽模式", on = "开", off = "关",
		hint = "上下选择   左右调整   A/回车 开始",
		over = "磁芯失守", won = "防线守住！",
		again = "按 %s 重开（新地图）",
		paused = "暂停", footer = "最高波次 %d   胜场 %d   最高分 %d",
		help_title = "键位", help_close = "按 %s 关闭", hint_k = "键位表",
		-- 每行：键组（虚拟键名，渲染时才经 phos.input.key_name 求真键名）+ 说明。
		help = {
			{ { "left", "right", "up", "down" }, "移动光标" },
			{ { "a" }, "建造 / 升级（塔上）" },
			{ { "z" }, "上一个塔型" },
			{ { "x" }, "下一个塔型" },
			{ { "d" }, "拆除（返还 60%）" },
			{ { "c" }, "空袭（冷却 40s）" },
			{ { "space" }, "提前放波（战斗中也能，场上最多两波）" },
			{ { "comma", "period" }, "减速 / 加速" },
			{ { "p" }, "切目标优先级" },
			{ { "k" }, "本帮助（同时暂停）" },
			{ { "start" }, "暂停 / 继续" },
			{ { "backspace" }, "返回选择菜单（结算）" },
			{ { "escape" }, "返回卡带架" },
		},
		diff_names = { EASY = "简单", NORMAL = "普通", HARD = "困难" },
		map_names = { OPEN = "开阔", CANALS = "水道", MAZE = "迷宫", RANDOM = "随机" },
	},
	en = {
		title = "CORE LINE",
		subtitle = "Build towers into a maze, power them, survive 20 waves",
		diff = "DIFFICULTY", map = "MAP", start = "START",
		endless = "ENDLESS", on = "ON", off = "OFF",
		hint = "UP/DOWN select   LEFT/RIGHT change   A/ENTER start",
		over = "CORE DESTROYED", won = "LINE HELD!",
		again = "press %s to restart (new map)",
		paused = "PAUSED", footer = "BEST WAVE %d   WINS %d   SCORE %d",
		help_title = "CONTROLS", help_close = "press %s to close", hint_k = "CONTROLS",
		help = {
			{ { "left", "right", "up", "down" }, "move cursor" },
			{ { "a" }, "build / upgrade (on tower)" },
			{ { "z" }, "previous tower type" },
			{ { "x" }, "next tower type" },
			{ { "d" }, "sell (refund 60%)" },
			{ { "c" }, "airstrike (40s cd)" },
			{ { "space" }, "early wave (also mid-fight; max 2 waves)" },
			{ { "comma", "period" }, "slower / faster" },
			{ { "p" }, "cycle target priority" },
			{ { "k" }, "this help (pauses too)" },
			{ { "start" }, "pause / resume" },
			{ { "backspace" }, "back to menu (settles)" },
			{ { "escape" }, "back to shelf" },
		},
		diff_names = { EASY = "EASY", NORMAL = "NORMAL", HARD = "HARD" },
		map_names = { OPEN = "OPEN", CANALS = "CANALS", MAZE = "MAZE", RANDOM = "RANDOM" },
	},
}

local MAPS = { "OPEN", "CANALS", "MAZE", "RANDOM" }

local cart
local menu
local game
local mode = "menu" -- menu / play
local paused = false
local help_open = false -- K 键位表（开着时整局冻结）
local SPEED_MAX = 3 -- 速度档位：1× / 2× / 3×（DESIGN §7）
local speed = 1
-- 存档纪录（init 读一次，常驻内存；只在刷新时写盘）
local best_wave, wins, best_score

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end

-- 存盘只在**刷新纪录 / 改设置**时发生，不每帧 IO（DESIGN §9）
local function bump_best_wave(w)
	if w > best_wave then
		best_wave = w
		phos.save.write("best_wave", tostring(best_wave))
	end
end

-- 结算当前分数（峰值金币 + 波数×100）：**每帧算一遍**，只在刷新纪录时落盘。
-- 这样"拔出卡带"（主机直接销毁卡带、不再调用 update）与阵亡走同一条路——
-- 半途退出的一局也照算进最高分，不必等某一波清完（DESIGN §9）。
local function settle_score()
	local sc = game.peak_credits + game.wave * 100
	if sc > best_score then
		best_score = sc
		phos.save.write("best_score", tostring(best_score))
	end
end

-- 退格：回选择菜单（"直接结算"）。settle_score 每帧都在跑，分数已经记下，这里只切模式。
-- 与"拔卡退出"同一条路——半途回菜单的一局也照算最高分。
local function to_menu()
	mode = "menu"
	paused = false
	help_open = false
	game = nil
	phos.panel.resize(0) -- 菜单不需要侧栏
end

local function new_game()
	phos.panel.resize(PANEL_W) -- 对局需要侧栏
	-- 开局即把"上次难度/地图"写盘（DESIGN §9：菜单确认时写）
	phos.save.write("diff", menu.diff)
	phos.save.write("map", menu.map)
	phos.save.write("endless", menu.endless and "1" or "0")
	game = Game.new(menu.diff, menu.map, menu.endless)
	mode = "play"
	paused = false
	help_open = false
	phos.audio.music(Music)
end

function init()
	cart = phos.cart.info()
	phos.panel.resize(0) -- 菜单不需要侧栏：留着会压住标题
	best_wave = tonumber(phos.save.read("best_wave") or "0") or 0
	wins = tonumber(phos.save.read("wins") or "0") or 0
	best_score = tonumber(phos.save.read("best_score") or "0") or 0
	speed = clamp(tonumber(phos.save.read("speed") or "1") or 1, 1, SPEED_MAX)
	local diff = phos.save.read("diff") or "NORMAL"
	if not ({ EASY = true, NORMAL = true, HARD = true })[diff] then diff = "NORMAL" end
	local map = phos.save.read("map") or "RANDOM"
	if not ({ OPEN = true, CANALS = true, MAZE = true, RANDOM = true })[map] then map = "RANDOM" end
	-- 无尽模式沿用上次选择（"1"/"0"）；与 best_wave/best_score 共用一格纪录，不另开键
	local endless = (phos.save.read("endless") == "1")

	menu = { row = menu_rows.DIFF, diff = diff, map = map, endless = endless }

	-- 把几个关键旋钮挂到 `~` 调试台（DESIGN §12 第三刀）：边打边调
	local PACING = { zh = "节奏", en = "PACING" }
	phos.debug.number({ zh = "布防时长(秒)", en = "Build time (s)" },
		function() return Game.BUILD_TIME end, function(v) Game.BUILD_TIME = v end,
		{ min = 3, max = 600, step = 1, group = PACING })
	phos.debug.integer({ zh = "起始金币", en = "Start credits" },
		function() return Game.START_CREDITS end, function(v) Game.START_CREDITS = v end,
		{ min = 0, max = 10000, step = 50, group = PACING })
	phos.debug.number({ zh = "敌人血量x", en = "Enemy HP x" },
		function() return Game.ENEMY_HP_MULT end, function(v) Game.ENEMY_HP_MULT = v end,
		{ min = 0.1, max = 10, step = 0.1, group = PACING })
	phos.debug.number({ zh = "空袭伤害", en = "Airstrike dmg" },
		function() return Game.AIRSTRIKE_DMG end, function(v) Game.AIRSTRIKE_DMG = v end,
		{ min = 0, max = 1000, step = 10, group = PACING })
	local GRP = { zh = "塔伤害", en = "TOWER DMG" }
	for _, name in ipairs(Towers.ORDER) do
		local d = Towers.TYPES[name]
		if d.dmg and d.dmg > 0 then
			phos.debug.number(name, function() return d.dmg end,
				function(v) d.dmg = v end,
				{ min = 0, max = 300, step = 1, group = GRP })
		end
	end

	game = nil
	mode = "menu"
end

-- ── 输入 ─────────────────────────────────────────────────────────────

local DIRKEYS = { { "left", -1, 0 }, { "right", 1, 0 }, { "up", 0, -1 }, { "down", 0, 1 } }
local MOVE_INIT, MOVE_REPEAT = 0.20, 0.055
local move_timer = 0

-- 光标移动：点一下走一格，按住加速连走（与菜单同一套）。
local function cursor_input(dt, x0, y0, x1, y1)
	local moved = false
	for _, k in ipairs(DIRKEYS) do
		if phos.input.pressed(k[1]) then
			game.cx = clamp(game.cx + k[2], x0, x1)
			game.cy = clamp(game.cy + k[3], y0, y1)
			move_timer = MOVE_INIT
			moved = true
		end
	end
	if not moved then
		local ldx, ldy, any = 0, 0, false
		for _, k in ipairs(DIRKEYS) do
			if phos.input.down(k[1]) then any, ldx, ldy = true, k[2], k[3] end
		end
		if any then
			move_timer = move_timer - dt
			while move_timer <= 0 do
				game.cx = clamp(game.cx + ldx, x0, x1)
				game.cy = clamp(game.cy + ldy, y0, y1)
				move_timer = move_timer + MOVE_REPEAT
			end
		else
			move_timer = 0
		end
	end
end

-- 调速：循环而非夹紧（DESIGN §7）。夹紧时"到顶后再按 ."会静默无效，玩家以为按键坏了；
-- 循环让每次按键都有反馈，再配一声短促提示音把"手感"落到实处。
local function set_speed(v)
	speed = ((v - 1) % SPEED_MAX) + 1
	phos.save.write("speed", tostring(speed))
	phos.audio.beep(520 + speed * 140, 0.05, { wave = "square", volume = 0.14 })
end

local function game_input(dt)
	local g = game
	cursor_input(dt, 1, 1, g.MW - 2, g.MH - 2)

	if phos.input.pressed("a") then
		local t = g:tower_at(g.cx, g.cy)
		local ok
		if t then
			ok = g:upgrade(g.cx, g.cy) -- 塔上按 A = 升级
			if ok then g.ev.upgraded = true end
		else
			ok = g:build(g.cx, g.cy) -- 空地上按 A = 按当前塔型建造
			if ok then g.ev.built = true end
		end
		if not ok then g.ev.denied = true end -- 金币不足 / 会堵死路：给个"拒绝"反馈
	end
	if phos.input.pressed("d") then
		if g:sell(g.cx, g.cy) then g.ev.sold = true end
	end
	-- X 下一个 / Z 上一个：只切"待建造"塔型，不动光标下的塔。
	if phos.input.pressed("x") then
		g.build_index = (g.build_index % #Towers.ORDER) + 1
	end
	if phos.input.pressed("z") then
		g.build_index = ((g.build_index - 2) % #Towers.ORDER) + 1
	end
	if phos.input.pressed("p") then
		g:cycle_priority(g.cx, g.cy)
	end
	if phos.input.pressed("c") then
		g:airstrike()
	end
	if phos.input.pressed("space") then
		-- 提前放波：布防期拿奖金；战斗中也行（场上最多两拨，超了会被拒绝）。给一声反馈音。
		local ok = g:early_wave()
		phos.audio.beep(ok and 760 or 180, 0.06, { wave = ok and "square" or "saw", volume = 0.12 })
	end
	if phos.input.pressed("comma") then set_speed(speed - 1) end
	if phos.input.pressed("period") then set_speed(speed + 1) end
end

local function menu_input(dt)
	local DIFFS = { "EASY", "NORMAL", "HARD" }
	local MENU_ROWS = { menu_rows.DIFF, menu_rows.MAP, menu_rows.ENDLESS, menu_rows.START }
	local n = #MENU_ROWS
	-- 上下在**登记的**行之间循环
	local at = 1
	for i, r in ipairs(MENU_ROWS) do if r == menu.row then at = i end end
	if phos.input.pressed("up") then menu.row = MENU_ROWS[((at - 2) % n) + 1] end
	if phos.input.pressed("down") then menu.row = MENU_ROWS[(at % n) + 1] end

	local step = 0
	if phos.input.pressed("left") then step = -1 end
	if phos.input.pressed("right") then step = 1 end
	if step ~= 0 then
		if menu.row == menu_rows.DIFF then
			local i = 1
			for k, d in ipairs(DIFFS) do if d == menu.diff then i = k end end
			menu.diff = DIFFS[((i - 1 + step) % #DIFFS) + 1]
			phos.save.write("diff", menu.diff)
		elseif menu.row == menu_rows.MAP then
			local i = 1
			for k, m in ipairs(MAPS) do if m == menu.map then i = k end end
			menu.map = MAPS[((i - 1 + step) % #MAPS) + 1]
			phos.save.write("map", menu.map)
		elseif menu.row == menu_rows.ENDLESS then
			menu.endless = not menu.endless
			phos.save.write("endless", menu.endless and "1" or "0")
		end
	end

	if phos.input.pressed("a") or phos.input.pressed("start") then
		new_game()
	end
end

function update(dt)
	if mode == "menu" then
		menu_input(dt)
		return
	end

	-- 每帧结算当前分：拔卡退出的一局也算数（见 settle_score），与暂停/结束态无关
	settle_score()

	-- 退格：回选择菜单（直接结算）。放在最前，暂停/帮助/结束态下都能用
	if phos.input.pressed("backspace") then
		to_menu()
		return
	end

	-- 结束态：按 A 以新 seed 重开（DESIGN §3）
	if game.phase == "won" or game.phase == "over" then
		if phos.input.pressed("a") then
			phos.sys.seed(phos.sys.random(1, 1000000000)) -- 换一张图
			new_game()
		end
		return
	end

	-- K：键位表（开着时整局冻结）。不收起侧栏——像地牢那张的帮助浮窗一样摊在游戏区中央
	if phos.input.pressed("k") then help_open = not help_open end
	if help_open then return end

	if phos.input.pressed("start") then paused = not paused end
	if paused then
		-- 暂停浮层里只认"继续"：start 在上一行已把自己的暂停翻回来，B 也在此收尾。
		-- （原来把 B/start 的恢复逻辑留在 game_input 里，而暂停时 game_input 根本不跑 → 永久卡死）
		if phos.input.pressed("b") then paused = false end
		return
	end

	game_input(dt)
	local ev = game:update(dt * speed)
	Sfx.play(ev)

	-- 事件 → 存档（只在刷新时写盘）
	if ev.wave_start then bump_best_wave(game.wave) end
	if ev.wave_clear then
		bump_best_wave(game.wave)
	end
	if ev.won then
		wins = wins + 1
		phos.save.write("wins", tostring(wins))
		bump_best_wave(game.wave_total)
	end
	if ev.over then bump_best_wave(game.wave) end
end

-- ── 绘制 ─────────────────────────────────────────────────────────────

local function draw_menu(C)
	local S = phos.screen
	local t = phos.lang.dict(Text)
	S.clear()
	local w, h = S.size()
	local mid = math.floor(w / 2)

	local function center(y, text, col, scale)
		local tw = phos.text.width(text) * (scale or 1)
		S.print(mid - math.floor(tw / 2), y, text, col, nil, scale)
	end

	center(6, t.title, C.yellow, 3)
	center(10, t.subtitle, C.gray)

	local rows = {
		{ t.diff, t.diff_names[menu.diff] or menu.diff },
		{ t.map, t.map_names[menu.map] or menu.map },
		{ t.endless, menu.endless and t.on or t.off },
		{ t.start, "" },
	}
	local top = 16
	for i, r in ipairs(rows) do
		local y = top + (i - 1) * 3
		local mark = (i == menu.row) and ">" or " "
		local label = string.format("%s %s", mark, phos.text.pad(r[1], 12))
		if i == #rows then
			center(y, r[1], (i == menu.row) and C.yellow or C.white, 2)
		else
			S.print(mid - 14, y, label, (i == menu.row) and C.yellow or C.white)
			S.print(mid + 2, y, r[2], (i == menu.row) and C.cyan or C.gray)
		end
	end
	center(h - 4, t.hint, C.dark_gray)
	center(h - 2, string.format(t.footer, best_wave, wins, best_score), C.dark_gray)
end

-- 不透明浮窗：先铺底板盖住世界，再画边框与居中文字。
-- ui.frame 只画边框不铺底（卡带浮窗默认保留背景），所以要挡世界必须自己先铺。
-- **只在游戏区居中**：侧栏不属于游戏画面，拿整个内容区居中会偏到侧栏上。
local function overlay(C, title, line1, line2)
	local S = phos.screen
	local px, py, pw, ph = S.playfield()
	local bw, bh = 36, 6
	local bx = px + math.floor((pw - bw) / 2)
	local by = py + math.floor((ph - bh) / 2)
	local r = phos.ui.region(bx, by, bw, bh)
	r:clear(C.white, C.dark_gray) -- 不透明底板（色板 dark_gray，随主题）
	r:frame(title)
	local function mid(y, text, col)
		local tw = phos.text.width(text)
		r:print(math.floor((bw - tw) / 2), y, phos.text.fit(text, bw - 4), col)
	end
	if line1 then mid(2, line1, C.yellow) end
	if line2 then mid(4, line2, C.white) end
end

-- K 键位表：不透明底板 + 键位两列。开着时整局冻结（见 update），像把说明书摊在机器上。
local function draw_help(C)
	local S = phos.screen
	local t = phos.lang.dict(Text)
	local px, py, pw, ph = S.playfield()
	local bw = 56
	local bh = #t.help + 4
	local bx = px + math.floor((pw - bw) / 2)
	local by = py + math.floor((ph - bh) / 2)
	local r = phos.ui.region(bx, by, bw, bh)
	r:clear(C.white, C.dark_gray)
	r:frame(t.help_title)
	local KEYW = 20
	for i, line in ipairs(t.help) do
		-- 键组：每个虚拟键名现求真键名，再拼成一列（左右方向键等成组显示）。
		local keys = {}
		for _, k in ipairs(line[1]) do keys[#keys + 1] = phos.input.key_name(k) end
		r:print(2, 1 + i, phos.text.pad(table.concat(keys, "/"), KEYW), C.yellow)
		r:print(2 + KEYW, 1 + i, phos.text.fit(line[2], bw - KEYW - 4), C.white)
	end
	r:print(2, bh - 2, string.format(t.help_close, phos.input.key_name("k")), C.gray)
end

local function draw_play(C)
	View.draw(game, C)
	Hud.draw(game, C)
	if not game:tower_at(game.cx, game.cy) then
		Hud.cursor_hint(game, C) -- 塔上时侧栏已给详情，不重复压提示
	end
	Panel.draw(game, cart, speed, C)

	local t = phos.lang.dict(Text)
	if help_open then
		draw_help(C)
	elseif game.phase == "won" or game.phase == "over" then
		overlay(C, "", (game.phase == "won") and t.won or t.over,
			string.format(t.again, phos.input.key_name("a")))
	elseif paused then
		overlay(C, t.paused, nil, string.format("%s  /  %s", phos.input.key_name("start"), phos.input.key_name("b")))
	end
end

function draw()
	local C = phos.color
	if mode == "menu" then
		draw_menu(C)
	else
		draw_play(C)
	end
end

-- ── 给 agent / 自测的结构化状态（DESIGN §10）────────────────────────

function debug_state()
	if mode == "menu" or not game then
		return { phase = "menu", best_wave = best_wave, wins = wins, best_score = best_score,
			speed = speed, endless = menu.endless }
	end
	local g = game
	local towers = {}
	for _, t in ipairs(g.towers) do
		towers[#towers + 1] = { x = t.x, y = t.y, type = t.type, level = t.level,
			kills = t.kills, priority = t.priority, hp = t.hp, max_hp = t.max_hp }
	end
	local enemies = {}
	for _, e in ipairs(g.enemies) do
		local d = g.map:dist_at(math.floor(e.x), math.floor(e.y))
		local tg = e.target
		enemies[#enemies + 1] = { x = e.x, y = e.y, type = e.type, hp = e.hp,
			max_hp = e.max_hp, fly = e.fly, dist = d, mode = e.mode, reason = e.reason,
			tx = tg and tg.x or nil, ty = tg and tg.y or nil }
	end
	return {
		phase = g.phase,
		wave = g.wave, wave_total = g.wave_total, endless = g.endless,
		diff = g.diff, map_style = g.map_style,
		core_hp = g.core_hp, core_max = g.core_max,
		credits = g.credits,
		power_used = g.power_used, power_cap = g.power_cap,
		overload = (g.power_used > g.power_cap),
		overload_over = g.overload_over, overload_rate = g.overload_rate,
		active_waves = g:active_waves(),
		speed = speed, next_in = g.next_in,
		enemies_alive = #g.enemies,
		selected_type = g:selected_name(),
		cursor_x = g.cx, cursor_y = g.cy,
		airstrike_cd = g.airstrike_cd,
		buildable = g:can_build(g.cx, g.cy),
		heals = g.heal_count, towers_lost = g.towers_lost,
		towers = towers,
		enemies = enemies,
		path_ok = g.map:ground_path_exists(),
		grid = { w = g.MW, h = g.MH },
	}
end

-- panel.lua —— 右侧栏（DESIGN §8 那张表）。坐标是面板局部坐标，越界由主机裁剪。
-- 只读游戏状态；颜色全用主题色板；中文/英文走 phos.lang.dict，定宽字段用 phos.text.pad。
--
-- SELECTED 段是"跟随光标"的：光标在已建塔上就show那座塔（含升级后的实际数值），
-- 在空地上就show当前待建造塔型的完整数据——建造前也能先看数值，不用先花钱试。

local Towers = require("towers")

local Panel = {}

local Text = {
	zh = {
		wave = "波次", credits = "金币", draw = "耗电", out = "发电", core = "磁芯",
		online = "运作中", nopower = "未通电", base_pwr = "基地供电",
		build = "建造", selected = "已选", dmg = "伤害", range = "范围",
		rate = "攻速", kills = "击杀", upgrade = "升级", refund = "返还",
		cost = "造价", persec = "/秒", speed = "速度", hp = "血量",
		lvl = "级", airstrike = "空袭", ready = "就绪", sec = "秒", cont = "连续",
		priority = "优先",
		priority_names = { FIRST = "先攻", STRONG = "最强", CLOSE = "最近", AIR = "对空" },
		diff = "难度", map = "地图", max = "满级", combat = "交战", buildp = "布防",
		hint_k = "键位表",
		h_build = "建造/升级", h_sell = "拆除", h_type = "塔型",
		h_strike = "空袭", h_speed = "调速", h_keys = "键位",
		diff_names = { EASY = "简单", NORMAL = "普通", HARD = "困难" },
		map_names = { OPEN = "开阔", CANALS = "水道", MAZE = "迷宫", RANDOM = "随机" },
	},
	en = {
		wave = "WAVE", credits = "CREDITS", draw = "DRAW", out = "OUT", core = "CORE",
		online = "ONLINE", nopower = "NO POWER", base_pwr = "BASE POWER",
		build = "BUILD", selected = "SELECTED", dmg = "DMG", range = "RANGE",
		rate = "RATE", kills = "KILLS", upgrade = "UP", refund = "SELL",
		cost = "COST", persec = "/s", speed = "SPEED", hp = "HP",
		lvl = "Lv", airstrike = "AIRSTRIKE", ready = "READY", sec = "s", cont = "CONT",
		priority = "PRIORITY",
		priority_names = { FIRST = "FIRST", STRONG = "STRONG", CLOSE = "CLOSE", AIR = "AIR" },
		diff = "DIFF", map = "MAP", max = "MAX", combat = "COMBAT", buildp = "BUILD",
		hint_k = "CONTROLS",
		h_build = "BUILD", h_sell = "SELL", h_type = "TYPE",
		h_strike = "STRIKE", h_speed = "SPEED", h_keys = "KEYS",
		diff_names = { EASY = "EASY", NORMAL = "NORMAL", HARD = "HARD" },
		map_names = { OPEN = "OPEN", CANALS = "CANALS", MAZE = "MAZE", RANDOM = "RANDOM" },
	},
}

-- 面板"标签 值"两列对齐用的标签宽度（中/英都用它 pad，数值列才齐）。
local KVW = 6

-- 选中塔的颜色（与场上一致）：未满级用白（朴素），满级用类型色（各显本色，标出"练满"的独特）。
local function sel_color(d, tsel)
	return (tsel.level >= 3) and d.color or "white"
end

function Panel.draw(game, cart, speed, C)
	local P = phos.panel
	local pw, ph = P.size()
	if pw == 0 then return end
	local t = phos.lang.dict(Text)
	local region = phos.ui.region(0, 0, pw, ph, { surface = "panel" })
	-- 两列对齐的"标签 + 值"（标签 pad 到 KVW，中/英数值列都对齐）
	local function kv(label, val) return phos.text.pad(label, KVW) .. val end

	P.clear()
	P.print(1, 0, phos.text.fit(cart.name, pw - 2), C.yellow)
	P.print(1, 1, string.rep("-", pw - 2), C.dark_gray)

	-- 无尽模式超过 20 波后不再显示 /20（"+ " 表示继续），与 best_wave 共用同一纪录格
	if game.endless and game.wave > game.wave_total then
		P.print(1, 2, string.format("%s %d +", t.wave, game.wave), C.white)
	else
		P.print(1, 2, string.format("%s %d/%d", t.wave, game.wave, game.wave_total), C.white)
	end

	-- 磁芯血：数字 + 血条（色随血量档）
	local frac = (game.core_max > 0) and (game.core_hp / game.core_max) or 0
	local bar_col = (frac > 0.5) and C.green or (frac > 0.25 and C.yellow or C.red)
	P.print(1, 3, t.core .. string.format(" %d/%d", game.core_hp, game.core_max), bar_col)
	region:bar(1, 4, pw - 2, frac)

	P.print(1, 5, string.format("%s %d", t.credits, game.credits), C.yellow)

	-- 波次状态：build 倒计时 / combat 剩余（电力已改范围供电，不再有全局电力读数）
	local state
	if game.phase == "combat" or game.phase == "won" or game.phase == "over" then
		state = string.format("%s %.0f", t.combat, game.next_in)
	else
		state = string.format("%s %.0f", t.buildp, game.build_timer)
	end
	P.print(1, 6, phos.text.fit(state, pw - 2), C.gray)

	-- 速度读数：x1/x2/x3 常显，>1 时高亮——切速必须肉眼可辨（否则像按键没生效）。
	local spd = speed or 1
	P.print(1, 7, string.format("%s x%d", t.speed, spd), (spd > 1) and C.yellow or C.white)

	-- 分隔线：把上面的状态区与下面的建造/详情区分开，读起来更清爽
	P.print(1, 8, string.rep("-", pw - 2), C.dark_gray)

	-- 建造面板：**竖排一列**（`>名字 造价`，造价右对齐成一列），光标高亮当前选中；Z/X 按这一列上下切。
	P.print(1, 9, t.build, C.gray)
	local namew = pw - 6 -- 光标位 + 名字 + 右对齐的 3 位造价 = pw-2
	local list_y = 10
	for i, name in ipairs(Towers.ORDER) do
		local d = Towers.TYPES[name]
		local mark = (i == game.build_index) and ">" or " "
		local line = mark .. phos.text.pad(phos.text.fit(Towers.label(name), namew), namew)
			.. string.format("%3d", d.cost)
		P.print(1, list_y + i - 1, line, (i == game.build_index) and C.yellow or C.dark_gray)
	end

	-- 光标详情：光标下是塔 → 那座塔（含升级后数值 + HP 条）；否则 → 待建造塔型的完整数据。
	-- 行号从列表末尾顺延（不再写死），所以塔型多少都不撞行。
	local tsel = game:tower_at(game.cx, game.cy)
	local y = list_y + #Towers.ORDER
	P.print(1, y, t.selected, C.gray)
	y = y + 1
	if tsel then
		local d = Towers.TYPES[tsel.type]
		local dmg, range, interval = Towers.stats(tsel, tsel.aura)
		-- 升级预览：非满级时也算出"下一级"的三项，末尾用 ->下一级 标出练级收益
		local dmg2, range2, interval2
		if tsel.level < 3 then
			dmg2, range2, interval2 = Towers.stats({ type = tsel.type, level = tsel.level + 1,
				aura_range = tsel.aura_range, aura_rate = tsel.aura_rate }, tsel.aura)
		end
		local title = string.format("%s %s%d", Towers.label(tsel.type), t.lvl, tsel.level)
		P.print(1, y, title, C[sel_color(d, tsel)])
		-- "名字 等级"行**末尾**追加通电状态：未通电用醒目红、运作中用绿——一眼看出停没停
		local live = (tsel.powered ~= false)
		P.print(1 + phos.text.width(title) + 1, y, live and t.online or t.nopower,
			live and C.green or C.red)
		-- 名字下面一行：一句话功能简介（"它是干嘛的"）
		P.print(1, y + 1, phos.text.fit(Towers.desc(tsel.type), pw - 2), C.gray)
		-- HP：数字 + 血条（色随血量档）——选中的塔一眼看得出还撑不撑得住
		local hf = (tsel.max_hp > 0) and (tsel.hp / tsel.max_hp) or 0
		local hcol = (hf > 0.5) and C.green or (hf > 0.25 and C.yellow or C.red)
		P.print(1, y + 2, kv(t.hp, string.format("%d/%d", math.max(0, math.floor(tsel.hp)), tsel.max_hp)), hcol)
		region:bar(1, y + 3, pw - 2, math.max(0, math.min(1, hf)))
		P.print(1, y + 4, phos.text.fit(Panel._line(t.dmg,
			Panel._dmg(d, dmg, t, tsel.level), dmg2 and Panel._dmg(d, dmg2, t, tsel.level + 1)), pw - 2), C.white)
		P.print(1, y + 5, phos.text.fit(Panel._line(t.range,
			Panel._rng(range), range2 and Panel._rng(range2)), pw - 2), C.white)
		P.print(1, y + 6, phos.text.fit(Panel._line(t.rate,
			Panel._rate(d, interval, t), interval2 and Panel._rate(d, interval2, t)), pw - 2), C.white)
		-- 电源显示"发电 a/n"（a=已消耗 / n=供电量）；普通塔显示"耗电 d"；未通电时耗电行标红
		if d.kind == "reactor" then
			local s = game:source_at(tsel.x, tsel.y)
			P.print(1, y + 7, kv(t.out, string.format("%d/%d", s and s.used or 0,
				Towers.power_out(tsel))), C.white)
		else
			P.print(1, y + 7, kv(t.draw, tostring(Towers.power_use(tsel))),
				(tsel.powered == false) and C.red or C.white)
		end
		P.print(1, y + 8, kv(t.kills, tostring(tsel.kills)), C.white)
		-- 目标优先级（P 键切换）：让"按了 P 变成什么"看得见，而不是只在内部悄悄改
		P.print(1, y + 9, kv(t.priority, t.priority_names[tsel.priority] or tsel.priority), C.cyan)
		local uc = Towers.upgrade_cost(tsel)
		if uc then
			P.print(1, y + 10, kv(t.upgrade, "$" .. uc), C.green)
		else
			P.print(1, y + 10, kv(t.upgrade, t.max), C.gray)
		end
		P.print(1, y + 11, kv(t.refund, "$" .. Towers.refund(tsel)), C.orange)
		y = y + 12
	elseif game.cx == game.map.core.x and game.cy == game.map.core.y then
		-- 基地磁芯（也是电源）：光标悬在磁芯格上时显示它的"发电 a/n"
		local s = game:source_at(game.map.core.x, game.map.core.y)
		P.print(1, y, t.core, C.cyan)
		P.print(1, y + 1, phos.text.fit(t.base_pwr, pw - 2), C.gray)
		P.print(1, y + 2, kv(t.out, string.format("%d/%d", s and s.used or 0,
			Towers.CORE_SUPPLY)), C.white)
		y = y + 4
	else
		local name = game:selected_name()
		local d = Towers.TYPES[name]
		local dmg, range, interval = Towers.stats({ type = name, level = 1 }, false)
		P.print(1, y, Towers.label(name), C[d.color])
		P.print(1, y + 1, phos.text.fit(Towers.desc(name), pw - 2), C.gray)
		P.print(1, y + 2, kv(t.cost, "$" .. d.cost), C.yellow)
		-- 待建反应堆 → "发电 0/n"（还没建、未消耗）；其余 → "耗电 d"
		if d.kind == "reactor" then
			P.print(1, y + 3, kv(t.out, string.format("0/%d", d.supply[1])), C.white)
		else
			P.print(1, y + 3, kv(t.draw, tostring(Towers.power_at(name, 1))), C.white)
		end
		-- 建造前也报塔的血量（这一型的总血量）：建好后侧栏改显"当前/总"，
		-- 于是不管光标在塔上还是空地，血量都看得见。
		P.print(1, y + 4, kv(t.hp, tostring(d.hp or 0)), C.white)
		P.print(1, y + 5, Panel._line(t.dmg, Panel._dmg(d, dmg, t, 1)), C.white)
		P.print(1, y + 6, Panel._line(t.range, Panel._rng(range)), C.white)
		P.print(1, y + 7, Panel._line(t.rate, Panel._rate(d, interval, t)), C.white)
		y = y + 8
	end

	-- 空袭 / 难度地图：紧接详情之下顺延（不写死行号，塔型增多也不会被顶掉）
	local ast = (game.airstrike_cd <= 0) and t.ready
		or string.format("%.0f%s", game.airstrike_cd, t.sec)
	P.print(1, y + 1, kv(t.airstrike, ast),
		(game.airstrike_cd <= 0) and C.cyan or C.dark_gray)

	P.print(1, y + 2, phos.text.fit(string.format("%s %s  %s %s", t.diff,
		t.diff_names[game.diff] or game.diff, t.map,
		t.map_names[game.map_style] or game.map_style), pw - 2), C.dark_gray)

	-- 底部提示：新增/改位的键都在这行重述一遍，键名经 phos.input.key_name 求真名。
	local function kn(k) return phos.input.key_name(k) end
	P.print(1, ph - 4, phos.text.fit(string.format("%s %s  %s %s",
		kn("a"), t.h_build, kn("d"), t.h_sell), pw - 2), C.dark_gray)
	P.print(1, ph - 3, phos.text.fit(string.format("%s/%s %s  %s %s",
		kn("z"), kn("x"), t.h_type, kn("c"), t.h_strike), pw - 2), C.dark_gray)
	P.print(1, ph - 2, phos.text.fit(string.format("%s %s %s",
		kn("comma"), kn("period"), t.h_speed), pw - 2), C.dark_gray)
	P.print(1, ph - 1, string.format("%s %s", kn("k"), t.h_keys), C.dark_gray)
end

-- 一行"标签 当前值"；给了下一级值且确实变了，就带 ->下一级 预览练级收益（不涨的轴不啰嗦）。
function Panel._line(label, cur, nxt)
	local head = phos.text.pad(label, KVW) .. cur
	if nxt and nxt ~= cur then return head .. " ->" .. nxt end
	return head
end

-- 伤害字段：连续塔（dps）标 /s，普通塔给整数；无伤害（雷达/反应堆）给 "-"。
-- 维修塔没有伤害，改显每跳治疗量（+N），等级决定数值。
function Panel._dmg(d, dmg, t, level)
	if d.kind == "repair" then return string.format("+%d", d.heal.amount[level or 1]) end
	if d.dps then return string.format("%.0f%s", dmg, t.persec) end
	if (d.dmg or 0) > 0 then return string.format("%.0f", dmg) end
	return "-"
end

-- 射程字段：反应堆没有攻击射程（0）——给 "-" 而不是误导性的 0.0。
function Panel._rng(range)
	if range and range > 0 then return string.format("%.1f", range) end
	return "-"
end

-- 攻速字段：连续塔不占冷却，标"连续"；普通塔给攻击间隔秒；无攻击给 "-"。
function Panel._rate(d, interval, t)
	if d.dps then return t.cont end
	if (d.rate or 0) > 0 then return string.format("%.2f", interval) end
	return "-"
end

return Panel

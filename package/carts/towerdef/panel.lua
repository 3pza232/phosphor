-- panel.lua —— 右侧栏（DESIGN §8 那张表）。坐标是面板局部坐标，越界由主机裁剪。
-- 只读游戏状态；颜色全用主题色板；中文/英文走 phos.lang.dict，定宽字段用 phos.text.pad。
--
-- SELECTED 段是"跟随光标"的：光标在已建塔上就show那座塔（含升级后的实际数值），
-- 在空地上就show当前待建造塔型的完整数据——建造前也能先看数值，不用先花钱试。

local Towers = require("towers")

local Panel = {}

local Text = {
	zh = {
		wave = "波次", credits = "金币", power = "电力", core = "磁芯",
		build = "建造", selected = "已选", dmg = "伤害", range = "射程",
		rate = "攻速", kills = "击杀", upgrade = "升级", refund = "返还",
		cost = "造价", persec = "/秒", speed = "速度", hp = "血量",
		lvl = "级", airstrike = "空袭", ready = "就绪", sec = "秒", cont = "连续",
		diff = "难度", map = "地图", max = "满级", combat = "交战", buildp = "布防",
		hint_k = "键位表",
		h_build = "建造/升级", h_sell = "拆除", h_type = "塔型",
		h_strike = "空袭", h_speed = "调速", h_keys = "键位",
		diff_names = { EASY = "简单", NORMAL = "普通", HARD = "困难" },
		map_names = { OPEN = "开阔", CANALS = "水道", MAZE = "迷宫", RANDOM = "随机" },
	},
	en = {
		wave = "WAVE", credits = "CREDITS", power = "POWER", core = "CORE",
		build = "BUILD", selected = "SELECTED", dmg = "DMG", range = "RNG",
		rate = "RATE", kills = "KILLS", upgrade = "UP", refund = "SELL",
		cost = "COST", persec = "/s", speed = "SPEED", hp = "HP",
		lvl = "Lv", airstrike = "AIRSTRIKE", ready = "READY", sec = "s", cont = "CONT",
		diff = "DIFF", map = "MAP", max = "MAX", combat = "COMBAT", buildp = "BUILD",
		hint_k = "CONTROLS",
		h_build = "BUILD", h_sell = "SELL", h_type = "TYPE",
		h_strike = "STRIKE", h_speed = "SPEED", h_keys = "KEYS",
		diff_names = { EASY = "EASY", NORMAL = "NORMAL", HARD = "HARD" },
		map_names = { OPEN = "OPEN", CANALS = "CANALS", MAZE = "MAZE", RANDOM = "RANDOM" },
	},
}

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
	local pcol = game.overload and C.orange or C.white
	P.print(1, 6, string.format("%s %d/%d", t.power, game.power_used, game.power_cap), pcol)

	local state
	if game.phase == "combat" or game.phase == "won" or game.phase == "over" then
		state = string.format("%s %.0f", t.combat, game.next_in)
	else
		state = string.format("%s %.0f", t.buildp, game.build_timer)
	end
	P.print(1, 7, phos.text.fit(state, pw - 2), C.gray)

	-- 速度读数：x1/x2/x3 常显，>1 时高亮——切速必须肉眼可辨（否则像按键没生效）。
	local spd = speed or 1
	P.print(1, 8, string.format("%s x%d", t.speed, spd), (spd > 1) and C.yellow or C.white)

	-- 建造面板：12 型排成**两列各 6 行**（`>名字 造价`），光标高亮当前选中。
	-- 竖排 12 行会顶到下面的详情区，两列既放得下、又留足了详情与底部提示的行。
	P.print(1, 10, t.build, C.gray)
	-- 两个 11 列块（x=0 / x=11）：左块的 > 在 0 列、名字从 1 列起，与标题对齐。
	local colx, colw = { 0, 11 }, 11
	for i, name in ipairs(Towers.ORDER) do
		local d = Towers.TYPES[name]
		local cost = string.format("%d", d.cost)
		local labw = colw - 2 - #cost -- 光标位 + 名字 + 空格 + 造价 = colw
		local mark = (i == game.build_index) and ">" or " "
		local line = mark .. phos.text.pad(phos.text.fit(Towers.label(name), labw), labw) .. " " .. cost
		P.print(colx[((i - 1) % 2) + 1], 11 + math.floor((i - 1) / 2), line,
			(i == game.build_index) and C.yellow or C.dark_gray)
	end

	-- 光标详情：光标下是塔 → 那座塔（含升级后数值 + HP 条）；否则 → 待建造塔型的完整数据。
	-- 行号从标题顺延（不再写死），所以塔型多少都不撞行。
	local tsel = game:tower_at(game.cx, game.cy)
	local y = 18
	P.print(1, y, t.selected, C.gray)
	y = y + 1
	if tsel then
		local d = Towers.TYPES[tsel.type]
		local dmg, range, interval = Towers.stats(tsel, tsel.aura)
		P.print(1, y, string.format("%s %s%d", Towers.label(tsel.type), t.lvl, tsel.level), C[sel_color(d, tsel)])
		-- 名字下面一行：一句话功能简介（"它是干嘛的"）
		P.print(1, y + 1, phos.text.fit(Towers.desc(tsel.type), pw - 2), C.gray)
		-- HP：数字 + 血条（色随血量档）——选中的塔一眼看得出还撑不撑得住
		local hf = (tsel.max_hp > 0) and (tsel.hp / tsel.max_hp) or 0
		local hcol = (hf > 0.5) and C.green or (hf > 0.25 and C.yellow or C.red)
		P.print(1, y + 2, string.format("%s %d/%d", t.hp, math.max(0, math.floor(tsel.hp)), tsel.max_hp), hcol)
		region:bar(1, y + 3, pw - 2, math.max(0, math.min(1, hf)))
		P.print(1, y + 4, string.format("%s %s", t.dmg, Panel._dmg(d, dmg, t, tsel.level)), C.white)
		P.print(1, y + 5, string.format("%s %s", t.range, Panel._rng(range)), C.white)
		P.print(1, y + 6, string.format("%s %s", t.rate, Panel._rate(d, interval, t)), C.white)
		local out = (d.kind == "reactor") and string.format("+%d", Towers.power_out(tsel))
			or tostring(Towers.power_use(tsel))
		P.print(1, y + 7, string.format("%s %s", t.power, out), C.white)
		P.print(1, y + 8, string.format("%s %d", t.kills, tsel.kills), C.white)
		local uc = Towers.upgrade_cost(tsel)
		if uc then
			P.print(1, y + 9, string.format("%s $%d", t.upgrade, uc), C.green)
		else
			P.print(1, y + 9, t.max, C.gray)
		end
		P.print(1, y + 10, string.format("%s $%d", t.refund, Towers.refund(tsel)), C.orange)
		y = y + 11
	else
		local name = game:selected_name()
		local d = Towers.TYPES[name]
		local dmg, range, interval = Towers.stats({ type = name, level = 1 }, false)
		P.print(1, y, Towers.label(name), C[d.color])
		P.print(1, y + 1, phos.text.fit(Towers.desc(name), pw - 2), C.gray)
		P.print(1, y + 2, string.format("%s $%d", t.cost, d.cost), C.yellow)
		local out = (d.kind == "reactor") and string.format("+%d", d.cap[1]) or tostring(d.power or 0)
		P.print(1, y + 3, string.format("%s %s", t.power, out), C.white)
		-- 建造前也报塔的血量（这一型的总血量）：建好后侧栏改显"当前/总"，
		-- 于是不管光标在塔上还是空地，血量都看得见。
		P.print(1, y + 4, string.format("%s %d", t.hp, d.hp or 0), C.white)
		P.print(1, y + 5, string.format("%s %s", t.dmg, Panel._dmg(d, dmg, t, 1)), C.white)
		P.print(1, y + 6, string.format("%s %s", t.range, Panel._rng(range)), C.white)
		P.print(1, y + 7, string.format("%s %s", t.rate, Panel._rate(d, interval, t)), C.white)
		y = y + 8
	end

	-- 空袭 / 难度地图：紧接详情之下顺延（不写死行号，塔型增多也不会被顶掉）
	local ast = (game.airstrike_cd <= 0) and t.ready
		or string.format("%.0f%s", game.airstrike_cd, t.sec)
	P.print(1, y + 1, string.format("%s %s", t.airstrike, ast),
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

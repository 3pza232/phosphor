-- panel.lua —— 右侧栏（DESIGN §8 那张表）。坐标是面板局部坐标，越界由主机裁剪。
-- 只读游戏状态；颜色全用主题色板；中文/英文走 phos.lang.dict，定宽字段用 phos.text.pad。

local Towers = require("towers")

local Panel = {}

local Text = {
	zh = {
		wave = "波次", credits = "金币", power = "电力", core = "磁芯",
		build = "建造", selected = "已选", dmg = "伤害", range = "射程",
		rate = "攻速", kills = "击杀", upgrade = "升级", refund = "返还",
		lvl = "级", airstrike = "空袭", ready = "就绪", sec = "秒",
		cont = "连续",
		diff = "难度", map = "地图", max = "满级", combat = "交战", buildp = "布防",
		hint_k = "键位表",
		diff_names = { EASY = "简单", NORMAL = "普通", HARD = "困难" },
		map_names = { OPEN = "开阔", CANALS = "水道", MAZE = "迷宫", RANDOM = "随机" },
	},
	en = {
		wave = "WAVE", credits = "CREDITS", power = "POWER", core = "CORE",
		build = "BUILD", selected = "SELECTED", dmg = "DMG", range = "RNG",
		rate = "RATE", kills = "KILLS", upgrade = "UP", refund = "SELL",
		lvl = "Lv", airstrike = "AIRSTRIKE", ready = "READY", sec = "s",
		cont = "CONT",
		diff = "DIFF", map = "MAP", max = "MAX", combat = "COMBAT", buildp = "BUILD",
		hint_k = "CONTROLS",
		diff_names = { EASY = "EASY", NORMAL = "NORMAL", HARD = "HARD" },
		map_names = { OPEN = "OPEN", CANALS = "CANALS", MAZE = "MAZE", RANDOM = "RANDOM" },
	},
}

-- 选中塔的类型色（与场上一致，L3 用白）。定义在 draw 之前，避免前向引用到全局。
local function sel_color(d, tsel)
	return (tsel.level >= 3) and "white" or d.color
end

function Panel.draw(game, cart, C)
	local P = phos.panel
	local pw, ph = P.size()
	if pw == 0 then return end
	local t = phos.lang.dict(Text)
	local region = phos.ui.region(0, 0, pw, ph, { surface = "panel" })

	P.clear()
	P.print(1, 0, phos.text.fit(cart.name, pw - 2), C.yellow)
	P.print(1, 1, string.rep("-", pw - 2), C.dark_gray)

	P.print(1, 2, string.format("%s %d/%d", t.wave, game.wave, game.wave_total), C.white)

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

	-- 建造面板：7 项，光标高亮当前选中
	P.print(1, 9, t.build, C.gray)
	for i, name in ipairs(Towers.ORDER) do
		local d = Towers.TYPES[name]
		local mark = (i == game.build_index) and ">" or " "
		local line = string.format("%s%s$%dp", mark, phos.text.pad(Towers.label(name), 9), d.cost, d.power)
		P.print(1, 9 + i, phos.text.fit(line, pw - 2), (i == game.build_index) and C.yellow or C.dark_gray)
	end

	-- 选中塔详情（光标下）
	local y = 19
	P.print(1, y, t.selected, C.gray)
	y = y + 1
	local tsel = game:tower_at(game.cx, game.cy)
	if tsel then
		local d = Towers.TYPES[tsel.type]
		local dmg, range, interval = Towers.stats(tsel, tsel.aura)
		P.print(1, y, string.format("%s %s%d", Towers.label(tsel.type), t.lvl, tsel.level), C[sel_color(d, tsel)])
		if d.dps then
			P.print(1, y + 1, string.format("%s %.0f/s", t.dmg, dmg), C.white)
		else
			P.print(1, y + 1, string.format("%s %.0f", t.dmg, dmg), C.white)
		end
		P.print(1, y + 2, string.format("%s %.1f", t.range, range), C.white)
		if d.dps then
			P.print(1, y + 3, string.format("%s %s", t.rate, t.cont), C.white)
		else
			P.print(1, y + 3, string.format("%s %.2f", t.rate, interval), C.white)
		end
		P.print(1, y + 4, string.format("%s %d", t.kills, tsel.kills), C.white)
		local uc = Towers.upgrade_cost(tsel)
		if uc then
			P.print(1, y + 5, string.format("%s $%d", t.upgrade, uc), C.green)
		else
			P.print(1, y + 5, t.max, C.gray)
		end
		P.print(1, y + 6, string.format("%s $%d", t.refund, Towers.refund(tsel)), C.orange)
	else
		P.print(1, y, "-", C.dark_gray)
	end

	-- 空袭（放在选中详情之下，避免与其最后一行撞行）
	local ast = (game.airstrike_cd <= 0) and t.ready
		or string.format("%.0f%s", game.airstrike_cd, t.sec)
	P.print(1, 28, string.format("%s %s", t.airstrike, ast),
		(game.airstrike_cd <= 0) and C.cyan or C.dark_gray)

	P.print(1, 29, phos.text.fit(string.format("%s %s  %s %s", t.diff,
		t.diff_names[game.diff] or game.diff, t.map,
		t.map_names[game.map_style] or game.map_style), pw - 2), C.dark_gray)

	-- 键位全部收进 K 帮助浮窗；侧栏底部只留一个整齐的入口指针（游戏区底部不再放任何键位）
	P.print(1, ph - 1, phos.text.fit(string.format("[%s] %s", phos.input.key_name("k"), t.hint_k), pw - 2), C.dark_gray)
end

return Panel

-- hud.lua —— 压在地图上的叠字：顶部读数、波次横幅、底部提示、空袭冷却。
-- 只读游戏状态；只给前景、不给底色（透明底，透出地形，见 DESIGN §8）。
-- 中文/英文都走 phos.lang.dict；定宽补齐用 phos.text.pad。

local Towers = require("towers")

local Hud = {}

local Text = {
	zh = {
		wave = "波次", combat = "交战", build = "布防", combo = "战斗",
		credits = "金币", power = "电力", core = "磁芯",
		overload = "电力超载", airstrike_ready = "空袭就绪", airstrike = "空袭",
		early = "空格 提前放波", banner = "第 %d 波",
		hint_build = "A 建造  X 拆除  Y 换塔  Z 空袭",
		hint_combat = "A 升级  X 拆除  Z 空袭  退格 优先级",
	},
	en = {
		wave = "WAVE", combat = "COMBAT", build = "BUILD", combo = "FIGHT",
		credits = "CREDITS", power = "POWER", core = "CORE",
		overload = "POWER OVERLOAD", airstrike_ready = "AIRSTRIKE RDY", airstrike = "AIRSTRIKE",
		early = "SPACE: early wave", banner = "WAVE %d",
		hint_build = "A build  X sell  Y type  Z strike",
		hint_combat = "A upgrade  X sell  Z strike  BKSP prio",
	},
}

function Hud.draw(game, C)
	local S = phos.screen
	local px, py, pw, ph = S.playfield()
	local t = phos.lang.dict(Text)

	-- ── 顶部读数（第 0 行）──
	local phase = (game.phase == "combat") and t.combat or t.build
	local timer = string.format("%02d", math.floor(game.next_in + 0.5))
	local line = string.format("%s %d/%d  %s %s  %s %d  %s %d/%d  %s %d/%d",
		t.wave, game.wave, game.wave_total, phase, timer,
		t.credits, game.credits, t.power, game.power_used, game.power_cap,
		t.core, game.core_hp, game.core_max)
	S.print(px + 1, py, line, C.white)

	-- 欠压警示：单独一行，橙色（DESIGN §6.4）
	if game.overload then
		S.print(px + 1, py + 1, t.overload, C.orange)
	end

	-- ── 波次横幅（scale=2 居中，只在前 1.8s）──
	if game.banner > 0 then
		local label = string.format(t.banner, game.wave)
		local w = phos.text.width(label) * 2
		S.print(px + math.floor((pw - w) / 2), py + 7, label, C.yellow, nil, 2)
	end
	-- 游戏区底部不放任何键位/提示：键位全在 K 帮助浮窗里，状态读数在侧栏
end

-- 菜单里也显示一行"当前选中塔型的说明"，由 main 在光标处调用。
function Hud.cursor_hint(game, C)
	local S = phos.screen
	local px, py, pw, ph = S.playfield()
	local name = game:selected_name()
	local d = Towers.TYPES[name]
	local txt = string.format("%s  $%d  %dp", Towers.label(name), d.cost, d.power)
	S.print(px + 1, py + ph - 2, phos.text.fit(txt, pw - 2), C.yellow)
end

return Hud

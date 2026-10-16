-- hud.lua —— 压在地图上的叠字：顶部读数、波次横幅、底部提示、空袭冷却。
-- 只读游戏状态；只给前景、不给底色（透明底，透出地形，见 DESIGN §8）。
-- 中文/英文都走 phos.lang.dict；定宽补齐用 phos.text.pad。

local Towers = require("towers")

local Hud = {}

local Text = {
	zh = {
		wave = "波次", combat = "交战", build = "布防", combo = "战斗",
		credits = "金币", core = "磁芯",
		airstrike_ready = "空袭就绪", airstrike = "空袭",
		early = "空格 提前放波", banner = "第 %d 波",
	},
	en = {
		wave = "WAVE", combat = "COMBAT", build = "BUILD", combo = "FIGHT",
		credits = "CREDITS", core = "CORE",
		airstrike_ready = "AIRSTRIKE RDY", airstrike = "AIRSTRIKE",
		early = "SPACE: early wave", banner = "WAVE %d",
	},
}

function Hud.draw(game, C)
	local S = phos.screen
	local px, py, pw, ph = S.playfield()
	local t = phos.lang.dict(Text)

	-- ── 顶部读数（第 0 行）──
	local phase = (game.phase == "combat") and t.combat or t.build
	local timer = string.format("%02d", math.floor(game.next_in + 0.5))
	-- 无尽超过 20 波后不再显示 /20
	local wave_str = (game.endless and game.wave > game.wave_total)
		and string.format("%d+", game.wave)
		or string.format("%d/%d", game.wave, game.wave_total)
	-- 顶部只有 波次 / 阶段 / 金币 / 磁芯——电力改范围供电后不再有全局读数（见 §6.4）
	local line = string.format("%s %s  %s %s  %s %d  %s %d/%d",
		t.wave, wave_str, phase, timer,
		t.credits, game.credits, t.core, game.core_hp, game.core_max)
	S.print(px + 1, py, line, C.white)

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
	-- 反应堆是电源：显示"+供电"；其余显示本级耗电
	local spec = (d.kind == "reactor") and string.format("+%d", d.supply[1])
		or string.format("%dp", Towers.power_at(name, 1))
	local txt = string.format("%s  $%d  %s", Towers.label(name), d.cost, spec)
	S.print(px + 1, py + ph - 2, phos.text.fit(txt, pw - 2), C.yellow)
end

return Hud

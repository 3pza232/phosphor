-- waves.lua —— 20 波模板、成长系数与难度系数（DESIGN §5.1 / §5.4）。
--
-- 纯数据 + 纯函数：这一层不认识敌人实体，也不计时——它只回答"第 w 波该出什么、
-- 数值该乘多少"。换一份 waves.lua 就换了一套波次，玩法代码不用动（mod 可覆盖）。

local Waves = {}

Waves.TOTAL = 20

-- 成长系数：随波号线性放大。公式写在这里，别散到 enemies/game 里。
function Waves.hp_growth(w) return 1 + 0.06 * (w - 1) end
function Waves.speed_growth(w) return math.min(1.20, 1 + 0.01 * (w - 1)) end
function Waves.reward_growth(w) return 1 + 0.02 * (w - 1) end

-- ── 无尽模式（w > TOTAL）──────────────────────────────────────────────
-- 第 20 波血量作基准，之后每波 +9%；速度/赏金仍走上面那两条公式（速度本就封顶）。
function Waves.hp_growth_endless(w)
	return Waves.hp_growth(Waves.TOTAL) * (1 + 0.09 * (w - Waves.TOTAL))
end

-- 无尽波按"威胁预算"花掉：B(w) = B20 + 6·(w-20)，B20 取第 20 波模板的近似总量。
Waves.B20 = 86

-- 敌人威胁点 + 出怪间隔（沿用现有量级的代表值）。顺序固定 = 同种子可复现。
Waves.THREATS = {
	{ type = "grunt",  threat = 1.0,  interval = 0.8 },
	{ type = "runner", threat = 1.0,  interval = 0.6 },
	{ type = "swarm",  threat = 0.4,  interval = 0.2 },
	{ type = "flyer",  threat = 2.5,  interval = 0.9 },
	{ type = "shield", threat = 3.0,  interval = 1.1 },
	{ type = "armor",  threat = 4.0,  interval = 1.2 },
	{ type = "boss",   threat = 30.0, interval = 0.5 },
}
local BOSS_CAP = 2 -- 每波首领上限

-- 难度（开局菜单选）：起始金币 / 磁芯血 / 敌人 hp 乘数 / 敌人速度乘数。
Waves.DIFF = {
	EASY = { credits = 300, core = 25, hp = 0.80, speed = 0.90 },
	NORMAL = { credits = 200, core = 20, hp = 1.00, speed = 1.00 },
	HARD = { credits = 150, core = 15, hp = 1.25, speed = 1.08 },
}
Waves.DIFF_ORDER = { "EASY", "NORMAL", "HARD" }

-- 每波 = 若干"组"：{ type, count, interval, gate? }。gate 省略 = 随机刷怪口；
-- 多组**并行**，各自计时（各自间隔），不是一组出完再下一组。
Waves.TEMPLATES = {
	{ { "grunt", 6, 1.0 } },
	{ { "grunt", 10, 0.8 } },
	{ { "runner", 8, 0.7 } },
	{ { "grunt", 8, 0.7 }, { "runner", 6, 0.6 } },
	{ { "armor", 4, 1.5 } },
	{ { "swarm", 20, 0.25 } },
	{ { "flyer", 6, 1.0 } },
	{ { "grunt", 12, 0.7 }, { "armor", 4, 1.4 } },
	{ { "shield", 5, 1.2 } },
	{ { "boss", 1, 0 }, { "grunt", 8, 0.8 } },
	{ { "runner", 14, 0.5 } },
	{ { "swarm", 30, 0.2 }, { "flyer", 8, 0.9 } },
	{ { "armor", 8, 1.2 } },
	{ { "shield", 8, 1.0 }, { "grunt", 10, 0.7 } },
	{ { "boss", 1, 0 }, { "flyer", 10, 0.8 }, { "runner", 10, 0.6 } },
	{ { "swarm", 40, 0.18 }, { "armor", 6, 1.3 } },
	{ { "shield", 10, 0.9 }, { "flyer", 10, 0.8 } },
	{ { "armor", 12, 1.0 }, { "runner", 16, 0.5 } },
	{ { "grunt", 20, 0.5 }, { "armor", 10, 1.0 }, { "shield", 8, 0.9 }, { "flyer", 10, 0.7 } },
	{ { "boss", 2, 0 }, { "swarm", 40, 0.18 }, { "armor", 10, 1.0 } },
}

-- 取第 w 波的组定义（1 基）。常规波走模板；无尽波（w > TOTAL）现算预算。
-- endless=false 时越界返回空表（保留旧行为）。
function Waves.groups(w, endless)
	if w <= Waves.TOTAL then return Waves.TEMPLATES[w] or {} end
	if not endless then return {} end
	return Waves.endless_groups(w)
end

-- 无尽波：反复从"买得起的类型"里随机挑一个花预算，花不动就停（剩余不足最小项）。
-- 用 phos.sys.random —— 同种子同波次生成同一批怪（可复现）。
function Waves.endless_groups(w)
	local budget = Waves.B20 + 6 * (w - Waves.TOTAL)
	local counts, bosses = {}, 0
	while true do
		-- 买得起、且没到首领上限的类型
		local pool = {}
		for _, e in ipairs(Waves.THREATS) do
			if e.threat <= budget + 1e-9 and not (e.type == "boss" and bosses >= BOSS_CAP) then
				pool[#pool + 1] = e
			end
		end
		if #pool == 0 then break end
		local pick = pool[phos.sys.random(1, #pool)]
		budget = budget - pick.threat
		counts[pick.type] = (counts[pick.type] or 0) + 1
		if pick.type == "boss" then bosses = bosses + 1 end
	end
	local groups = {}
	for _, e in ipairs(Waves.THREATS) do
		local c = counts[e.type]
		if c and c > 0 then groups[#groups + 1] = { e.type, c, e.interval } end
	end
	return groups
end

-- 该波的三个成长乘数（含难度）打包返回，game 侧生成敌人时直接用。
-- 无尽波的血量走 hp_growth_endless，速度/赏金仍走常规公式。
function Waves.factors(w, diff, endless)
	local d = Waves.DIFF[diff] or Waves.DIFF.NORMAL
	local hp = (endless and w > Waves.TOTAL) and Waves.hp_growth_endless(w) or Waves.hp_growth(w)
	return {
		hp = hp * d.hp,
		speed = Waves.speed_growth(w) * d.speed,
		reward = Waves.reward_growth(w),
	}
end

return Waves

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

-- 取第 w 波的组定义（1 基）。越界返回空表。
function Waves.groups(w)
	return Waves.TEMPLATES[w] or {}
end

-- 该波的三个成长乘数（含难度）打包返回，game 侧生成敌人时直接用。
function Waves.factors(w, diff)
	local d = Waves.DIFF[diff] or Waves.DIFF.NORMAL
	return {
		hp = Waves.hp_growth(w) * d.hp,
		speed = Waves.speed_growth(w) * d.speed,
		reward = Waves.reward_growth(w),
	}
end

return Waves

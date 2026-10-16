-- waves.lua —— 20 波模板 + 难度模型（DESIGN §5.1 / §5.4）。
--
-- 纯数据 + 纯函数：这一层不认识敌人实体，也不计时——它只回答"第 w 波该出什么、
-- 数值该乘多少"。换一份 waves.lua 就换了一套波次，玩法代码不用动（mod 可覆盖）。
--
-- ── 难度模型：经济 → 我方火力 → 敌人强度 ──────────────────────────────
-- 不硬编码逐波难度：加载期用"模板 + 少量具名常量"推导每条血/赏金乘子。方程：
--   FPC   = 攻击塔 F/cost 的中位数（F=dps·range；连续塔用 dps；AoE×(1+splash)；连锁×chain）
--   I(w)  = 起始金币 + Σ_{i≤w}( 赏金 + 波清奖金(15+2i) + INCLUDE·P_MED·max_bonus(i) )
--           赏金 = Σ count·base_bounty·reward_growth(i)
--           max_bonus(i)=WAIT_A+WAIT_B·i 是第 i 波"满额等待金"（game.lua 提前放波，见 §6.4）
--   P(w)  = 攻击力金币 ·FPC·EFF                 （范围供电约束下的有效火力，见下）
--           攻击力金币 = G(I(w))：金币要么买攻击塔、要么买反应堆供电；基地免费供 200。
--   Ebase = Σ count·(hp + ARMOR_W·armor + shield)
--   Etarget(w) = P(w)·R·S(w)，  S(w)=1+S_SLOPE·(w-1)
--   hp_growth(w) = Etarget(w)/Ebase(w)         （逐波推出，不是手填表）
-- 于是 E(w)/P(w) = R·S(w)：全程近乎恒定、后期缓升（见 dev/balance_model.py 的逐波表）。
-- hp_growth 仍随模板组成起伏：boss/精英波基础血高 → 乘子低。这不是 bug——正是它抵消
-- 模板的"某波突然变重"，使玩家能感到的**难度曲线 E(w)/P(w) 平滑**。强行把 hp_growth
-- 抹成单调反而会让 E/P 摆动 4~10 倍（dev/balance_model.py 已记录该实验）。
--
-- **MODEL_ENEMY 是 enemies.lua 的镜像**（只取模型用得到的 hp/armor/bounty/shield）：
-- 改 enemies.lua 的这几项务必要同步这里，否则模型与实体漂移。dev/balance_model.py
-- 是同一模型的独立复算（改常量三处一起改）。

local Waves = {}

Waves.TOTAL = 20

-- 每波 = 若干"组"：{ type, count, interval, gate? }。gate 省略 = 随机刷怪口；
-- 多组**并行**，各自计时（各自间隔），不是一组出完再下一组。
-- 只定"出怪风味"（类型与配比）；强度由下面的模型定。
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

-- ── 模型常量（含义 + 取值理由）────────────────────────────────────────
-- FPC：攻击塔 F/cost 的中位数。现行塔表中位塔 = TESLA
--   （24/1.40·5.5·3 / 130 ≈ 2.176）。改 towers.lua 的火力/造价要重算这里。
local FPC = 2.17582
local EFF = 0.50          -- 中位数玩家把金币转成"有效火力"的效率：布局/空转/超杀/辅助设施
local ARMOR_W = 20        -- 每点 armor 折算的有效血：armor=5 → 装甲等效血约 ×1.45
local S_SLOPE = 0.03      -- 每波目标松紧缓坡：后期略紧（从 0.02 上调，压一压无尽后期我方膨胀）
-- 范围供电（DESIGN §6.4）：基地免费供 BASE_SUPPLY；反应堆 L1 花 60 金供 60 电（≈1 电/金）。
-- 攻击塔"每金带来的耗电"DRAW_RATIO 由下面 MODEL_TOWER 表算（耗电/造价 的均值）。
local BASE_SUPPLY = 200   -- 基地磁芯供电（免费，但只罩磁芯附近——空间限制折进 EFF）
local SUPPLY_PER_GOLD = 1.0 -- 反应堆供电/金币（L1=60/60）
local REWARD_MAX = 1.20   -- 赏金乘子全程上限：数量已驱动收入增长 ~18×，乘子再快就滚雪球
local HP_GROWTH_1 = 1.0   -- 标定：第 1 波（NORMAL）血乘子 = 1.0（开局面值 → 平顺开局）
-- 经济/奖金常量（与 game.lua 一一对应）
local CLEAR_A, CLEAR_B = 15, 2        -- 波清奖金 = A + B·w（game.lua check_end）
local WAIT_A, WAIT_B = 10, 2          -- 满额等待金 = A + B·w（game.lua early_wave 调 wait_bonus_max）
local P_MED = 0.50                    -- 中位实现比例：玩家不总提前招、常建到一半才招 → 中位拿满额一半
local INCLUDE = 0.50                  -- 等待金折入 I(w) 的比例（手感奖励 > 曲线影响）
local BUILD_TIME = 60                 -- 每波等待秒数（与 game.BUILD_TIME 同步；仅供模型阅读）
local NORMAL_CREDITS = 130            -- 标定 R 用的起始金币（NORMAL 档）

-- 敌人最小输入表（enemies.lua 镜像；模型只用 hp/armor/bounty/shield）
local MODEL_ENEMY = {
	grunt  = { hp = 60,   armor = 0, bounty = 5,   shield = 0 },
	runner = { hp = 40,   armor = 0, bounty = 6,   shield = 0 },
	swarm  = { hp = 25,   armor = 0, bounty = 2,   shield = 0 },
	armor  = { hp = 220,  armor = 5, bounty = 13,  shield = 0 },
	shield = { hp = 140, armor = 0, bounty = 15, shield = 40 },
	flyer  = { hp = 90,  armor = 0, bounty = 10, shield = 0 },
	boss   = { hp = 2600, armor = 8, bounty = 170, shield = 0 },
}

-- 攻击塔最小输入表（towers.lua 镜像；模型只用 cost 与 L1 耗电估"每金耗电"）。
-- 改 towers.lua 的造价/耗电要同步这里（与 MODEL_ENEMY 同一约定）。
local MODEL_TOWER = {
	{ cost = 50,  draw = 20 }, -- GUN
	{ cost = 95,  draw = 40 }, -- CANNON
	{ cost = 70,  draw = 30 }, -- FROST
	{ cost = 130, draw = 45 }, -- TESLA
	{ cost = 115, draw = 40 }, -- FLAME
	{ cost = 120, draw = 50 }, -- LASER
	{ cost = 150, draw = 55 }, -- HELL
	{ cost = 140, draw = 45 }, -- SNIPER
	{ cost = 135, draw = 50 }, -- MORTAR
}

-- 速度仍走一条独立缓坡（与血量解耦：快慢是风味，强度由模型定）。
function Waves.speed_growth(w) return math.min(1.25, 1 + 0.012 * (w - 1)) end
-- 赏金乘子：线性缓升到 REWARD_MAX（由"不滚雪球"的经济目标反推，见 DESIGN §5.4）
function Waves.reward_growth(w) return 1 + (REWARD_MAX - 1) / (Waves.TOTAL - 1) * (w - 1) end
-- 满额等待金：整段等待都省掉时拿多少（combat 期提前招 = 满额；build 期按剩余比例）。
-- 按波号缓增，量级与波清奖金 15+2w 相当但略低——"有意义但非主要收入"：够推动你抢节奏，
-- 又不至于让提前放波变成主要刷钱手段。game.lua 的 early_wave 直接调它。
function Waves.wait_bonus_max(w) return WAIT_A + WAIT_B * w end

-- ── 加载期推导（下面全是模型算出来的，不是手填）──────────────────────
local function S(w) return 1 + S_SLOPE * (w - 1) end
local function base_hp(t) local e = MODEL_ENEMY[t]; return e.hp + ARMOR_W * e.armor + e.shield end

local Ebase, Bounty = {}, {}   -- 每波基础总血 / 面值赏金总额
for w, groups in ipairs(Waves.TEMPLATES) do
	local eb, bb = 0, 0
	for _, g in ipairs(groups) do
		local t, c = g[1], g[2]
		eb = eb + c * base_hp(t)
		bb = bb + c * MODEL_ENEMY[t].bounty
	end
	Ebase[w], Bounty[w] = eb, bb
end

local Income = {}  -- 到第 w 波累计可支配金币
do
	local cum = 0
	for w = 1, Waves.TOTAL do
		cum = cum + Bounty[w] * Waves.reward_growth(w)
			+ (CLEAR_A + CLEAR_B * w)
			+ INCLUDE * P_MED * Waves.wait_bonus_max(w)
		Income[w] = cum
	end
end

-- 每金攻击塔带来的耗电（均值）；反应堆每金供 SUPPLY_PER_GOLD。
-- 攻击力金币 G 满足：G·DRAW_RATIO ≤ BASE_SUPPLY + (I − G)·SUPPLY_PER_GOLD；
-- 解出 G = min(I, (I + BASE_SUPPLY)/(1 + DRAW_RATIO/SUPPLY_PER_GOLD))：
-- 早期 I 小、基地 200 免费够用 → G=I（不扣电税）；后期 I 大 → 一部分金币转去买反应堆。
local DRAW_RATIO = 0
do
	local sc, sd = 0, 0
	for _, tw in ipairs(MODEL_TOWER) do sc = sc + tw.cost; sd = sd + tw.draw end
	DRAW_RATIO = (sd / #MODEL_TOWER) / (sc / #MODEL_TOWER) -- 均值耗电 / 均值造价
end
local function attack_gold(I)
	local g = (I + BASE_SUPPLY * SUPPLY_PER_GOLD) / (1 + DRAW_RATIO / SUPPLY_PER_GOLD)
	if g > I then g = I end
	return g
end
local function P(w) return attack_gold(NORMAL_CREDITS + Income[w]) * FPC * EFF end

-- R：整体松紧常量，标定 hp_growth(1)=HP_GROWTH_1（即开局面值）
local R = HP_GROWTH_1 * Ebase[1] / P(1)

local HP_GROWTH = {}  -- 逐波血乘子（模型推出）
for w = 1, Waves.TOTAL do
	HP_GROWTH[w] = P(w) * R * S(w) / Ebase[w]
end

-- ── 无尽模式（w > TOTAL）──────────────────────────────────────────────
-- 与常规同源：血量 = 第 20 波乘子 × 同一模型的每波增幅，线性外推到之后。
-- 增幅取模型在第 15→20 波的平均每波强度比（去掉单波噪声，代表后期真实爬升）。
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
do
	local function Etarget(w) return P(w) * R * S(w) end
	Waves.ENDLESS_RATE = (Etarget(Waves.TOTAL) / Etarget(Waves.TOTAL - 5)) ^ (1 / 5) - 1
	-- B20 = 第 20 波模板的威胁总量（预算与血量同源外推）
	local threat_of = {}
	for _, e in ipairs(Waves.THREATS) do threat_of[e.type] = e.threat end
	local b = 0
	for _, g in ipairs(Waves.TEMPLATES[Waves.TOTAL]) do b = b + g[2] * (threat_of[g[1]] or 1) end
	Waves.B20 = b
end

-- 第 w 波的血乘子。w>TOTAL（无尽）走同一模型的线性外推。
function Waves.hp_growth(w)
	if w <= Waves.TOTAL then return HP_GROWTH[w] end
	return Waves.hp_growth_endless(w)
end

function Waves.hp_growth_endless(w)
	return HP_GROWTH[Waves.TOTAL] * (1 + Waves.ENDLESS_RATE * (w - Waves.TOTAL))
end

-- 难度（开局菜单选）：起始金币 / 磁芯血 / 敌人 hp 乘数 / 敌人速度乘数。
-- 起始金币按模型"够撑过前几波"定：范围供电后前期还要花钱拉电（反应堆），HARD 起始金币
-- 随之上调到 150，保证"前几波不变难"；EASY 170 更宽松。hp 乘数按各档松紧
-- （EASY 0.8 / NORMAL 1.0 / HARD 1.15）叠在模型曲线之上。
Waves.DIFF = {
	EASY = { credits = 170, core = 25, hp = 0.80, speed = 0.90 },
	NORMAL = { credits = 130, core = 20, hp = 1.00, speed = 1.00 },
	HARD = { credits = 150, core = 15, hp = 1.15, speed = 1.05 },
}
Waves.DIFF_ORDER = { "EASY", "NORMAL", "HARD" }

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
	local budget = Waves.B20 * (1 + Waves.ENDLESS_RATE * (w - Waves.TOTAL))
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
function Waves.factors(w, diff, endless)
	local d = Waves.DIFF[diff] or Waves.DIFF.NORMAL
	return {
		hp = Waves.hp_growth(w) * d.hp,
		speed = Waves.speed_growth(w) * d.speed,
		reward = Waves.reward_growth(w),
	}
end

return Waves

-- towers.lua —— 塔类型表、升级/返还计算、目标选择与开火结算。
--
-- 数据驱动 + 无 UI：加一种塔只加一行；换 towers.lua 就换一套炮塔。
-- 开火逻辑通过 ctx（game 现搭的一张接口表）触达敌人与特效，自己不持有 game——
-- 于是这一层可以脱离 game 单测，也说明它没有偷偷读键盘/画东西。
--
-- 颜色同样只存**色板槽位名**，绘制时才解析。

local Enemies = require("enemies") -- 冰塔/火焰要往敌人身上挂 slow / burn 状态

local Towers = {}

-- 每个字段：cost 金币 / power 耗电（按 L1/L2/L3 三项，见 §电力）/ dmg / rate(攻击间隔秒) /
-- range(格) / chars 三级字符 / color 槽位 / kind 机制 / ignore_armor 无视护甲 / hp 满血。
-- hp 让塔也能被拆（敌人 siege 直接扣它）——满值按类型，独立于造价。
--
-- 电力（范围供电，DESIGN §6.4）：**耗电**是一张"每型×每级"表（power = {L1,L2,L3}）；
-- 反应堆是**电源**（supply = {L1,L2,L3} 供电量，不耗电）。锚点：L1 机枪 = 20，
-- 一个 L2 反应堆(100) 带约 5 个中型设备。重火力/激光/地狱/采矿机偏高；雷达/维修偏低。
--
-- up 是每型的**升级档案**：dmg 每级伤害乘子 / rate 每级间隔乘子 / range 每级射程加值。
-- 默认 1.6 / 0.88 / 1.5；填 1.0 / 1.0 / 0 表示该轴不涨。冰塔不堆伤害、雷达/反应堆
-- 无伤害档，靠这份档案各自声明"练级练什么"，而不是全场一刀切。
-- 特殊量随等级的（溅射半径、连锁数、锁定数…）写成按等级数组成员，用 Towers.by 取。
Towers.TYPES = {
	-- 机枪：主堆攻速（0.85 比旧的 0.88 更快）与伤害，射程仅小幅跟进。
	GUN = { cost = 50, power = { 20, 32, 50 }, dmg = 9, rate = 0.35, range = 5.0, hp = 100,
		up = { dmg = 1.7, rate = 0.85, range = 1.0 },
		chars = { "g", "G", "G" }, color = "green", kind = "gun",
		label = { zh = "机枪", en = "GUN" }, desc = { zh = "单体速射，便宜", en = "fast single shot" } },
	-- 加农炮：溅射半径随级放大是它的身份（否则只是个大枪）。
	CANNON = { cost = 95, power = { 40, 62, 96 }, dmg = 34, rate = 1.25, range = 6.0, splash = 1.6, hp = 140,
		up = { dmg = 1.7, rate = 0.92, range = 1.0 }, splash_by = { 1.6, 2.1, 2.7 },
		chars = { "c", "C", "C" }, color = "orange", kind = "cannon",
		label = { zh = "加农炮", en = "CANNON" }, desc = { zh = "高伤溅射", en = "high splash dmg" } },
	-- 冰霜：只堆"控"——减速更狠、更久、目标更多；伤害乘子 1.0（升级不涨伤害）。
	FROST = { cost = 70, power = { 30, 46, 70 }, dmg = 5, rate = 0.70, range = 5.0, max_targets = 3, hp = 90,
		slow_factor = 0.55, slow_time = 1.8,
		up = { dmg = 1.0, rate = 0.92, range = 1.5 },
		slow_by = { 0.55, 0.42, 0.30 }, slow_time_by = { 1.8, 2.4, 3.2 },
		max_targets_by = { 3, 4, 6 },
		chars = { "f", "F", "F" }, color = "cyan", kind = "frost",
		label = { zh = "冰霜", en = "FROST" }, desc = { zh = "范围减速", en = "slows a group" } },
	-- 电塔：连锁数与连锁距离随级涨（更多跳、更远跳），伤害中等放大。
	TESLA = { cost = 130, power = { 45, 70, 108 }, dmg = 24, rate = 1.40, range = 5.5, chain = 3, chain_range = 3.0, hp = 120,
		up = { dmg = 1.55, rate = 0.9, range = 1.2 },
		chain_by = { 3, 4, 5 }, chain_range_by = { 3.0, 3.6, 4.4 },
		chars = { "t", "T", "T" }, color = "purple", kind = "tesla", ignore_armor = true,
		label = { zh = "电塔", en = "TESLA" }, desc = { zh = "连锁电击，破甲", en = "chain, no armor" } },
	-- 喷火：伤害/灼烧/溅射都涨，射程几乎不涨（近距武器）；连续伤不占冷却。
	FLAME = { cost = 115, power = { 40, 62, 96 }, dmg = 13, dps = true, range = 3.0, splash = 2.0, hp = 130,
		burn_dps = 6, burn_time = 2.0,
		up = { dmg = 1.7, range = 0.8 },
		burn_by = { 6, 11, 18 }, splash_by = { 2.0, 2.6, 3.2 },
		chars = { "l", "L", "L" }, color = "red", kind = "flame", ignore_armor = true,
		label = { zh = "喷火", en = "FLAME" }, desc = { zh = "近距持续灼烧", en = "short-range burn" } },
	-- 激光：贯穿一条线上的全部敌人。线宽升级**克制**（1/1/2，满级才到 2）与攻速加成放缓
	-- （up.rate 0.9）——贯穿+高伤本就强，升级再叠粗细/攻速会一枝独秀，这里压一头。
	LASER = { cost = 120, power = { 50, 78, 120 }, dmg = 26, rate = 1.0, range = 7.0, thickness = 1, hp = 110,
		up = { dmg = 1.7, rate = 0.9 }, thickness_by = { 1, 1, 2 },
		chars = { "n", "N", "N" }, color = "magenta", kind = "laser",
		label = { zh = "激光炮", en = "LASER" }, desc = { zh = "贯穿整线的光束", en = "pierces a line" } },
	-- 地狱塔：锁定 N 个目标持续掉血，锁定越久伤害越高（3s 内线性升到 3×）；dmg 存的是 dps。
	HELL = { cost = 150, power = { 55, 85, 130 }, dmg = 8, dps = true, range = 5.0, lock = 1, hp = 110,
		up = { dmg = 1.6, range = 1.0 }, lock_by = { 1, 2, 3 },
		chars = { "y", "Y", "Y" }, color = "red", kind = "hell",
		label = { zh = "地狱塔", en = "HELL" }, desc = { zh = "锁定灼烧渐增", en = "lock & ramp burn" } },
	-- 狙击：极远单体、高伤、慢，无视护甲。
	SNIPER = { cost = 140, power = { 45, 70, 108 }, dmg = 90, rate = 2.4, range = 9.0, hp = 100,
		up = { dmg = 1.85, range = 2.5, rate = 0.94 },
		chars = { "s", "S", "S" }, color = "gray", kind = "sniper", ignore_armor = true,
		label = { zh = "狙击塔", en = "SNIPER" }, desc = { zh = "超远单体高伤", en = "long-range sniper" } },
	-- 迫击炮：抛射(shell)延迟 ~0.5s 落地，落点范围伤害；溅射半径随级涨。
	MORTAR = { cost = 135, power = { 50, 78, 120 }, dmg = 40, rate = 1.6, range = 8.0, splash = 2.2, hp = 120,
		up = { dmg = 1.7, rate = 0.9, range = 1.0 }, splash_by = { 2.2, 2.8, 3.4 },
		chars = { "m", "M", "M" }, color = "orange", kind = "mortar",
		label = { zh = "迫击炮", en = "MORTAR" }, desc = { zh = "抛射落点范围伤害", en = "lobbed splash" } },
	-- 雷达：光环增益随级走 aura_by（L1 {+25%,+15%} → L3 {+55%,+35%}）；自身无伤害档。
	RADAR = { cost = 100, power = { 25, 40, 60 }, dmg = 0, rate = 0, range = 4.0, aura_range = 0.25, aura_rate = 0.15, hp = 70,
		up = { range = 1.5 }, aura_by = { { 0.25, 0.15 }, { 0.38, 0.24 }, { 0.55, 0.35 } },
		chars = { "r", "R", "R" }, color = "yellow", kind = "radar",
		label = { zh = "雷达", en = "RADAR" }, desc = { zh = "光环：友塔增强", en = "aura: buff allies" } },
	-- 维修塔：不攻击，周期治疗范围内受损友军（治疗量/频率/目标数随等级走，见 heal）。
	REPAIR = { cost = 90, power = { 25, 40, 60 }, dmg = 0, range = 4.0, hp = 80,
		heal = { time = { 4, 3, 2 }, count = { 1, 2, 3 }, amount = { 10, 14, 18 } },
		chars = { "h", "H", "H" }, color = "green", kind = "repair",
		label = { zh = "维修", en = "REPAIR" }, desc = { zh = "治疗受损友塔", en = "heals allies" } },
	-- 反应堆：不攻击，只作**电源**（范围供电）；射程对它无意义（up.range=0）。
	-- supply = 各级供电量；升级只拉高供电（不耗电、无攻击档）。
	REACTOR = { cost = 60, power = { 0, 0, 0 }, dmg = 0, rate = 0, range = 0, supply = { 60, 100, 150 }, hp = 80,
		up = { range = 0 },
		chars = { "R", "R", "R" }, color = "blue", kind = "reactor",
		label = { zh = "反应堆", en = "REACTOR" }, desc = { zh = "范围供电", en = "area power" } },
	-- 采矿机：不攻击，周期把金币"挖"出来（小幅、**不随波次膨胀**）；代价是**吃电最凶**
	-- （L1 就要 60 电 ≈ 整个 L1 反应堆），逼你为它专门拉电——纯经济塔的取舍就在这。
	MINER = { cost = 100, power = { 60, 90, 125 }, dmg = 0, range = 0, hp = 90,
		up = { range = 0 },
		mine = { time = { 6, 6, 6 }, amount = { 5, 9, 14 } },
		chars = { "$", "$", "$" }, color = "yellow", kind = "miner",
		label = { zh = "采矿机", en = "MINER" }, desc = { zh = "周期产金，吃电", en = "generates gold" } },
}

-- 塔的显示名（随界面语言）。UI 一律用它，别直接印 type 这个内部键。
function Towers.label(name) return phos.lang.pick(Towers.TYPES[name].label) end

-- 塔的一句话功能简介（随界面语言）——侧栏显示在名字下面。
function Towers.desc(name) return phos.lang.pick(Towers.TYPES[name].desc) end

-- 建造面板里的循环顺序（含反应堆、维修）。Z/X 键按这个顺序切。
Towers.ORDER = { "GUN", "CANNON", "FROST", "TESLA", "FLAME", "LASER", "HELL",
	"SNIPER", "MORTAR", "RADAR", "REPAIR", "REACTOR", "MINER" }

Towers.PRIORITIES = { "FIRST", "STRONG", "CLOSE", "AIR" }

local function hypot(x, y) return math.sqrt(x * x + y * y) end

-- 取"按等级数组成员"的第 lvl 项（arr 可能缺项/越界，此时回退 default）。
-- 特殊升级轴（溅射/连锁/锁定/光环…）都用它读，避免每处写 arr[lvl] or fallback。
function Towers.by(arr, lvl, default)
	if arr and arr[lvl] ~= nil then return arr[lvl] end
	return default
end

-- 升到下一级要多少金币：L2 = ceil(cost*0.8)，L3 = ceil(cost*1.2)。已满级返回 nil。
function Towers.upgrade_cost(t)
	if t.level >= 3 then return nil end
	local base = Towers.TYPES[t.type].cost
	local mul = (t.level == 1) and 0.8 or 1.2
	return math.ceil(base * mul)
end

-- 拆塔返还累计投入（造价 + 已花升级费）的 60%。
function Towers.refund(t)
	return math.floor(t.spent * 0.6)
end

-- 塔的**有效**属性（含等级与光环）。aura=true 表示被雷达覆盖：
-- 加减成取自"覆盖它的那座雷达"（update 时按最强的一座写进 t.aura_range/t.aura_rate），
-- 而不是从目标塔自己的类型里读（那样 GUN 等没有 aura_* 字段的塔永远吃不到光环）。
-- 三轴乘子/加值改读每型 up 档案（缺省 1.6 / 0.88 / 1.5）：冰塔 up.dmg=1.0 不再堆伤害，
-- 雷达 up.rate=1.0/反应堆无攻速也就不会凭空长攻速。签名保持 dmg, range, interval。
function Towers.stats(t, aura)
	local d = Towers.TYPES[t.type]
	local lvl = t.level
	local up = d.up or {}
	local dmg = (d.dmg or 0) * ((up.dmg or 1.6) ^ (lvl - 1))
	local range = (d.range or 0) + (up.range or 1.5) * (lvl - 1)
	local interval = (d.rate or 0) * ((up.rate or 0.88) ^ (lvl - 1))
	if aura then
		range = range * (1 + (t.aura_range or 0)) -- 雷达光环：射程 +25%
		if d.rate and d.rate > 0 then
			interval = interval / (1 + (t.aura_rate or 0)) -- 攻速 +15%（连续塔无间隔，改在结算里加速度）
		end
	end
	return dmg, range, interval
end

-- ── 电力：范围供电（DESIGN §6.4）──────────────────────────────────────
-- 电源的**供电半径**（格）：反应堆 **4**、基地磁芯 **5**。
-- 反应堆 4 格：直径 9 的区域放得下一座反应堆 + 其 L2 能带的 ~5 台中型塔（60/100 供电是真正的
--   瓶颈；半径只决定"够不够得着"）——比 5 更"局部"，逼玩家沿防线铺多座反应堆而非一塔管一片。
-- 基地 5 格（比反应堆略大）：磁芯周边一圈铺满，开局内圈免费供电够用。
-- 核心生成据此选位（map.lua 用 ≥ 供电半径的留白），保证供电圆不越出地图。
Towers.REACTOR_RADIUS = 4
Towers.CORE_RADIUS = 5
Towers.CORE_SUPPLY = 200

-- 某型塔在 lvl 级的耗电（power = {L1,L2,L3}，反应堆为 0）。
function Towers.power_at(name, lvl)
	lvl = lvl or 1
	local d = Towers.TYPES[name]
	if type(d.power) ~= "table" then return 0 end
	return d.power[lvl] or d.power[1] or 0
end

-- 设备耗电（反应堆是电源、不耗电 → 0）。
function Towers.power_use(t)
	if Towers.TYPES[t.type].kind == "reactor" then return 0 end
	return Towers.power_at(t.type, t.level)
end

-- 电源供电量（按等级）。非反应堆 → 0。
function Towers.power_out(t)
	local d = Towers.TYPES[t.type]
	if d.kind ~= "reactor" then return 0 end
	return d.supply[t.level]
end

-- 敌人到磁芯的"远近"评分：地面看 BFS 步数，飞行看直线距离。
local function threat_distance(e, map, core)
	if e.fly then
		return hypot(e.x - (core.x + 0.5), e.y - (core.y + 0.5))
	end
	local d = map:dist_at(math.floor(e.x), math.floor(e.y))
	if d < 0 then return 1e9 end
	return d
end

-- 按优先级从射程内的敌人里选一个。所有优先级都折算成"分数越大越优先"，
-- 避免 AIR 那种"高/低分两套比较"在多敌时互相顶掉（飞行目标会被后来的地面目标替换）。
function Towers.pick_target(tx, ty, range, enemies, priority, map, core)
	local r2 = range * range
	local best, bestscore = nil, nil
	for _, e in ipairs(enemies) do
		if not e.dead then
			local dx, dy = e.x - tx, e.y - ty
			if dx * dx + dy * dy <= r2 then
				local score
				if priority == "STRONG" then
					score = e.hp
				elseif priority == "CLOSE" then
					score = -(dx * dx + dy * dy)
				elseif priority == "AIR" then
					score = (e.fly and 1e6 or 0) - threat_distance(e, map, core)
				else -- FIRST
					score = -threat_distance(e, map, core)
				end
				if best == nil or score > bestscore then best, bestscore = e, score end
			end
		end
	end
	return best
end

-- 离某点最近的敌人（链式闪电找下一跳用），排除已命中的。
local function nearest_to(px, py, enemies, used, maxr)
	local best, bestd, r2 = nil, nil, maxr * maxr
	for _, e in ipairs(enemies) do
		if not e.dead and not used[e] then
			local dx, dy = e.x - px, e.y - py
			local d2 = dx * dx + dy * dy
			if d2 <= r2 and (bestd == nil or d2 < bestd) then best, bestd = e, d2 end
		end
	end
	return best
end

-- 推进所有塔开火。ctx 由 game 每帧现搭：
--   enemies / map / core / deal_damage(e,dmg,ignore,tower) / add_fx(eff)
-- 范围供电：game 每帧先算好 t.powered；**未通电的设备一律不工作**（不攻击/不治疗/不产金），
-- 也不再有任何"欠压降载"——电够了才动，不够就停（表现见 view 的红 x）。
local function on(t) return t.powered ~= false end

function Towers.update(ts, ctx, dt)
	-- 1) 先清光环，再由每座雷达点亮它覆盖到的塔。多座雷达覆盖同一塔时**取最强的一个**
	--    （加成不叠加）；雷达增益随等级走 aura_by（L1 25%/15% → L3 55%/35%）。
	--    雷达自己没通电就不发光环（它也是用电设备）。
	for _, t in ipairs(ts) do t.aura, t.aura_range, t.aura_rate = false, nil, nil end
	-- 被拆闪烁计时衰减（game 受击时置 0.12）
	for _, t in ipairs(ts) do
		if t.hit_t and t.hit_t > 0 then t.hit_t = math.max(0, t.hit_t - dt) end
	end
	for _, r in ipairs(ts) do
		local rd = Towers.TYPES[r.type]
		if rd.kind == "radar" and on(r) then
			local _, arange = Towers.stats(r, false)
			local r2 = arange * arange
			local ab = Towers.by(rd.aura_by, r.level, { rd.aura_range or 0, rd.aura_rate or 0 })
			local br, ba = ab[1], ab[2]
			for _, t in ipairs(ts) do
				if t ~= r then
					local dx, dy = t.x - r.x, t.y - r.y
					if dx * dx + dy * dy <= r2 then
						t.aura = true
						if not t.aura_range or br > t.aura_range then
							t.aura_range, t.aura_rate = br, ba
						end
					end
				end
			end
		end
	end

	-- 2) 逐塔开火（仅通电的）
	for _, t in ipairs(ts) do
		local d = Towers.TYPES[t.type]
		if d.rate and d.rate > 0 and on(t) then
			t.cd = (t.cd or 0) - dt
			if t.cd <= 0 then
				local dmg, range, interval = Towers.stats(t, t.aura)
				if Towers.fire(t, d, dmg, range, t.priority or "FIRST", ctx) then
					t.cd = interval
				else
					t.cd = 0 -- 没目标不空转：目标一出现就能立刻开火
				end
			end
		end
	end

	-- 3) 火焰是**连续**伤害塔：不占冷却，每帧按 dps×dt 结算。
	--    射程内选中一个目标，向它周围 splash_by 溅射，无视护甲 + 挂燃烧（burn_by）。
	for _, t in ipairs(ts) do
		local d = Towers.TYPES[t.type]
		if d.kind == "flame" and on(t) then
			local dmg, range = Towers.stats(t, t.aura)
			dmg = dmg * (1 + (t.aura_rate or 0)) -- 雷达光环的"攻速"对连续塔体现为 dps 提升
			local ex, ey = t.x + 0.5, t.y + 0.5
			local tgt = Towers.pick_target(ex, ey, range, ctx.enemies,
				t.priority or "FIRST", ctx.map, ctx.core)
			if tgt then
				local r = Towers.by(d.splash_by, t.level, d.splash or 0)
				local r2 = r * r
				local any = false
				for _, o in ipairs(ctx.enemies) do
					if not o.dead then
						local dx, dy = o.x - tgt.x, o.y - tgt.y
						if dx * dx + dy * dy <= r2 then
							any = true
							ctx.deal_damage(o, dmg * dt, true, t)
							Enemies.apply_burn(o, Towers.by(d.burn_by, t.level, d.burn_dps), d.burn_time)
						end
					end
				end
				if any then
					ctx.add_fx({ kind = "flame", x0 = ex, y0 = ey, x = tgt.x, y = tgt.y,
						r = r, color = d.color, t = 0.12 })
				end
			end
		end
	end

	-- 3b) 地狱塔：锁定射程内最多 lock_by 个目标，每帧按 dps×dt 持续掉血，且随"热度"
	--     （锁定秒数）线性升到 3× 封顶；目标死亡或离开射程即解除。锁定表存塔上 t.locked。
	for _, t in ipairs(ts) do
		local d = Towers.TYPES[t.type]
		if d.kind == "hell" and on(t) then
			local dmg, range = Towers.stats(t, t.aura)
			dmg = dmg * (1 + (t.aura_rate or 0))
			local ex, ey = t.x + 0.5, t.y + 0.5
			local r2 = range * range
			local maxn = Towers.by(d.lock_by, t.level, d.lock or 1)
			local locked = t.locked or {}
			t.locked = locked
			-- 清掉已死/已出射程的锁定
			for i = #locked, 1, -1 do
				local e = locked[i].e
				local dx, dy = e.x - ex, e.y - ey
				if e.dead or dx * dx + dy * dy > r2 then table.remove(locked, i) end
			end
			-- 补足名额：从射程内、未被锁的敌人里按优先级挑
			if #locked < maxn then
				local used = {}
				for _, L in ipairs(locked) do used[L.e] = true end
				local pool = {}
				for _, e in ipairs(ctx.enemies) do
					if not e.dead and not used[e] then
						local dx, dy = e.x - ex, e.y - ey
						if dx * dx + dy * dy <= r2 then pool[#pool + 1] = e end
					end
				end
				while #locked < maxn and #pool > 0 do
					local pick = Towers.pick_target(ex, ey, range, pool,
						t.priority or "FIRST", ctx.map, ctx.core)
					if not pick then break end
					locked[#locked + 1] = { e = pick, heat = 0 }
					for i = #pool, 1, -1 do if pool[i] == pick then table.remove(pool, i) end end
				end
			end
			-- 结算：热度 0→3s 对应倍率 1→3
			for _, L in ipairs(locked) do
				L.heat = L.heat + dt
				local mult = 1 + 2 * math.min(L.heat, 3) / 3
				ctx.deal_damage(L.e, dmg * mult * dt, false, t)
				ctx.add_fx({ kind = "hell", x0 = ex, y0 = ey, x1 = L.e.x, y1 = L.e.y,
					heat = L.heat, color = d.color, t = 0.08 })
			end
		end
	end

	-- 4) 维修塔：周期治疗范围内"血量缺口最大"的 N 座友军（不超 max_hp）。
	--    它也要通电（停电就不治）；目标数/治疗量/间隔随等级取自 d.heal。
	for _, t in ipairs(ts) do
		local d = Towers.TYPES[t.type]
		if d.kind == "repair" and on(t) then
			t.cd = (t.cd or 0) - dt
			if t.cd <= 0 then
				local lvl = t.level
				local _, range = Towers.stats(t, t.aura)
				local ex, ey = t.x + 0.5, t.y + 0.5
				local r2 = range * range
				local cands = {}
				for _, o in ipairs(ts) do
					if o ~= t and not o.dead and o.hp < o.max_hp then
						local dx, dy = o.x - t.x, o.y - t.y
						if dx * dx + dy * dy <= r2 then cands[#cands + 1] = o end
					end
				end
				if #cands > 0 then
					-- 缺口大的优先；同缺口按坐标定序，保证确定性
					table.sort(cands, function(a, b)
						local da, db = a.max_hp - a.hp, b.max_hp - b.hp
						if da ~= db then return da > db end
						if a.y ~= b.y then return a.y < b.y end
						return a.x < b.x
					end)
					local n, amount = d.heal.count[lvl], d.heal.amount[lvl]
					local healed_any = false
					for i = 1, math.min(n, #cands) do
						local o = cands[i]
						local before = o.hp
						o.hp = math.min(o.max_hp, o.hp + amount)
						local healed = o.hp - before
						if healed > 0 then
							healed_any = true
							ctx.add_fx({ kind = "heal", x0 = ex, y0 = ey, x1 = o.x + 0.5, y1 = o.y + 0.5,
								amount = healed, t = 0.5 })
						end
					end
					t.cd = healed_any and d.heal.time[lvl] or 0
				else
					t.cd = 0 -- 没伤员不空转：一有人受伤就能立刻开治
				end
			end
		end
	end

	-- 5) 采矿机：周期进账（小幅、不随波次膨胀）。也要通电——停电就不产金。
	for _, t in ipairs(ts) do
		local d = Towers.TYPES[t.type]
		if d.kind == "miner" and on(t) then
			t.cd = (t.cd or 0) - dt
			if t.cd <= 0 then
				local lvl = t.level
				local amount = Towers.by(d.mine.amount, lvl, d.mine.amount[1])
				ctx.earn(amount)
				ctx.add_fx({ kind = "gold", x = t.x + 0.5, y = t.y + 0.5, amount = amount, t = 0.9 })
				t.cd = Towers.by(d.mine.time, lvl, d.mine.time[1])
			end
		end
	end
end

-- 单座塔按类型结算一次攻击。返回是否真的开火了。
function Towers.fire(t, d, dmg, range, priority, ctx)
	local ex, ey = t.x + 0.5, t.y + 0.5

	if d.kind == "gun" then
		local e = Towers.pick_target(ex, ey, range, ctx.enemies, priority, ctx.map, ctx.core)
		if not e then return false end
		local dealt = ctx.deal_damage(e, dmg, false, t)
		ctx.add_fx({ kind = "shot", x0 = ex, y0 = ey, x1 = e.x, y1 = e.y, color = d.color, t = 0.10 })
		ctx.add_fx({ kind = "dmg", x = e.x, y = e.y, amount = dealt, t = 0.7 })
		return true

	elseif d.kind == "cannon" then
		local e = Towers.pick_target(ex, ey, range, ctx.enemies, priority, ctx.map, ctx.core)
		if not e then return false end
		local r = Towers.by(d.splash_by, t.level, d.splash)
		ctx.add_fx({ kind = "boom", x = e.x, y = e.y, r = r, color = d.color, t = 0.25, total = 0.25 })
		for _, o in ipairs(ctx.enemies) do
			if not o.dead then
				local dx, dy = o.x - e.x, o.y - e.y
				if dx * dx + dy * dy <= r * r then
					local dealt = ctx.deal_damage(o, dmg, false, t)
					ctx.add_fx({ kind = "dmg", x = o.x, y = o.y, amount = dealt, t = 0.7 })
				end
			end
		end
		ctx.add_fx({ kind = "shot", x0 = ex, y0 = ey, x1 = e.x, y1 = e.y, color = d.color, t = 0.14 })
		return true

	elseif d.kind == "frost" then
		-- 命中最多 max_targets_by 个：逐个挑"离塔最近且没挑过"的。picked 表当临时剔除集。
		local picked, hits = {}, 0
		for _ = 1, Towers.by(d.max_targets_by, t.level, d.max_targets) do
			local cand
			for _, o in ipairs(ctx.enemies) do
				if not o.dead and not picked[o] then
					local dx, dy = o.x - ex, o.y - ey
					if dx * dx + dy * dy <= range * range then
						if not cand then
							cand = o
						else
							local a = (o.x - ex) ^ 2 + (o.y - ey) ^ 2
							local b = (cand.x - ex) ^ 2 + (cand.y - ey) ^ 2
							if a < b then cand = o end
						end
					end
				end
			end
			if not cand then break end
			picked[cand] = true
			hits = hits + 1
			local dealt = ctx.deal_damage(cand, dmg, false, t)
			Enemies.apply_slow(cand,
				Towers.by(d.slow_by, t.level, d.slow_factor),
				Towers.by(d.slow_time_by, t.level, d.slow_time))
			ctx.add_fx({ kind = "frost", x = cand.x, y = cand.y, t = 0.3, total = 0.3 })
			ctx.add_fx({ kind = "dmg", x = cand.x, y = cand.y, amount = dealt, t = 0.7 })
		end
		return hits > 0

	elseif d.kind == "tesla" then
		local first = Towers.pick_target(ex, ey, range, ctx.enemies, priority, ctx.map, ctx.core)
		if not first then return false end
		local used = {}
		local pts = { { x = ex, y = ey } }
		local cur = first
		local chain_range = Towers.by(d.chain_range_by, t.level, d.chain_range)
		for i = 1, Towers.by(d.chain_by, t.level, d.chain) do
			if not cur then break end
			used[cur] = true
			local dealt = ctx.deal_damage(cur, dmg * (0.7 ^ (i - 1)), true, t)
			ctx.add_fx({ kind = "dmg", x = cur.x, y = cur.y, amount = dealt, t = 0.7 })
			pts[#pts + 1] = { x = cur.x, y = cur.y }
			cur = nearest_to(cur.x, cur.y, ctx.enemies, used, chain_range)
		end
		ctx.add_fx({ kind = "chain", pts = pts, color = d.color, t = 0.18 })
		return true

	elseif d.kind == "laser" then
		-- 朝目标方向的射线：命中射程内、在射线前方、离射线 ≤ 半宽的所有敌人（贯穿）。
		local e = Towers.pick_target(ex, ey, range, ctx.enemies, priority, ctx.map, ctx.core)
		if not e then return false end
		local dx, dy = e.x - ex, e.y - ey
		local len = hypot(dx, dy)
		if len < 1e-6 then return false end
		local ux, uy = dx / len, dy / len
		local half = Towers.by(d.thickness_by, t.level, d.thickness or 1)
		local hits = 0
		for _, o in ipairs(ctx.enemies) do
			if not o.dead then
				local vx, vy = o.x - ex, o.y - ey
				local proj = vx * ux + vy * uy
				if proj >= 0 and proj <= range and math.abs(vx * uy - vy * ux) <= half then
					local dealt = ctx.deal_damage(o, dmg, false, t)
					ctx.add_fx({ kind = "dmg", x = o.x, y = o.y, amount = dealt, t = 0.7 })
					hits = hits + 1
				end
			end
		end
		ctx.add_fx({ kind = "laser", x0 = ex, y0 = ey, x1 = ex + ux * range, y1 = ey + uy * range,
			thickness = half, color = d.color, t = 0.16 })
		return hits > 0

	elseif d.kind == "sniper" then
		local e = Towers.pick_target(ex, ey, range, ctx.enemies, priority, ctx.map, ctx.core)
		if not e then return false end
		local dealt = ctx.deal_damage(e, dmg, true, t) -- 无视护甲
		ctx.add_fx({ kind = "sniper", x0 = ex, y0 = ey, x1 = e.x, y1 = e.y, color = d.color, t = 0.14 })
		ctx.add_fx({ kind = "dmg", x = e.x, y = e.y, amount = dealt, t = 0.8 })
		return true

	elseif d.kind == "mortar" then
		-- 抛射：只落一枚 shell fx，落地结算交给 game.fx_tick（延迟 ~0.5s + 范围伤害）。
		local e = Towers.pick_target(ex, ey, range, ctx.enemies, priority, ctx.map, ctx.core)
		if not e then return false end
		local r = Towers.by(d.splash_by, t.level, d.splash or 0)
		ctx.add_fx({ kind = "shell", x0 = ex, y0 = ey, x1 = e.x, y1 = e.y, total = 0.5,
			dmg = dmg, r = r, tower = t, color = d.color, t = 0.5 })
		return true
	end
	return false
end

return Towers

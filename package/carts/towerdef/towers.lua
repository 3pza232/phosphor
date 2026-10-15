-- towers.lua —— 塔类型表、升级/返还计算、目标选择与开火结算。
--
-- 数据驱动 + 无 UI：加一种塔只加一行；换 towers.lua 就换一套炮塔。
-- 开火逻辑通过 ctx（game 现搭的一张接口表）触达敌人与特效，自己不持有 game——
-- 于是这一层可以脱离 game 单测，也说明它没有偷偷读键盘/画东西。
--
-- 颜色同样只存**色板槽位名**，绘制时才解析。

local Enemies = require("enemies") -- 冰塔/火焰要往敌人身上挂 slow / burn 状态

local Towers = {}

-- 每个字段：cost 金币 / power 电力占用 / dmg / rate(攻击间隔秒) / range(格) /
-- chars 三级字符 / color 槽位 / kind 机制 / ignore_armor 无视护甲。
Towers.TYPES = {
	GUN = { cost = 50, power = 1, dmg = 9, rate = 0.35, range = 5.0,
		chars = { "g", "G", "G" }, color = "green", kind = "gun",
		label = { zh = "机枪", en = "GUN" } },
	CANNON = { cost = 95, power = 2, dmg = 34, rate = 1.25, range = 6.0, splash = 1.6,
		chars = { "c", "C", "C" }, color = "orange", kind = "cannon",
		label = { zh = "加农炮", en = "CANNON" } },
	FROST = { cost = 70, power = 2, dmg = 5, rate = 0.70, range = 5.0, max_targets = 3,
		slow_factor = 0.55, slow_time = 1.8,
		chars = { "f", "F", "F" }, color = "cyan", kind = "frost",
		label = { zh = "冰霜", en = "FROST" } },
	TESLA = { cost = 130, power = 3, dmg = 24, rate = 1.40, range = 5.5, chain = 3, chain_range = 3.0,
		chars = { "t", "T", "T" }, color = "purple", kind = "tesla", ignore_armor = true,
		label = { zh = "电塔", en = "TESLA" } },
	FLAME = { cost = 115, power = 3, dmg = 13, dps = true, range = 3.0, splash = 2.0,
		burn_dps = 6, burn_time = 2.0,
		chars = { "l", "L", "L" }, color = "red", kind = "flame", ignore_armor = true,
		label = { zh = "喷火", en = "FLAME" } },
	RADAR = { cost = 100, power = 2, dmg = 0, rate = 0, range = 4.0, aura_range = 0.25, aura_rate = 0.15,
		chars = { "r", "R", "R" }, color = "yellow", kind = "radar",
		label = { zh = "雷达", en = "RADAR" } },
	REACTOR = { cost = 60, power = 0, dmg = 0, rate = 0, range = 0, cap = { 10, 16, 24 },
		chars = { "R", "R", "R" }, color = "blue", kind = "reactor",
		label = { zh = "反应堆", en = "REACTOR" } },
}

-- 塔的显示名（随界面语言）。UI 一律用它，别直接印 type 这个内部键。
function Towers.label(name) return phos.lang.pick(Towers.TYPES[name].label) end

-- 建造面板里的循环顺序（含反应堆）。Y 键按这个顺序切。
Towers.ORDER = { "GUN", "CANNON", "FROST", "TESLA", "FLAME", "RADAR", "REACTOR" }

Towers.PRIORITIES = { "FIRST", "STRONG", "CLOSE", "AIR" }

local function hypot(x, y) return math.sqrt(x * x + y * y) end

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
function Towers.stats(t, aura)
	local d = Towers.TYPES[t.type]
	local lvl = t.level
	local dmg = (d.dmg or 0) * (1.6 ^ (lvl - 1))
	local range = (d.range or 0) + 0.6 * (lvl - 1)
	local interval = (d.rate or 0) * (0.88 ^ (lvl - 1))
	if aura then
		range = range * (1 + (t.aura_range or 0)) -- 雷达光环：射程 +25%
		if d.rate and d.rate > 0 then
			interval = interval / (1 + (t.aura_rate or 0)) -- 攻速 +15%（连续塔无间隔，改在结算里加速度）
		end
	end
	return dmg, range, interval
end

-- 电力占用（升级每级 +1；反应堆不占电，它产电）。
function Towers.power_use(t)
	local d = Towers.TYPES[t.type]
	if d.kind == "reactor" then return 0 end
	return (d.power or 0) + (t.level - 1)
end

-- 反应堆产能（按等级）。
function Towers.power_out(t)
	local d = Towers.TYPES[t.type]
	if d.kind ~= "reactor" then return 0 end
	return d.cap[t.level]
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
--   enemies / map / core / overload(欠压攻速系数) / deal_damage(e,dmg,ignore,tower) / add_fx(eff)
function Towers.update(ts, ctx, dt)
	-- 1) 先清光环，再由每座雷达点亮它覆盖到的塔。多座雷达覆盖同一塔时**取最强的一个**
	--    （加成不叠加）；雷达自身等级按 ×1.6 提效（与攻击塔升级同一档）。
	for _, t in ipairs(ts) do t.aura, t.aura_range, t.aura_rate = false, nil, nil end
	for _, r in ipairs(ts) do
		local rd = Towers.TYPES[r.type]
		if rd.kind == "radar" then
			local _, arange = Towers.stats(r, false)
			local r2 = arange * arange
			local gain = 1.6 ^ (r.level - 1)
			local br = (rd.aura_range or 0) * gain
			local ba = (rd.aura_rate or 0) * gain
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

	-- 2) 逐塔开火。欠压时冷却走得慢 = 有效攻速降（DESIGN §6.4）
	local overload = ctx.overload or 1
	for _, t in ipairs(ts) do
		local d = Towers.TYPES[t.type]
		if d.rate and d.rate > 0 then
			t.cd = (t.cd or 0) - dt * overload
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

	-- 3) 火焰是**连续**伤害塔（DESIGN：13/s、连续）：不占冷却，每帧按 dps×dt 结算。
	--    射程 3.0 里选中一个目标，向它周围 2.0（"半径 2.0 子半径"）溅射，无视护甲 + 挂燃烧。
	for _, t in ipairs(ts) do
		local d = Towers.TYPES[t.type]
		if d.dps then
			local dmg, range = Towers.stats(t, t.aura)
			dmg = dmg * (1 + (t.aura_rate or 0)) -- 雷达光环的"攻速"对连续塔体现为 dps 提升
			local ex, ey = t.x + 0.5, t.y + 0.5
			local tgt = Towers.pick_target(ex, ey, range, ctx.enemies,
				t.priority or "FIRST", ctx.map, ctx.core)
			if tgt then
				local r = d.splash or 0
				local r2 = r * r
				local any = false
				for _, o in ipairs(ctx.enemies) do
					if not o.dead then
						local dx, dy = o.x - tgt.x, o.y - tgt.y
						if dx * dx + dy * dy <= r2 then
							any = true
							ctx.deal_damage(o, dmg * dt * overload, true, t)
							Enemies.apply_burn(o, d.burn_dps, d.burn_time)
						end
					end
				end
				if any then
					ctx.add_fx({ kind = "flame", x = tgt.x, y = tgt.y, r = r, color = d.color, t = 0.12 })
				end
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
		local r = d.splash
		ctx.add_fx({ kind = "boom", x = e.x, y = e.y, r = r, color = d.color, t = 0.25 })
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
		-- 命中最多 3 个：逐个挑"离塔最近且没挑过"的。picked 表当临时剔除集。
		local picked, hits = {}, 0
		for _ = 1, d.max_targets do
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
			Enemies.apply_slow(cand, d.slow_factor, d.slow_time)
			ctx.add_fx({ kind = "frost", x = cand.x, y = cand.y, t = 0.3 })
			ctx.add_fx({ kind = "dmg", x = cand.x, y = cand.y, amount = dealt, t = 0.7 })
		end
		return hits > 0

	elseif d.kind == "tesla" then
		local first = Towers.pick_target(ex, ey, range, ctx.enemies, priority, ctx.map, ctx.core)
		if not first then return false end
		local used = {}
		local pts = { { x = ex, y = ey } }
		local cur = first
		for i = 1, d.chain do
			if not cur then break end
			used[cur] = true
			local dealt = ctx.deal_damage(cur, dmg * (0.7 ^ (i - 1)), true, t)
			ctx.add_fx({ kind = "dmg", x = cur.x, y = cur.y, amount = dealt, t = 0.7 })
			pts[#pts + 1] = { x = cur.x, y = cur.y }
			cur = nearest_to(cur.x, cur.y, ctx.enemies, used, d.chain_range)
		end
		ctx.add_fx({ kind = "chain", pts = pts, color = d.color, t = 0.18 })
		return true
	end
	return false
end

return Towers

-- enemies.lua —— 敌人类型表、生成、移动（地面走寻路场 / 飞行直线）、
-- slow/burn 状态结算与伤害入账。数据驱动：加一种敌人只加一行。
--
-- 这一层不读键盘、不绘制、不出声；死亡赏金/磁芯扣血由 game.lua 统一处理
-- （deal_damage 只负责"掉多少血、死没死"，赏金归谁是 game 的事）。
-- 颜色存**色板槽位名**（"red" 之类），绘制时才经 phos.color 解析——绝不写死 rgb。

local Enemies = {}

-- 基础值（未乘成长/难度系数）。armor = 每击固定减伤；leak = 走到磁芯扣的磁芯血。
-- fly = 无视地形与塔、直线扑磁芯。siege = 拆塔 DPS（走到塔相邻格后按它扣塔 hp）；
-- **刻意压低**：被围攻时塔也能撑住数秒，给出"挡住"的顿感，不至于一触即碎。
Enemies.TYPES = {
	grunt = { char = "o", color = "red", hp = 60, armor = 0, speed = 1.6, leak = 1, bounty = 5, siege = 3 },
	runner = { char = "r", color = "yellow", hp = 40, armor = 0, speed = 3.2, leak = 1, bounty = 6, siege = 2 },
	swarm = { char = ".", color = "magenta", hp = 25, armor = 0, speed = 2.4, leak = 1, bounty = 2, siege = 1.5 },
	armor = { char = "A", color = "gray", hp = 220, armor = 5, speed = 1.0, leak = 2, bounty = 13, siege = 6 },
	shield = { char = "D", color = "cyan", hp = 140, armor = 0, speed = 1.4, leak = 2, bounty = 15, siege = 4,
		shield = 40, shield_regen = 6, shield_delay = 2.0 },
	flyer = { char = "v", color = "green", hp = 90, armor = 0, speed = 2.0, leak = 2, bounty = 10, siege = 3, fly = true },
	boss = { char = "B", color = "red", hp = 2600, armor = 8, speed = 0.8, leak = 10, bounty = 170, siege = 12, boss = true },
}

local function hypot(x, y) return math.sqrt(x * x + y * y) end

-- 造一个敌人。x/y 是**格中心浮点**（格 (cx,cy) 的中心是 cx+0.5, cy+0.5）。
-- factors 里带本波+难度的 hp/speed/reward 乘数。
function Enemies.new(kind, x, y, factors)
	local d = Enemies.TYPES[kind]
	local e = {
		type = kind, x = x, y = y,
		hp = math.floor(d.hp * factors.hp + 0.5),
		max_hp = math.floor(d.hp * factors.hp + 0.5),
		armor = d.armor, speed = d.speed * factors.speed,
		leak = d.leak, bounty = math.floor(d.bounty * factors.reward + 0.5),
		siege = d.siege,
		fly = d.fly or false, boss = d.boss or false,
		shield = 0, shield_max = 0, shield_cd = 0,
		slow_t = 0, slow_factor = 1,
		burn_dps = 0, burn_t = 0,
		-- AI：mode="core" 冲磁芯；mode="tower" 拆 target（reason="wall"/"reactor"）。
		mode = "core", target = nil, reason = nil, retarget_t = 0,
	}
	if d.shield then
		e.shield = d.shield
		e.shield_max = d.shield
		e.shield_cd = 0
	end
	return e
end

-- 有效速度：受 slow 影响。slow_factor=1 表示没被减速。
function Enemies.speed_of(e)
	local f = 1
	if e.slow_t > 0 then f = e.slow_factor end
	return e.speed * f
end

function Enemies.apply_slow(e, factor, time)
	-- 取更强的减速与更长的剩余时间：两个冰塔打同一只不该互相冲淡
	if e.slow_t <= 0 or factor < e.slow_factor then e.slow_factor = factor end
	e.slow_t = math.max(e.slow_t, time)
end

function Enemies.apply_burn(e, dps, time)
	e.burn_dps = math.max(e.burn_dps, dps)
	e.burn_t = math.max(e.burn_t, time)
end

-- 伤害结算：eff = max(1, dmg - armor)（ignore_armor 时直接打满）。
-- 护盾先顶伤害，打穿后才掉血。返回实际造成的伤害（给观察/浮字用）。
function Enemies.damage(e, dmg, ignore_armor)
	local eff = dmg
	if not ignore_armor then eff = math.max(1, dmg - e.armor) end
	local dealt = 0
	if e.shield > 0 then
		local take = math.min(e.shield, eff)
		e.shield = e.shield - take
		dealt = dealt + take
		eff = eff - take
		e.shield_cd = Enemies.TYPES.shield.shield_delay -- 受击后重新计时回充
	end
	if eff > 0 then
		e.hp = e.hp - eff
		dealt = dealt + eff
	end
	return dealt
end

function Enemies.dead(e) return e.hp <= 0 end

-- 每帧状态结算：slow 计时、burn 持续伤害、护盾回充。
-- 返回 burn 造成的总伤害（game 侧据此判"烧死了没有"）。
function Enemies.tick_effects(e, dt)
	if e.slow_t > 0 then
		e.slow_t = e.slow_t - dt
		if e.slow_t <= 0 then e.slow_factor = 1 end
	end
	local burn = 0
	if e.burn_t > 0 then
		e.burn_t = e.burn_t - dt
		burn = e.burn_dps * dt
		e.hp = e.hp - burn
		if e.burn_t <= 0 then e.burn_dps = 0 end
	end
	-- 护盾：脱离受击 shield_delay 秒后按 6/s 回充到上限
	if e.shield_max > 0 then
		if e.shield_cd > 0 then
			e.shield_cd = e.shield_cd - dt
		elseif e.shield < e.shield_max then
			e.shield = math.min(e.shield_max, e.shield + 6 * dt)
		end
	end
	return burn
end

-- ── AI：目标优先级（每个敌人独立）────────────────────────────────────
-- 每 RETARGET 秒或状态变化时重选；"正在拆某座塔"时不切换（直到它倒塌或不再挡路）。
-- 优先级自上而下，首个成立者胜：
--   1) 破墙 P0：到磁芯不可达，或 path_dist > 3×曼哈顿 → 拆就近的挡路塔
--   2) 反应堆 P1：8 格侦察半径内有 REACTOR → 拆最近的反应堆
--   3) 磁芯 P2：沿 BFS 寻路场冲击磁芯（默认）
-- 飞行单位不做 P0（飞越地形），但做 P1；否则直冲磁芯。
local RETARGET = 0.5
local SCOUT_R2 = 64 -- 8 格
local WALL_R2 = 16 -- "就近塔" 4 格
local SLOPE = 3 -- path_dist > SLOPE × 曼哈顿 → 视为被逼绕

-- 朝格中心 (tx,ty) 直线插值（飞行、拆塔走位、P0 兜底都用它）。
local function straight_move(e, tx, ty, dt)
	local dx, dy = tx - e.x, ty - e.y
	local d = hypot(dx, dy)
	local sp = Enemies.speed_of(e) * dt
	if d <= sp or d < 1e-6 then
		e.x, e.y = tx, ty
	else
		e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp
	end
end

-- 是否被玩家的墙逼到"不走直线就太绕"：不可达，或寻路步数 > 3×曼哈顿距离。
local function walled_off(e, ctx)
	local ex, ey = math.floor(e.x), math.floor(e.y)
	local pd = ctx.map:dist_at(ex, ey)
	local md = math.abs(ex - ctx.core.x) + math.abs(ey - ctx.core.y)
	return pd < 0 or pd > SLOPE * md
end

-- 侦察半径内最近的反应堆（r2 为平方半径）。
local function nearest_reactor(e, ctx, r2)
	local best, bestd
	for _, t in ipairs(ctx.towers) do
		if not t.dead and t.type == "REACTOR" then
			local dx, dy = t.x + 0.5 - e.x, t.y + 0.5 - e.y
			local d2 = dx * dx + dy * dy
			if d2 <= r2 and (bestd == nil or d2 < bestd) then best, bestd = t, d2 end
		end
	end
	return best
end

-- P0 的"拆掉能开路的挡路塔"：先看 4 格内最近的塔；一格都没有就退取全局最近的塔。
-- （简化：不强求严格最短路，够用即可——见 DESIGN §AI）
local function pick_wall(e, ctx)
	local best, bestd
	for _, t in ipairs(ctx.towers) do
		if not t.dead then
			local d2 = (t.x + 0.5 - e.x) ^ 2 + (t.y + 0.5 - e.y) ^ 2
			if d2 <= WALL_R2 and (bestd == nil or d2 < bestd) then best, bestd = t, d2 end
		end
	end
	if best then return best end
	for _, t in ipairs(ctx.towers) do
		if not t.dead then
			local d2 = (t.x + 0.5 - e.x) ^ 2 + (t.y + 0.5 - e.y) ^ 2
			if bestd == nil or d2 < bestd then best, bestd = t, d2 end
		end
	end
	return best
end

local function choose(e, ctx)
	if not e.fly and walled_off(e, ctx) then
		local t = pick_wall(e, ctx)
		if t then return "wall", t end
	end
	local r = nearest_reactor(e, ctx, SCOUT_R2)
	if r then return "reactor", r end
	return "core", nil
end

function Enemies.retarget(e, ctx)
	local t = e.target
	local keep = (e.mode == "tower") and t and not t.dead
	if keep and e.reason == "wall" then
		keep = (not e.fly) and walled_off(e, ctx) -- 路通了就不再拆
	elseif keep and e.reason == "reactor" then
		local dx, dy = t.x + 0.5 - e.x, t.y + 0.5 - e.y
		keep = (dx * dx + dy * dy) <= SCOUT_R2 -- 离开侦察圈就重评
	end
	if not keep then
		local reason, nt = choose(e, ctx)
		if reason == "core" then
			e.mode, e.target, e.reason = "core", nil, nil
		else
			e.mode, e.target, e.reason = "tower", nt, reason
		end
	end
	e.retarget_t = RETARGET
end

-- 拆塔：走到目标塔相邻格，然后按 siege×dt 扣它的 hp（倒塌由 game 结算）。
local function assault(e, t, ctx, dt)
	local ex, ey = math.floor(e.x), math.floor(e.y)
	if e.fly then
		if math.abs(ex - t.x) + math.abs(ey - t.y) <= 1 then
			ctx.siege(t, e.siege * dt, e)
		else
			straight_move(e, t.x + 0.5, t.y + 0.5, dt)
		end
		return
	end
	local f = ctx.map:assault_field(t.x, t.y)
	local fd = f[ey * ctx.map.w + ex]
	if fd == 1 then -- BFS 距塔 1 步 = 正交相邻：开拆
		ctx.siege(t, e.siege * dt, e)
		return
	end
	local nxt = (fd and fd > 0) and ctx.map:step_field(f, ex, ey) or nil
	if nxt then
		straight_move(e, nxt.x + 0.5, nxt.y + 0.5, dt)
	else
		straight_move(e, t.x + 0.5, t.y + 0.5, dt) -- 极端地貌兜底：硬走，别原地卡死
	end
end

-- 每帧 AI 推进：重选目标 + 移动/拆塔。ctx 由 game 每帧现搭：
--   map / core / towers / siege(t, amount, enemy) / add_fx(eff)
function Enemies.update(e, ctx, dt)
	local stale = (e.mode == "tower") and (not e.target or e.target.dead)
	e.retarget_t = e.retarget_t - dt
	if e.retarget_t <= 0 or stale then Enemies.retarget(e, ctx) end

	if e.mode == "tower" and e.target and not e.target.dead then
		assault(e, e.target, ctx, dt)
		return
	end

	-- P2：地面沿寻路场走，飞行直线扑磁芯
	if e.fly then
		straight_move(e, ctx.core.x + 0.5, ctx.core.y + 0.5, dt)
	else
		local tgt = ctx.map:step_target(math.floor(e.x), math.floor(e.y))
		if tgt then straight_move(e, tgt.x + 0.5, tgt.y + 0.5, dt) end
	end
end

-- 是否已经到达磁芯（该漏了）：格坐标落在磁芯格上。
function Enemies.at_core(e, core)
	return math.floor(e.x) == core.x and math.floor(e.y) == core.y
end

return Enemies

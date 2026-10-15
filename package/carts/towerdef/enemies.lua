-- enemies.lua —— 敌人类型表、生成、移动（地面走寻路场 / 飞行直线）、
-- slow/burn 状态结算与伤害入账。数据驱动：加一种敌人只加一行。
--
-- 这一层不读键盘、不绘制、不出声；死亡赏金/磁芯扣血由 game.lua 统一处理
-- （deal_damage 只负责"掉多少血、死没死"，赏金归谁是 game 的事）。
-- 颜色存**色板槽位名**（"red" 之类），绘制时才经 phos.color 解析——绝不写死 rgb。

local Enemies = {}

-- 基础值（未乘成长/难度系数）。armor = 每击固定减伤；leak = 走到磁芯扣的磁芯血。
-- fly = 无视地形与塔、直线扑磁芯。
Enemies.TYPES = {
	grunt = { char = "o", color = "red", hp = 60, armor = 0, speed = 1.6, leak = 1, bounty = 6 },
	runner = { char = "r", color = "yellow", hp = 40, armor = 0, speed = 3.2, leak = 1, bounty = 7 },
	swarm = { char = ".", color = "magenta", hp = 25, armor = 0, speed = 2.4, leak = 1, bounty = 3 },
	armor = { char = "A", color = "gray", hp = 220, armor = 5, speed = 1.0, leak = 2, bounty = 15 },
	shield = { char = "D", color = "cyan", hp = 140, armor = 0, speed = 1.4, leak = 2, bounty = 18,
		shield = 40, shield_regen = 6, shield_delay = 2.0 },
	flyer = { char = "v", color = "green", hp = 90, armor = 0, speed = 2.0, leak = 2, bounty = 12, fly = true },
	boss = { char = "B", color = "red", hp = 2600, armor = 8, speed = 0.8, leak = 10, bounty = 200, boss = true },
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
		fly = d.fly or false, boss = d.boss or false,
		shield = 0, shield_max = 0, shield_cd = 0,
		slow_t = 0, slow_factor = 1,
		burn_dps = 0, burn_t = 0,
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

-- 地面移动：沿 BFS 梯度走。目标是"当前格里 dist 最小的邻居"的格中心，
-- 走到格中心附近就自然换下一个。浮点坐标让移动是平滑的（不是逐格跳）。
function Enemies.move_ground(e, map, dt)
	local cx, cy = math.floor(e.x), math.floor(e.y)
	local tgt = map:step_target(cx, cy)
	if not tgt then
		-- 被玩家建塔关进死路（本格四周都到不了磁芯）：直接朝磁芯直线逃。
		-- 纯 BFS 寻路在这里会永久卡住一波怪、让波次永远清不掉（软锁）。
		-- 直线逃让"被自己堵住"变成"漏几个怪"，比死锁好——且这本来也只发生在玩家自找的角落。
		local tx, ty = map.core.x + 0.5, map.core.y + 0.5
		local dx, dy = tx - e.x, ty - e.y
		local d = hypot(dx, dy)
		local sp = Enemies.speed_of(e) * dt
		if d <= sp or d < 1e-6 then
			e.x, e.y = tx, ty
		else
			e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp
		end
		return
	end
	local tx, ty = tgt.x + 0.5, tgt.y + 0.5
	local dx, dy = tx - e.x, ty - e.y
	local d = hypot(dx, dy)
	local sp = Enemies.speed_of(e) * dt
	if d <= sp or d < 1e-6 then
		e.x, e.y = tx, ty
	else
		e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp
	end
end

-- 飞行移动：无视地形，直线插值扑向磁芯格中心。
function Enemies.move_fly(e, core, dt)
	local tx, ty = core.x + 0.5, core.y + 0.5
	local dx, dy = tx - e.x, ty - e.y
	local d = hypot(dx, dy)
	local sp = Enemies.speed_of(e) * dt
	if d <= sp or d < 1e-6 then
		e.x, e.y = tx, ty
	else
		e.x, e.y = e.x + dx / d * sp, e.y + dy / d * sp
	end
end

-- 是否已经到达磁芯（该漏了）：格坐标落在磁芯格上。
function Enemies.at_core(e, core)
	return math.floor(e.x) == core.x and math.floor(e.y) == core.y
end

return Enemies

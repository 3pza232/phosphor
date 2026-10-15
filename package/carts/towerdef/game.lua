-- game.lua —— CORE LINE 的规则中枢：场地状态、金币/电力、波次推进、
-- 建/拆/升级、空袭、胜负判定。
--
-- 纪律（cart-format §5）：这一层**不读键盘、不绘制、不出声**——它把"发生了什么"
-- 写进事件表（self.ev）返回给 main.lua，由 main 决定放什么音效、写什么存档。
-- map/towers/enemies/waves 都被它 require，但它自己不 require 音频与存档。
--
-- 坐标：格子 (x,y)，(0,0) 在可玩区左上角；敌人位置是**格中心浮点**。

local Map = require("map")
local Enemies = require("enemies")
local Towers = require("towers")
local Waves = require("waves")

local Game = {}
Game.__index = Game

-- 手感常量（DESIGN 未定的项取合理默认；都是"一改就换手感"的旋钮）
Game.BUILD_TIME = 15 -- 布防期倒计时（秒）
Game.START_CREDITS = 0 -- 0 = 用难度默认；>0 = 调试台覆盖起始金币（DESIGN §12 第三刀）
Game.ENEMY_HP_MULT = 1 -- 调试台：敌人血量额外乘数（DESIGN §12 第三刀）
Game.AIRSTRIKE_DMG = 150 -- 空袭伤害（可被调试台覆盖）
local POWER_BASE = 8 -- 基础电力上限（反应堆在此之上累加）
local AIRSTRIKE_CD = 40
local AIRSTRIKE_RADIUS = 3.0
local AIRSTRIKE_WARN = 0.6

local function hypot(x, y) return math.sqrt(x * x + y * y) end

function Game.new(diff, style, endless)
	local self = setmetatable({}, Game)
	self.diff = diff
	self.endless = endless or false -- 无尽模式：第 20 波不判通关，继续 21、22…
	local _, _, pw, ph = phos.screen.playfield()
	self.MW, self.MH = pw, ph
	self.map = Map.new(pw, ph, style)
	self.map_style = self.map.style -- RANDOM 会在 map 内定下具体风格，这里回报**实际**风格

	local d = Waves.DIFF[diff] or Waves.DIFF.NORMAL
	self.core_max = d.core
	self.core_hp = d.core
	self.credits = (Game.START_CREDITS > 0) and Game.START_CREDITS or d.credits
	self.peak_credits = d.credits

	self.phase = "build"
	self.wave = 0
	self.wave_total = Waves.TOTAL
	self.build_timer = Game.BUILD_TIME
	self.next_in = Game.BUILD_TIME

	self.towers = {}
	self.enemies = {}
	self.schedules = {} -- 同时在场的出怪表（最多两拨，见 early_wave）
	self.strikes = {}
	self.fx = {}

	self.airstrike_cd = 0
	self.heal_count = 0 -- 维修塔累计治疗次数（观测/自测用）
	self.towers_lost = 0 -- 被敌人拆倒的塔数（观测/自测用）
	self.build_index = 1 -- 建造面板当前塔型（Towers.ORDER 的下标）
	self.cx = math.floor(pw / 2)
	self.cy = math.floor(ph / 2)
	self.banner = 0

	self.power_used = 0
	self.power_cap = POWER_BASE
	self.overload = false
	self.overload_over = 0 -- 超出上限的比例（0 = 不超）
	self.overload_rate = 1
	self.ev = {}
	self:compute_power()
	return self
end

-- ── 查询 ─────────────────────────────────────────────────────────────

function Game:tower_at(x, y)
	for _, t in ipairs(self.towers) do
		if t.x == x and t.y == y then return t end
	end
	return nil
end

function Game:selected_name()
	return Towers.ORDER[self.build_index]
end

-- 光标格能不能建：地形 + 连通性（map），再叠加"这一格当前没有敌人站着"。
function Game:can_build(x, y)
	if not self.map:can_build(x, y) then return false end
	for _, e in ipairs(self.enemies) do
		if not e.dead and math.floor(e.x) == x and math.floor(e.y) == y then return false end
	end
	return true
end

-- ── 建造 / 拆除 / 升级 ────────────────────────────────────────────────

-- 返回 (ok, reason)：失败时 reason 给 main 决定提示（金币不足 / 会堵死路）。
function Game:build(x, y)
	local name = self:selected_name()
	local d = Towers.TYPES[name]
	if self.credits < d.cost then return false, "credits" end
	if not self:can_build(x, y) then return false, "blocked" end
	self.credits = self.credits - d.cost
	self.map:set(x, y, Map.TOWER)
	self.map:compute_field() -- 墙变了：全局寻路场立刻重算（核心博弈点）
	local t = { type = name, x = x, y = y, level = 1, cd = 0, kills = 0,
		priority = "FIRST", spent = d.cost,
		hp = d.hp, max_hp = d.hp, hit_t = 0 }
	self.towers[#self.towers + 1] = t
	return true
end

function Game:sell(x, y)
	local t = self:tower_at(x, y)
	if not t then return false end
	self.credits = self.credits + Towers.refund(t)
	self.map:set(x, y, Map.GRASS)
	self.map:compute_field()
	for i, o in ipairs(self.towers) do
		if o == t then table.remove(self.towers, i) break end
	end
	return true
end

function Game:upgrade(x, y)
	local t = self:tower_at(x, y)
	if not t then return false, "none" end
	local cost = Towers.upgrade_cost(t)
	if not cost then return false, "max" end
	if self.credits < cost then return false, "credits" end
	self.credits = self.credits - cost
	t.level = t.level + 1
	t.spent = t.spent + cost
	t.cd = 0 -- 升级立即刷新冷却，反馈干脆
	return true
end

-- backspace：循环选中塔的目标优先级。
function Game:cycle_priority(x, y)
	local t = self:tower_at(x, y)
	if not t then return false end
	for i, p in ipairs(Towers.PRIORITIES) do
		if p == t.priority then
			t.priority = Towers.PRIORITIES[(i % #Towers.PRIORITIES) + 1]
			return true
		end
	end
	return false
end

-- ── 塔被拆（敌人 siege）──────────────────────────────────────────────
-- 敌人站到塔相邻格后每帧按 siege×dt 扣它 hp；归零即倒塌：还地、重算寻路场、
-- 移出 towers、**无返还**，并给一个倒塌特效与事件（DESIGN §B）。
function Game:siege_tower(t, amount, e)
	if t.dead then return end
	t.hp = t.hp - amount
	t.hit_t = 0.12 -- 让 view 把这座塔闪红，表现"正在被拆"
	if t.hp <= 0 then self:collapse_tower(t) end
end

function Game:collapse_tower(t)
	t.dead = true
	t.hp = 0
	self.towers_lost = self.towers_lost + 1
	self.map:set(t.x, t.y, Map.GRASS) -- 还地（塔倒墙倒）
	self.map:compute_field() -- 路可能通了：立即重算，其他人改道
	self:add_fx({ kind = "collapse", x = t.x + 0.5, y = t.y + 0.5, r = 1.2, color = "gray", t = 0.5 })
	self.ev.tower_down = true
end

-- 本帧结束后把倒塌的塔从列表移除（迭代敌人时不宜就地删）。
function Game:sweep_towers()
	local kept = {}
	for _, t in ipairs(self.towers) do
		if not t.dead then kept[#kept + 1] = t end
	end
	self.towers = kept
end

-- ── 空袭 ─────────────────────────────────────────────────────────────

function Game:airstrike()
	if self.airstrike_cd > 0 then return false end
	self.airstrike_cd = AIRSTRIKE_CD
	self.strikes[#self.strikes + 1] = { x = self.cx, y = self.cy, t = AIRSTRIKE_WARN }
	self.ev.airstrike = true
	return true
end

-- 对 (cx,cy) 周围 radius 内的敌人结算伤害（空袭无视护甲）。
function Game:explode(cx, cy, radius, dmg)
	local ex, ey = cx + 0.5, cy + 0.5
	self:add_fx({ kind = "boom", x = ex, y = ey, r = radius, color = "white", t = 0.35 })
	for _, e in ipairs(self.enemies) do
		if not e.dead then
			local dx, dy = e.x - ex, e.y - ey
			if dx * dx + dy * dy <= radius * radius then
				local dealt = self:deal_damage(e, dmg, true, nil)
				self:add_fx({ kind = "dmg", x = e.x, y = e.y, amount = dealt, t = 1.0 })
			end
		end
	end
end

-- ── 伤害入账（赏金 / 击杀计数都在这里） ──────────────────────────────

function Game:deal_damage(e, dmg, ignore_armor, tower)
	if e.dead then return 0 end
	local dealt = Enemies.damage(e, dmg, ignore_armor)
	if Enemies.dead(e) then
		e.dead = true
		self.credits = self.credits + e.bounty
		if tower then tower.kills = tower.kills + 1 end
		self.ev.kill = true
		if e.boss then self.ev.boss_kill = true end
	end
	return dealt
end

function Game:add_fx(eff)
	eff.t = eff.t or 0.2
	if eff.kind == "heal" then self.heal_count = self.heal_count + 1 end
	self.fx[#self.fx + 1] = eff
end

-- 采矿机等"主动进账"：直接加钱并记一个事件（供音效）。
function Game:earn(amount)
	if amount and amount > 0 then
		self.credits = self.credits + amount
		self.ev.earn = true
	end
end

-- ── 电力 ─────────────────────────────────────────────────────────────

function Game:compute_power()
	local used, cap = 0, POWER_BASE
	for _, t in ipairs(self.towers) do
		used = used + Towers.power_use(t)
		cap = cap + Towers.power_out(t)
	end
	self.power_used = used
	self.power_cap = cap
	self.overload = used > cap
	-- 欠压：按"超出上限的比例"降载——攻速/射程/连续伤/雷达光环都乘它（见 towers.update）。
	-- 例：12/8 → 超出 50% → 系数 0.5；下限 0.2 保底，不至于全场停摆。
	self.overload_over = self.overload and (used - cap) / cap or 0
	self.overload_rate = self.overload and math.max(0.2, 1 - self.overload_over) or 1
end

-- ── 波次 ─────────────────────────────────────────────────────────────

function Game:start_wave()
	self.wave = self.wave + 1
	self.phase = "combat"
	local groups_def = Waves.groups(self.wave, self.endless)
	local f = Waves.factors(self.wave, self.diff, self.endless)
	f.hp = f.hp * Game.ENEMY_HP_MULT
	local groups = {}
	for _, g in ipairs(groups_def) do
		groups[#groups + 1] = {
			type = g[1], count = g[2], interval = math.max(0.05, g[3]),
			gate = g[4], spawned = 0, timer = 0,
		}
	end
	-- 每波一份**独立的出怪表**：于是允许两波同时在场上（战斗中提前招下一波，见 early_wave）
	self.schedules[#self.schedules + 1] = { wave = self.wave, groups = groups, factors = f }
	self.banner = 1.8
	self.ev.wave_start = self.wave
end

-- 一份出怪表是否已把怪出完。
local function schedule_done(s)
	for _, g in ipairs(s.groups) do
		if g.spawned < g.count then return false end
	end
	return true
end

-- 提前放波：build 期随时可放（按剩余秒数给奖金）；combat 期也能放，但场上**最多同时两拨**——
-- 两拨都还在（有活口或还没出完）就不能再招，直到某一拨被清干净。贪快有代价，也有上限。
function Game:early_wave()
	if self.phase == "build" then
		local bonus = math.floor(math.max(0, self.build_timer)) * 2
		self.credits = self.credits + bonus
		self.ev.early_bonus = bonus
		self:start_wave()
		return true
	elseif self.phase == "combat" then
		if self:active_waves() >= 2 then return false end
		self:start_wave()
		return true
	end
	return false
end

-- 场上"还算数"的波有几拨：活着的敌军各带的 wave ∪ 还没出完的出怪表。
-- 一拨被清干净（怪全灭且出完）就从这个计数里退出——这正是"清掉一拨才能再招"的判据。
function Game:active_waves()
	local seen, n = {}, 0
	local function add(w) if w and not seen[w] then seen[w] = true; n = n + 1 end end
	for _, e in ipairs(self.enemies) do
		if not e.dead and not e.leaked then add(e.wave) end
	end
	for _, s in ipairs(self.schedules) do
		if not schedule_done(s) then add(s.wave) end
	end
	return n
end

function Game:spawn_enemy(g, factors, wave)
	local gates = self.map.gates
	if #gates == 0 then return end
	local gate
	if g.gate then gate = gates[g.gate] else gate = gates[phos.sys.random(1, #gates)] end
	local e = Enemies.new(g.type, gate.x + 0.5, gate.y + 0.5, factors)
	e.wave = wave -- 记下"这只来自第几波"，供 active_waves 判定能不能再招
	self.enemies[#self.enemies + 1] = e
end

function Game:spawn_tick(dt)
	for _, s in ipairs(self.schedules) do
		for _, g in ipairs(s.groups) do
			if g.spawned < g.count then
				g.timer = g.timer - dt
				while g.timer <= 0 and g.spawned < g.count do
					self:spawn_enemy(g, s.factors, s.wave)
					g.spawned = g.spawned + 1
					g.timer = g.timer + g.interval
				end
			end
		end
	end
end

function Game:all_spawned()
	for _, s in ipairs(self.schedules) do
		if not schedule_done(s) then return false end
	end
	return true
end

function Game:remaining_spawn()
	local rem = 0
	for _, s in ipairs(self.schedules) do
		for _, g in ipairs(s.groups) do
			if g.spawned < g.count then
				local r = g.timer + (g.count - g.spawned - 1) * g.interval
				if r > rem then rem = r end
			end
		end
	end
	return math.max(0, rem)
end

-- ── 每帧推进 ─────────────────────────────────────────────────────────

function Game:update(dt)
	self.ev = {}
	if self.phase == "won" or self.phase == "over" then
		return self.ev
	end
	-- 特效老化（放最前：本帧新加的效果 t 从满值开始）
	self:fx_tick(dt)
	if self.banner > 0 then self.banner = math.max(0, self.banner - dt) end
	if self.airstrike_cd > 0 then self.airstrike_cd = math.max(0, self.airstrike_cd - dt) end

	-- 空袭落点：预警结束后爆炸
	for i = #self.strikes, 1, -1 do
		local s = self.strikes[i]
		s.t = s.t - dt
		if s.t <= 0 then
			self:explode(s.x, s.y, AIRSTRIKE_RADIUS, Game.AIRSTRIKE_DMG)
			self.ev.boom = true
			table.remove(self.strikes, i)
		end
	end

	self:compute_power()

	-- 塔每帧都跑（布防期也跑）：采矿机在布防期照产钱；无敌人时开火逻辑自然空转。
	local ctx = {
		enemies = self.enemies, map = self.map, core = self.map.core,
		overload = self.overload_rate,
		deal_damage = function(e, dmg, ig, tower) return self:deal_damage(e, dmg, ig, tower) end,
		add_fx = function(eff) self:add_fx(eff) end,
		earn = function(n) self:earn(n) end,
	}
	Towers.update(self.towers, ctx, dt)

	if self.phase == "build" then
		self.build_timer = self.build_timer - dt
		self.next_in = math.max(0, self.build_timer)
		if self.build_timer <= 0 then self:start_wave() end
	elseif self.phase == "combat" then
		self:spawn_tick(dt)
		self:move_enemies(dt)
		self:sweep()
		self.next_in = self:remaining_spawn()
		self:check_end()
	end

	self:track_peak()
	return self.ev
end

function Game:fx_tick(dt)
	for i = #self.fx, 1, -1 do
		local f = self.fx[i]
		f.t = f.t - dt
		if f.t <= 0 then
			-- 迫击炮弹到期落地：这里才是"结算时刻"（发射时只记落点与伤害）
			if f.kind == "shell" then self:resolve_shell(f) end
			table.remove(self.fx, i)
		end
	end
end

-- 迫击炮弹落地：落点范围伤害 + 一个 boom。塔归属沿用发射它的那座塔（击杀计数）。
-- 落点固定为发射时瞄准的 (x1,y1)，不追踪移动目标——抛射武器本就打提前量。
function Game:resolve_shell(f)
	local x, y, r = f.x1, f.y1, f.r or 0
	self:add_fx({ kind = "boom", x = x, y = y, r = r, color = f.color or "orange",
		t = 0.28, total = 0.28 })
	local r2 = r * r
	for _, e in ipairs(self.enemies) do
		if not e.dead then
			local dx, dy = e.x - x, e.y - y
			if dx * dx + dy * dy <= r2 then
				local dealt = self:deal_damage(e, f.dmg, false, f.tower)
				self:add_fx({ kind = "dmg", x = e.x, y = e.y, amount = dealt, t = 0.7 })
			end
		end
	end
end

function Game:move_enemies(dt)
	local core = self.map.core
	-- ctx：把敌人 AI 需要的东西打包（enemies.lua 不持有 game，与 towers 同一套约定）。
	local ctx = {
		map = self.map, core = core, towers = self.towers,
		siege = function(t, amt, e) self:siege_tower(t, amt, e) end,
		add_fx = function(eff) self:add_fx(eff) end,
	}
	for _, e in ipairs(self.enemies) do
		if not e.dead then
			local burn = Enemies.tick_effects(e, dt)
			if burn > 0 and Enemies.dead(e) then
				e.dead = true
				self.credits = self.credits + e.bounty -- 烧死的也赏（无塔归属）
				self.ev.kill = true
			end
			if not e.dead then
				Enemies.update(e, ctx, dt)
				-- 拆塔中的敌人路过磁芯格不算漏（它的目标不是磁芯）
				if e.mode ~= "tower" and Enemies.at_core(e, core) then
					e.leaked = true
					self.core_hp = self.core_hp - e.leak
					self.ev.leak = true
				end
			end
		end
	end
	self:sweep_towers() -- 本帧被拆倒的塔在这之后才从列表移除
end

function Game:sweep()
	local kept = {}
	for _, e in ipairs(self.enemies) do
		if not e.dead and not e.leaked then kept[#kept + 1] = e end
	end
	self.enemies = kept
end

function Game:check_end()
	if self.core_hp <= 0 then
		self.core_hp = 0
		self.phase = "over"
		self.ev.over = true
		return
	end
	if self:all_spawned() and #self.enemies == 0 and self.phase == "combat" then
		-- 波清空：发奖金；第 20 波清完即通关（无尽模式不判通关，继续下一波）
		self.credits = self.credits + 15 + 2 * self.wave
		self.ev.wave_clear = true
		if self.wave >= self.wave_total and not self.endless then
			self.phase = "won"
			self.ev.won = true
		else
			self.phase = "build"
			self.build_timer = Game.BUILD_TIME
			self.next_in = Game.BUILD_TIME
			self.schedules = {}
		end
	end
end

-- 峰值金币：best_score 用（金币峰值 + 波数×100）。
function Game:track_peak()
	if self.credits > self.peak_credits then self.peak_credits = self.credits end
end

return Game

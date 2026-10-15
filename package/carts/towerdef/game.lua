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

function Game.new(diff, style)
	local self = setmetatable({}, Game)
	self.diff = diff
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
	self.groups = {}
	self.strikes = {}
	self.fx = {}

	self.airstrike_cd = 0
	self.build_index = 1 -- 建造面板当前塔型（Towers.ORDER 的下标）
	self.cx = math.floor(pw / 2)
	self.cy = math.floor(ph / 2)
	self.banner = 0

	self.power_used = 0
	self.power_cap = POWER_BASE
	self.overload = false
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
		priority = "FIRST", spent = d.cost }
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
	self.fx[#self.fx + 1] = eff
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
	-- 欠压：全场有效攻速乘 max(0.25, cap/used)。塔冷却按这个系数走（见 towers.update）。
	self.overload_rate = self.overload and math.max(0.25, cap / used) or 1
end

-- ── 波次 ─────────────────────────────────────────────────────────────

function Game:start_wave()
	self.wave = self.wave + 1
	self.phase = "combat"
	local groups = Waves.groups(self.wave)
	local f = Waves.factors(self.wave, self.diff)
	f.hp = f.hp * Game.ENEMY_HP_MULT
	self.spawn_factors = f
	self.groups = {}
	for _, g in ipairs(groups) do
		self.groups[#self.groups + 1] = {
			type = g[1], count = g[2], interval = math.max(0.05, g[3]),
			gate = g[4], spawned = 0, timer = 0,
		}
	end
	self.banner = 1.8
	self.ev.wave_start = self.wave
end

-- build 期按 space：提前放波，拿按剩余秒数算的奖金。
function Game:early_wave()
	if self.phase ~= "build" then return false end
	local bonus = math.floor(math.max(0, self.build_timer)) * 2
	self.credits = self.credits + bonus
	self.ev.early_bonus = bonus
	self:start_wave()
	return true
end

function Game:spawn_enemy(g)
	local gates = self.map.gates
	if #gates == 0 then return end
	local gate
	if g.gate then gate = gates[g.gate] else gate = gates[phos.sys.random(1, #gates)] end
	local e = Enemies.new(g.type, gate.x + 0.5, gate.y + 0.5, self.spawn_factors)
	self.enemies[#self.enemies + 1] = e
end

function Game:spawn_tick(dt)
	for _, g in ipairs(self.groups) do
		if g.spawned < g.count then
			g.timer = g.timer - dt
			while g.timer <= 0 and g.spawned < g.count do
				self:spawn_enemy(g)
				g.spawned = g.spawned + 1
				g.timer = g.timer + g.interval
			end
		end
	end
end

function Game:all_spawned()
	for _, g in ipairs(self.groups) do
		if g.spawned < g.count then return false end
	end
	return true
end

function Game:remaining_spawn()
	local rem = 0
	for _, g in ipairs(self.groups) do
		if g.spawned < g.count then
			local r = g.timer + (g.count - g.spawned - 1) * g.interval
			if r > rem then rem = r end
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

	if self.phase == "build" then
		self.build_timer = self.build_timer - dt
		self.next_in = math.max(0, self.build_timer)
		if self.build_timer <= 0 then self:start_wave() end
	elseif self.phase == "combat" then
		self:spawn_tick(dt)
		-- ctx：把"塔需要知道的"打包给它（towers.lua 不持有 game）
		local ctx = {
			enemies = self.enemies, map = self.map, core = self.map.core,
			overload = self.overload_rate,
			deal_damage = function(e, dmg, ig, tower) return self:deal_damage(e, dmg, ig, tower) end,
			add_fx = function(eff) self:add_fx(eff) end,
		}
		Towers.update(self.towers, ctx, dt)
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
		if f.t <= 0 then table.remove(self.fx, i) end
	end
end

function Game:move_enemies(dt)
	local core = self.map.core
	for _, e in ipairs(self.enemies) do
		if not e.dead then
			local burn = Enemies.tick_effects(e, dt)
			if burn > 0 and Enemies.dead(e) then
				e.dead = true
				self.credits = self.credits + e.bounty -- 烧死的也赏（无塔归属）
				self.ev.kill = true
			end
			if not e.dead then
				if e.fly then
					Enemies.move_fly(e, core, dt)
				else
					Enemies.move_ground(e, self.map, dt)
				end
				if Enemies.at_core(e, core) then
					e.leaked = true
					self.core_hp = self.core_hp - e.leak
					self.ev.leak = true
				end
			end
		end
	end
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
		-- 波清空：发奖金；第 20 波清完即通关
		self.credits = self.credits + 25 + 4 * self.wave
		self.ev.wave_clear = true
		if self.wave >= self.wave_total then
			self.phase = "won"
			self.ev.won = true
		else
			self.phase = "build"
			self.build_timer = Game.BUILD_TIME
			self.next_in = Game.BUILD_TIME
			self.groups = {}
		end
	end
end

-- 峰值金币：best_score 用（金币峰值 + 波数×100）。
function Game:track_peak()
	if self.credits > self.peak_credits then self.peak_credits = self.credits end
end

return Game

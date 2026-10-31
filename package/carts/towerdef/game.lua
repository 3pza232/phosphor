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
Game.BUILD_TIME = 60 -- 每波等待时间（秒）；提前放波奖金按"省下的等待比例"给（见 early_wave）
Game.START_CREDITS = 0 -- 0 = 用难度默认；>0 = 调试台覆盖起始金币（DESIGN §12 第三刀）
Game.ENEMY_HP_MULT = 1 -- 调试台：敌人血量额外乘数（DESIGN §12 第三刀）
Game.AIRSTRIKE_DMG = 150 -- 空袭伤害（可被调试台覆盖）
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

	self.sources = {} -- 电源列表（反应堆 + 基地），每帧由 compute_power 现算
	self.ev = {}
	-- 首个随机值当场定成"续局种子"：主机没有读当前 RNG 状态的接口，续局只能重新 seed，
	-- 做不到精确续流（详见 DESIGN §9）。存下它，restore 才能让续局后的随机可复现。
	self.rng_seed = phos.sys.random(1, 1000000000)
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

-- 覆盖某格的电源（反应堆或基地）；给侧栏显示"发电 a/n"用。没有则 nil。
function Game:source_at(x, y)
	for _, s in ipairs(self.sources or {}) do
		if s.x == x and s.y == y then return s end
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

-- ── 电力：范围供电 + 贪心分配（DESIGN §6.4）────────────────────────────
-- 电源：每座反应堆（供电半径 = 塔的 `range`，随升级扩张）+ 基地磁芯（Towers.CORE_SUPPLY）。
-- 每帧重算，确定性可复现：
--   1) 电源按"反应堆建造顺序 + 基地最后"定序；每个电源有 供应/已用。
--   2) 用电设备按**建塔顺序**处理（同局可复现）。
--   3) 对每个设备：取覆盖它的所有电源，按"**剩余电量少的优先**"贪心分配——
--      A 剩 10、B 富余、设备要 40 → A 出 10 + B 出 30（范围重叠可跨电源分摊；
--      单设备需求超过任一电源时，重叠多个电源会**串起来供**）。
--   4) 合计仍不足 → 该设备**不工作**（powered=false），且**耗电记 0**（不占任何电源）。
function Game:compute_power()
	local sources = {}
	for _, t in ipairs(self.towers) do
		if Towers.TYPES[t.type].kind == "reactor" then
			local _, radius = Towers.stats(t, t.aura) -- 供电半径随等级扩张（4/5/6）
			sources[#sources + 1] = { x = t.x, y = t.y, kind = "reactor",
				supply = Towers.power_out(t), used = 0,
				radius = radius, tower = t }
		end
	end
	sources[#sources + 1] = { x = self.map.core.x, y = self.map.core.y, kind = "core",
		supply = Towers.CORE_SUPPLY, used = 0, radius = Towers.CORE_RADIUS }
	self.sources = sources

	for _, t in ipairs(self.towers) do
		local draw = Towers.power_use(t)
		t.draw = draw
		t.srcs = {}
		t.powered = (draw <= 0)
		if draw > 0 then
			-- 覆盖它的电源（带下标，用于平局定序）
			local cov = {}
			for si = 1, #sources do
				local s = sources[si]
				local dx, dy = s.x - t.x, s.y - t.y
				if dx * dx + dy * dy <= s.radius * s.radius then
					cov[#cov + 1] = { s = s, i = si }
				end
			end
			local function remaining(c) return c.s.supply - c.s.used end
			-- 剩余少的优先；平局按电源定序（确定性）
			table.sort(cov, function(a, b)
				local ra, rb = remaining(a), remaining(b)
				if ra ~= rb then return ra < rb end
				return a.i < b.i
			end)
			local avail = 0
			for _, c in ipairs(cov) do avail = avail + remaining(c) end
			if avail >= draw then
				local need = draw
				for _, c in ipairs(cov) do
					if need <= 0 then break end
					local take = math.min(remaining(c), need)
					if take > 0 then
						c.s.used = c.s.used + take
						need = need - take
						t.srcs[#t.srcs + 1] = c.i
					end
				end
				t.powered = true
			else
				t.powered = false -- 合计不足：不工作、耗电记 0（已不占任何电源）
			end
		end
	end
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

-- 提前放波：奖励 = 满额等待金 max_bonus(所招波号) 按"省下的等待比例"折算。
--   build 期：ratio = 剩余秒 / BUILD_TIME（0~1）→ bonus = round(ratio × max_bonus)。
--             剩得越多拿越多：整段等待刚结束就招 ≈ 满额，快等完才招 ≈ 0。
--   combat 期：波没清完就招下一波 = 整段等待全免 → **满额**（这也是"贪快该最多"的那个上限）。
-- combat 期场上**最多同时两拨**（两拨都在就不能再招，直到某一拨被清干净）。
-- 满额曲线 max_bonus 在 waves.lua（数据层），这里只管"按比例发多少"。
function Game:early_wave()
	if self.phase == "build" then
		local ratio = math.max(0, math.min(1, self.build_timer / Game.BUILD_TIME))
		local bonus = math.floor(ratio * Waves.wait_bonus_max(self.wave + 1) + 0.5)
		self.credits = self.credits + bonus
		self.ev.early_bonus = bonus
		self:start_wave()
		return true
	elseif self.phase == "combat" then
		if self:active_waves() >= 2 then return false end
		local bonus = Waves.wait_bonus_max(self.wave + 1)
		self.credits = self.credits + bonus
		self.ev.early_bonus = bonus
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

-- ── 存档快照（结构化表 → phos.save 的 v2 值类型）──────────────────────
-- 版本 2。顶层字段具名；浮点一律存"毫单位整数"（q3 写出 / u3 读回，与旧格式 %.3f 的精度
-- 等价），否则 JSON 的 17 位有效数字会把"每个值 4096 字节"的额度吃光（api-reference phos.save）。
-- 实体/波次用位置数组 + 末尾默认值截断：常见的"无护盾 / 无燃烧 / 无锁定"只占一行短数字。
-- 地图 2565 格放不进数组（纯数字就 >5KB）：map.runs 是 (游程, 值) 对的扁平整数数组，按
-- count*8+value 打包（值 0..5 → count = floor(code/8)、value = code%8）。
--
-- 兼容：v1 的"整串 RLE 快照"仍可恢复——decode_v1 把它读成与 v2 同构的表，再走同一条
-- restore 路径；写出 v2 表后旧字符串自然被覆盖。v1 只读不写：RLE 文本**解码**仅在此保留，
-- 旧的单行快照编码已删除。
local SNAP_VERSION = 2

-- 定点：×1000 取整 / 逆变换
local function q3(x) return math.floor((x or 0) * 1000 + 0.5) end
local function u3(m) return (m or 0) / 1000 end

-- 存档的整数读回是 JSON 双精度：传给 phos.* / sol 接口且要求 integer 的字段，
-- 必须先显式转回整数（严格类型检查会拒收 4.0 这类"整值浮点"，如 screen.blend / sys.seed）。
local function i(v, default)
	v = v or default or 0
	return math.tointeger(v) or math.floor(v)
end

local E_INDEX, T_INDEX, P_INDEX = {}, {}, {}
for i, k in ipairs(Enemies.ORDER) do E_INDEX[k] = i end
for i, k in ipairs(Towers.ORDER) do T_INDEX[k] = i end
for i, k in ipairs(Towers.PRIORITIES) do P_INDEX[k] = i end

-- 格值（0..5）→ 游程数组，元素 = 游程*8 + 值
local function encode_runs(cells, n)
	local runs, i = {}, 0
	while i < n do
		local v = cells[i] or 0
		local j = i + 1
		while j < n and cells[j] == v do j = j + 1 end
		runs[#runs + 1] = (j - i) * 8 + v
		i = j
	end
	return runs
end

-- 游程数组 → 格数组（多余游程截断，绝不越过 w*h）
local function decode_runs(runs, n)
	local cells, idx = {}, 0
	for _, code in ipairs(runs or {}) do
		local count = math.floor(code / 8)
		local v = code % 8
		for _ = 1, count do
			if idx >= n then return cells end
			cells[idx] = v
			idx = idx + 1
		end
	end
	return cells
end

-- 行 = 定长数组去掉末尾默认值（缺 = 默认）：默认值表只列非 0 的列
local function row(values, defaults)
	local n = #values
	while n > 0 and values[n] == (defaults[n] or 0) do n = n - 1 end
	local out = {}
	for i = 1, n do out[i] = values[i] end
	return out
end

-- 塔行：类型下标,x,y,级,cd,击杀,优先级下标,投入,hp,max_hp,受击计时,锁定数,[敌人下标,热量]…
local TOWER_DEFAULTS = { [4] = 1, [7] = 1 }
-- 敌人行：类型下标,x,y,hp,max_hp,速度,赏金,护盾,护盾cd,减速剩余,减速系数,燃烧dps,燃烧剩余,
--         波号,mode,reason,重定向计时,标记,目标塔下标
local ENEMY_DEFAULTS = { [11] = 1000 } -- 减速系数 1.0 = 没被减速

-- ── v1 兼容：旧单行快照 → v2 同构表（只读路径）──────────────────────────
-- 旧格式定义见 dev/DESIGN.md §9.1。格仍是同一套 RLE 文本，故解码函数保留在这一段。
local function decode_v1_cells(str, n)
	local cells, idx, i, len = {}, 0, 1, #str
	while i <= len do
		local v = tonumber(string.sub(str, i, i))
		i = i + 1
		if v == nil then break end -- 串坏了就停：宁少格不崩
		local count = 0
		while i <= len do
			local b = string.byte(str, i)
			if b and b >= 97 and b <= 122 then
				count = count * 26 + (b - 96)
				i = i + 1
			else
				break
			end
		end
		if count < 1 then count = 1 end
		for _ = 1, count do cells[idx] = v; idx = idx + 1 end
	end
	return cells
end

-- v1 里按 %.3f 存的字段（其余是整数）
local V1_FIXED = { [2] = true, [3] = true, [4] = true, [5] = true, [6] = true, [8] = true,
	[9] = true, [10] = true, [11] = true, [12] = true, [13] = true, [17] = true }

local function decode_v1(str)
	local rec = {}
	for part in string.gmatch(str, "([^;]+)") do rec[string.sub(part, 1, 1)] = part end
	if not (rec.H and rec.M and rec.C) then return nil end
	local function split(s, sep)
		local out, i = {}, 1
		while true do
			local j = string.find(s, sep, i, true)
			if not j then out[#out + 1] = string.sub(s, i); break end
			out[#out + 1] = string.sub(s, i, j - 1)
			i = j + 1
		end
		return out
	end
	local function qf(text) local v = tonumber(text); return v and q3(v) end

	local out = { v = SNAP_VERSION }
	local H = split(rec.H, ",")
	out.diff, out.map_style = H[2], H[3]
	out.endless = (H[4] == "1")
	out.core_max = tonumber(H[5]) or 0
	out.core_hp = tonumber(H[6]) or 0
	out.credits = tonumber(H[7]) or 0
	out.peak_credits = tonumber(H[8]) or 0
	out.phase = H[9]
	out.wave = tonumber(H[10]) or 0
	out.wave_total = tonumber(H[11]) or Waves.TOTAL
	out.build_timer = qf(H[12]) or 0
	out.next_in = qf(H[13]) or 0
	out.airstrike_cd = qf(H[14]) or 0
	out.heal_count = tonumber(H[15]) or 0
	out.towers_lost = tonumber(H[16]) or 0
	out.build_index = tonumber(H[17]) or 1
	out.cx = tonumber(H[18]) or 1
	out.cy = tonumber(H[19]) or 1
	out.banner = qf(H[20]) or 0
	out.rng_seed = tonumber(H[21]) or 0

	local M = split(rec.M, ",")
	local mw, mh = tonumber(M[2]) or 0, tonumber(M[3]) or 0
	if mw * mh <= 0 then local _, _, pw, ph = phos.screen.playfield(); mw, mh = pw, ph end
	local cells = decode_v1_cells(string.sub(rec.C, 3), mw * mh)
	local gates = {}
	local G = split(rec.G or "", ",")
	for k = 1, (tonumber(G[2]) or 0) do
		gates[#gates + 1] = { x = tonumber(G[3 + (k - 1) * 2]) or 0,
			y = tonumber(G[4 + (k - 1) * 2]) or 0 }
	end
	out.map = { core = { x = tonumber(M[4]) or 0, y = tonumber(M[5]) or 0 },
		version = tonumber(M[6]) or 0, gates = gates, runs = encode_runs(cells, mw * mh) }

	local T = split(rec.T or "", ",")
	local ti = 3
	out.towers = {}
	for _ = 1, (tonumber(T[2]) or 0) do
		local r = { tonumber(T[ti]) or 0, q3(tonumber(T[ti + 1])), q3(tonumber(T[ti + 2])),
			tonumber(T[ti + 3]) or 1, q3(tonumber(T[ti + 4])), tonumber(T[ti + 5]) or 0,
			tonumber(T[ti + 6]) or 1, tonumber(T[ti + 7]) or 0, q3(tonumber(T[ti + 8])),
			q3(tonumber(T[ti + 9])), q3(tonumber(T[ti + 10])) }
		local nl = tonumber(T[ti + 11]) or 0
		r[#r + 1] = nl
		ti = ti + 12
		for _ = 1, nl do
			r[#r + 1] = tonumber(T[ti]) or 0
			r[#r + 1] = q3(tonumber(T[ti + 1]))
			ti = ti + 2
		end
		out.towers[#out.towers + 1] = r
	end

	local E = split(rec.E or "", ",")
	local ei = 3
	out.enemies = {}
	for _ = 1, (tonumber(E[2]) or 0) do
		local r = {}
		for f = 1, 19 do
			local raw = tonumber(E[ei + f - 1])
			if raw ~= nil then
				r[f] = V1_FIXED[f] and q3(raw) or raw
			elseif f == 11 then
				r[f] = 1000
			end
		end
		ei = ei + 19
		out.enemies[#out.enemies + 1] = r
	end

	local S = split(rec.S or "", ",")
	local si = 3
	out.schedules = {}
	for _ = 1, (tonumber(S[2]) or 0) do
		local r = { tonumber(S[si]) or 0, q3(tonumber(S[si + 1])), q3(tonumber(S[si + 2])),
			q3(tonumber(S[si + 3])) }
		local ng = tonumber(S[si + 4]) or 0
		r[5] = ng
		si = si + 5
		for _ = 1, ng do
			r[#r + 1] = tonumber(S[si]) or 0
			r[#r + 1] = tonumber(S[si + 1]) or 0
			r[#r + 1] = q3(tonumber(S[si + 2]))
			r[#r + 1] = (S[si + 3] == "-") and 0 or (tonumber(S[si + 3]) or 0)
			r[#r + 1] = tonumber(S[si + 4]) or 0
			r[#r + 1] = q3(tonumber(S[si + 5]))
			si = si + 6
		end
		out.schedules[#out.schedules + 1] = r
	end

	local K = split(rec.K or "", ",")
	local ki = 3
	out.strikes = {}
	for _ = 1, (tonumber(K[2]) or 0) do
		out.strikes[#out.strikes + 1] = { q3(tonumber(K[ki])), q3(tonumber(K[ki + 1])),
			q3(tonumber(K[ki + 2])) }
		ki = ki + 3
	end
	return out
end

-- 当前状态 → v2 表（phos.save.write 直接收表）
function Game:snapshot()
	local tidx, eidx = {}, {}
	for i, t in ipairs(self.towers) do tidx[t] = i end
	for i, e in ipairs(self.enemies) do eidx[e] = i end

	local towers = {}
	for _, t in ipairs(self.towers) do
		local values = { T_INDEX[t.type] or 0, q3(t.x), q3(t.y), t.level, q3(t.cd),
			t.kills or 0, P_INDEX[t.priority] or 1, t.spent or 0, q3(t.hp), q3(t.max_hp),
			q3(t.hit_t) }
		local locked = t.locked or {}
		values[#values + 1] = #locked
		for _, L in ipairs(locked) do
			values[#values + 1] = eidx[L.e] or 0
			values[#values + 1] = q3(L.heat)
		end
		towers[#towers + 1] = row(values, TOWER_DEFAULTS)
	end

	local enemies = {}
	for _, e in ipairs(self.enemies) do
		local values = { E_INDEX[e.type] or 0, q3(e.x), q3(e.y), q3(e.hp), q3(e.max_hp),
			q3(e.speed), e.bounty or 0, q3(e.shield), q3(e.shield_cd), q3(e.slow_t),
			q3(e.slow_factor == nil and 1 or e.slow_factor), q3(e.burn_dps), q3(e.burn_t),
			e.wave or 0, (e.mode == "tower") and 1 or 0,
			(e.reason == "block" and 1) or (e.reason == "reactor" and 2) or 0,
			q3(e.retarget_t), (e.dead and 1 or 0) + (e.leaked and 2 or 0), tidx[e.target] or 0 }
		enemies[#enemies + 1] = row(values, ENEMY_DEFAULTS)
	end

	local schedules = {}
	for _, s in ipairs(self.schedules) do
		local factors = s.factors or {}
		local values = { s.wave, q3(factors.hp), q3(factors.speed), q3(factors.reward),
			#s.groups }
		for _, gr in ipairs(s.groups) do
			values[#values + 1] = E_INDEX[gr.type] or 0
			values[#values + 1] = gr.count
			values[#values + 1] = q3(gr.interval)
			values[#values + 1] = gr.gate or 0
			values[#values + 1] = gr.spawned
			values[#values + 1] = q3(gr.timer)
		end
		schedules[#schedules + 1] = values
	end

	local strikes = {}
	for _, s in ipairs(self.strikes) do
		strikes[#strikes + 1] = { q3(s.x), q3(s.y), q3(s.t) }
	end

	local gates = {}
	for _, ga in ipairs(self.map.gates) do
		gates[#gates + 1] = { x = ga.x, y = ga.y }
	end

	return {
		v = SNAP_VERSION,
		-- 对局头（数字/布尔/字符串按原类型存，读回同类型）
		diff = self.diff, map_style = self.map_style, endless = self.endless and true or false,
		core_max = self.core_max, core_hp = self.core_hp,
		credits = self.credits, peak_credits = self.peak_credits, phase = self.phase,
		wave = self.wave, wave_total = self.wave_total,
		build_timer = q3(self.build_timer), next_in = q3(self.next_in),
		airstrike_cd = q3(self.airstrike_cd),
		heal_count = self.heal_count, towers_lost = self.towers_lost,
		build_index = self.build_index, cx = self.cx, cy = self.cy,
		banner = q3(self.banner), rng_seed = self.rng_seed or 0,
		-- 地图（核心/刷怪口是对象与数组；格是打包游程）
		map = { core = { x = self.map.core.x, y = self.map.core.y },
			version = self.map.version, gates = gates,
			runs = encode_runs(self.map.cells, self.MW * self.MH) },
		schedules = schedules, towers = towers, enemies = enemies, strikes = strikes,
	}
end

-- 从快照重建一局；参数是 v2 表（也接受 v1 字符串，内部经 decode_v1 转成同构表）。
-- 非法/缺失一律安全降级（返回 nil），绝不崩；地图不走 generate（不消耗随机）。
-- 注意：做不到精确续流（主机没有读当前 RNG 状态的接口），建完最后 seed(rng_seed)。
function Game.restore(data)
	if type(data) == "string" then data = decode_v1(data) end
	if type(data) ~= "table" or type(data.map) ~= "table" then return nil end
	if data.v ~= nil and data.v ~= SNAP_VERSION then return nil end
	if type(data.map.runs) ~= "table" then return nil end

	local self = setmetatable({}, Game)
	self.diff = data.diff or "NORMAL"
	self.map_style = data.map_style or "RANDOM"
	self.endless = (data.endless == true or data.endless == 1 or data.endless == "1")
	self.core_max = i(data.core_max)
	self.core_hp = i(data.core_hp)
	self.credits = i(data.credits)
	self.peak_credits = i(data.peak_credits)
	self.phase = data.phase or "build"
	self.wave = i(data.wave)
	self.wave_total = i(data.wave_total, Waves.TOTAL)
	self.build_timer = u3(data.build_timer)
	self.next_in = u3(data.next_in)
	self.airstrike_cd = u3(data.airstrike_cd)
	self.heal_count = i(data.heal_count)
	self.towers_lost = i(data.towers_lost)
	self.build_index = i(data.build_index, 1)
	self.cx = i(data.cx, 1)
	self.cy = i(data.cy, 1)
	self.banner = u3(data.banner)
	local rng_seed = i(data.rng_seed)
	self.rng_seed = rng_seed

	local _, _, w, h = phos.screen.playfield() -- MW/MH 现取（同硬件恒定）
	self.MW, self.MH = w, h

	local map_data = data.map
	local core = map_data.core or {}
	local gates = {}
	for _, ga in ipairs(map_data.gates or {}) do
		gates[#gates + 1] = { x = i(ga.x), y = i(ga.y) }
	end
	local cells = decode_runs(map_data.runs, w * h)
	self.map = Map.from_snapshot(w, h, self.map_style, { x = i(core.x), y = i(core.y) },
		gates, cells, i(map_data.version))

	self.schedules = {}
	for _, r in ipairs(data.schedules or {}) do
		local s = { wave = i(r[1]), groups = {},
			factors = { hp = u3(r[2]), speed = u3(r[3]), reward = u3(r[4]) } }
		local ng = i(r[5])
		local k = 6
		for _ = 1, ng do
			local gate = i(r[k + 3])
			s.groups[#s.groups + 1] = {
				type = Enemies.ORDER[i(r[k])] or "grunt",
				count = i(r[k + 1]),
				interval = u3(r[k + 2]),
				gate = (gate == 0) and nil or gate,
				spawned = i(r[k + 4]),
				timer = u3(r[k + 5]),
			}
			k = k + 6
		end
		self.schedules[#self.schedules + 1] = s
	end

	self.towers = {}
	local locked_refs = {}
	for _, r in ipairs(data.towers or {}) do
		self.towers[#self.towers + 1] = {
			type = Towers.ORDER[i(r[1])] or "GUN",
			x = i(u3(r[2])), y = i(u3(r[3])), -- 格坐标：整数（phos.screen / ui 只收整数）
			level = i(r[4], 1),
			cd = u3(r[5]),
			kills = i(r[6]),
			priority = Towers.PRIORITIES[i(r[7], 1)] or "FIRST",
			spent = i(r[8]),
			hp = u3(r[9]), max_hp = u3(r[10]),
			hit_t = u3(r[11]),
		}
		local refs = {}
		for k = 1, i(r[12]) do
			refs[#refs + 1] = { idx = i(r[12 + 2 * k - 1]), heat = u3(r[12 + 2 * k]) }
		end
		locked_refs[#self.towers] = refs
	end

	self.enemies = {}
	for _, r in ipairs(data.enemies or {}) do
		local kind = Enemies.ORDER[i(r[1])] or "grunt"
		-- 先按基础值造，再逐字段覆盖成存档值（Enemies.new 不碰随机，安全）
		local e = Enemies.new(kind, u3(r[2]), u3(r[3]), { hp = 1, speed = 1, reward = 1 })
		e.hp = u3(r[4])
		e.max_hp = u3(r[5])
		e.speed = u3(r[6])
		e.bounty = i(r[7])
		-- 缺省 = 0（被截掉的默认值），不是"没存"：别让 Enemies.new 给护盾型的预置值顶掉
		e.shield = u3(r[8])
		e.shield_cd = u3(r[9])
		e.slow_t = u3(r[10])
		e.slow_factor = r[11] and u3(r[11]) or 1
		e.burn_dps = u3(r[12])
		e.burn_t = u3(r[13])
		e.wave = i(r[14])
		e.mode = (i(r[15]) == 1) and "tower" or "core"
		local rc = i(r[16])
		e.reason = (rc == 1) and "block" or (rc == 2 and "reactor" or nil)
		e.retarget_t = u3(r[17])
		local flags = i(r[18])
		e.dead = (flags % 2 == 1)
		e.leaked = (flags >= 2)
		e.target = self.towers[i(r[19])] or nil
		self.enemies[#self.enemies + 1] = e
	end

	-- 地狱塔锁定：敌人建好后再把下标解析回对象（非法下标直接丢弃）
	for it, t in ipairs(self.towers) do
		local locked = {}
		for _, ref in ipairs(locked_refs[it] or {}) do
			local e = self.enemies[ref.idx]
			if e then locked[#locked + 1] = { e = e, heat = ref.heat } end
		end
		t.locked = locked
	end

	self.strikes = {}
	for _, r in ipairs(data.strikes or {}) do
		self.strikes[#self.strikes + 1] = { x = i(u3(r[1])), y = i(u3(r[2])), t = u3(r[3]) }
	end

	self.fx = {}
	self.ev = {}
	self:compute_power()
	phos.sys.seed(rng_seed) -- 续局后随机可复现（非精确续流，见上）
	return self
end

return Game

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
-- 电源：每座反应堆（供电 radius=Towers.REACTOR_RADIUS）+ 基地磁芯（Towers.CORE_SUPPLY）。
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
			sources[#sources + 1] = { x = t.x, y = t.y, kind = "reactor",
				supply = Towers.power_out(t), used = 0,
				radius = Towers.REACTOR_RADIUS, tower = t }
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

-- ── 存档快照（单行字符串，交给 phos.save）─────────────────────────────
-- 格式：记录用 ';' 分、字段用 ',' 分；浮点一律 %.3f（往返一致：存档值经一次取整，
-- 再存一次仍是同一串）。类型/优先级/目标都存**下标**而不是名字——省字节，值长上限 4096。
-- 地图格值 0..5 用 RLE：`<值数字><游程>`，游程写成 a..z 的双射 26 进制（'a'=1、'z'=26、
-- 'aa'=27…）。数字与字母不相交，因此无需分隔符即可逐段解析（行数=MW*MH 由 restore 校验）。
local f = function(x) return string.format("%.3f", x or 0) end
-- 零值/默认值留空：敌人动辄几十只，省下的字节直接决定快照能否塞进 4096。
-- tonumber("") == nil，restore 侧本就 `or 默认值`，故空串天然回落默认。
local fz = function(x) if not x or x == 0 then return "" end return f(x) end
local function iz(x) if not x or x == 0 then return "" end return tostring(x) end

local E_INDEX, T_INDEX, P_INDEX = {}, {}, {}
for i, k in ipairs(Enemies.ORDER) do E_INDEX[k] = i end
for i, k in ipairs(Towers.ORDER) do T_INDEX[k] = i end
for i, k in ipairs(Towers.PRIORITIES) do P_INDEX[k] = i end

-- 游程编码（值 0..5 + 双射 26 进制游程长度）。
local function encode_cells(cells, n)
	local out, i = {}, 0
	while i < n do
		local v = cells[i]
		local j = i + 1
		while j < n and cells[j] == v do j = j + 1 end
		local x, s = j - i, ""
		while x > 0 do
			s = string.char(97 + (x - 1) % 26) .. s
			x = math.floor((x - 1) / 26)
		end
		out[#out + 1] = tostring(v) .. s
		i = j
	end
	return table.concat(out)
end

local function decode_cells(str, n)
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

function Game:snapshot()
	local parts = {}
	local tidx, eidx = {}, {}
	for i, t in ipairs(self.towers) do tidx[t] = i end
	for i, e in ipairs(self.enemies) do eidx[e] = i end

	parts[#parts + 1] = table.concat({ "H", self.diff, self.map_style,
		self.endless and 1 or 0, tostring(self.core_max), tostring(self.core_hp),
		tostring(self.credits), tostring(self.peak_credits), self.phase,
		tostring(self.wave), tostring(self.wave_total), f(self.build_timer),
		f(self.next_in), f(self.airstrike_cd), tostring(self.heal_count),
		tostring(self.towers_lost), tostring(self.build_index), tostring(self.cx),
		tostring(self.cy), f(self.banner), tostring(self.rng_seed or 0) }, ",")

	parts[#parts + 1] = table.concat({ "M", tostring(self.MW), tostring(self.MH),
		tostring(self.map.core.x), tostring(self.map.core.y),
		tostring(self.map.version) }, ",")

	parts[#parts + 1] = "C," .. encode_cells(self.map.cells, self.MW * self.MH)

	local G = { "G", tostring(#self.map.gates) }
	for _, ga in ipairs(self.map.gates) do
		G[#G + 1] = tostring(ga.x); G[#G + 1] = tostring(ga.y)
	end
	parts[#parts + 1] = table.concat(G, ",")

	local S = { "S", tostring(#self.schedules) }
	for _, s in ipairs(self.schedules) do
		S[#S + 1] = tostring(s.wave)
		S[#S + 1] = f(s.factors.hp); S[#S + 1] = f(s.factors.speed); S[#S + 1] = f(s.factors.reward)
		S[#S + 1] = tostring(#s.groups)
		for _, gr in ipairs(s.groups) do
			S[#S + 1] = tostring(E_INDEX[gr.type] or 0)
			S[#S + 1] = tostring(gr.count)
			S[#S + 1] = f(gr.interval)
			S[#S + 1] = gr.gate and tostring(gr.gate) or "-"
			S[#S + 1] = tostring(gr.spawned)
			S[#S + 1] = f(gr.timer)
		end
	end
	parts[#parts + 1] = table.concat(S, ",")

	local T = { "T", tostring(#self.towers) }
	for _, t in ipairs(self.towers) do
		T[#T + 1] = tostring(T_INDEX[t.type] or 0)
		T[#T + 1] = tostring(t.x); T[#T + 1] = tostring(t.y)
		T[#T + 1] = tostring(t.level)
		T[#T + 1] = f(t.cd); T[#T + 1] = tostring(t.kills or 0)
		T[#T + 1] = tostring(P_INDEX[t.priority] or 1)
		T[#T + 1] = tostring(t.spent or 0)
		T[#T + 1] = f(t.hp); T[#T + 1] = f(t.max_hp); T[#T + 1] = f(t.hit_t)
		local locked = t.locked or {}
		T[#T + 1] = tostring(#locked)
		for _, L in ipairs(locked) do
			T[#T + 1] = tostring(eidx[L.e] or 0)
			T[#T + 1] = f(L.heat or 0)
		end
	end
	parts[#parts + 1] = table.concat(T, ",")

	local E = { "E", tostring(#self.enemies) }
	for _, e in ipairs(self.enemies) do
		E[#E + 1] = tostring(E_INDEX[e.type] or 0)
		E[#E + 1] = f(e.x); E[#E + 1] = f(e.y)
		E[#E + 1] = f(e.hp); E[#E + 1] = f(e.max_hp)
		E[#E + 1] = f(e.speed); E[#E + 1] = tostring(e.bounty or 0)
		E[#E + 1] = fz(e.shield); E[#E + 1] = fz(e.shield_cd)
		E[#E + 1] = fz(e.slow_t)
		E[#E + 1] = (e.slow_factor == 1) and "" or f(e.slow_factor)
		E[#E + 1] = fz(e.burn_dps); E[#E + 1] = fz(e.burn_t)
		E[#E + 1] = tostring(e.wave or 0)
		E[#E + 1] = (e.mode == "tower") and 1 or ""
		E[#E + 1] = (e.reason == "block") and 1 or (e.reason == "reactor" and 2 or "")
		E[#E + 1] = fz(e.retarget_t)
		E[#E + 1] = iz((e.dead and 1 or 0) + (e.leaked and 2 or 0))
		E[#E + 1] = iz(tidx[e.target])
	end
	parts[#parts + 1] = table.concat(E, ",")

	local K = { "K", tostring(#self.strikes) }
	for _, s in ipairs(self.strikes) do
		K[#K + 1] = f(s.x); K[#K + 1] = f(s.y); K[#K + 1] = f(s.t)
	end
	parts[#parts + 1] = table.concat(K, ",")

	return table.concat(parts, ";")
end

-- 从快照重建一局。非法/缺失一律安全降级（返回 nil 或置 nil），绝不崩。
-- 注意：地图不走 generate（不消耗随机）；建完最后 seed(rng_seed)，让续局后的随机可复现。
-- **做不到**精确续流（主机没有读取当前 RNG 状态的接口），DESIGN §9 已如实写明。
function Game.restore(str)
	if type(str) ~= "string" or str == "" then return nil end
	local rec = {}
	for part in string.gmatch(str, "([^;]+)") do rec[string.sub(part, 1, 1)] = part end
	if not (rec.H and rec.M and rec.C) then return nil end

	local self = setmetatable({}, Game)
	local H = split(rec.H, ",")
	self.diff = H[2]; self.map_style = H[3]; self.endless = (H[4] == "1")
	self.core_max = tonumber(H[5]) or 0
	self.core_hp = tonumber(H[6]) or 0
	self.credits = tonumber(H[7]) or 0
	self.peak_credits = tonumber(H[8]) or 0
	self.phase = H[9]
	self.wave = tonumber(H[10]) or 0
	self.wave_total = tonumber(H[11]) or Waves.TOTAL
	self.build_timer = tonumber(H[12]) or 0
	self.next_in = tonumber(H[13]) or 0
	self.airstrike_cd = tonumber(H[14]) or 0
	self.heal_count = tonumber(H[15]) or 0
	self.towers_lost = tonumber(H[16]) or 0
	self.build_index = tonumber(H[17]) or 1
	self.cx = tonumber(H[18]) or 1
	self.cy = tonumber(H[19]) or 1
	self.banner = tonumber(H[20]) or 0
	local rng_seed = tonumber(H[21]) or 0
	self.rng_seed = rng_seed -- 存回，重复 snapshot 才逐字一致

	local _, _, w, h = phos.screen.playfield() -- MW/MH 现取（同硬件恒定）
	self.MW, self.MH = w, h

	local M = split(rec.M, ",")
	local core = { x = tonumber(M[4]) or 0, y = tonumber(M[5]) or 0 }
	local version = tonumber(M[6]) or 0
	local cells = decode_cells(string.match(rec.C, "^C,(.*)$") or "", w * h)

	local gates = {}
	if rec.G then
		local G = split(rec.G, ",")
		local n = tonumber(G[2]) or 0
		for k = 1, n do
			gates[#gates + 1] = { x = tonumber(G[3 + (k - 1) * 2]) or 0,
				y = tonumber(G[4 + (k - 1) * 2]) or 0 }
		end
	end
	self.map = Map.from_snapshot(w, h, self.map_style, core, gates, cells, version)

	self.schedules = {}
	if rec.S then
		local S = split(rec.S, ",")
		local n, i = tonumber(S[2]) or 0, 3
		for _ = 1, n do
			local s = { wave = tonumber(S[i]) or 0, groups = {},
				factors = { hp = tonumber(S[i + 1]) or 1, speed = tonumber(S[i + 2]) or 1,
					reward = tonumber(S[i + 3]) or 1 } }
			local ng = tonumber(S[i + 4]) or 0
			i = i + 5
			for _ = 1, ng do
				local gt = tonumber(S[i]) or 0
				s.groups[#s.groups + 1] = {
					type = Enemies.ORDER[gt] or "grunt",
					count = tonumber(S[i + 1]) or 0,
					interval = tonumber(S[i + 2]) or 0.1,
					gate = (S[i + 3] == "-") and nil or tonumber(S[i + 3]),
					spawned = tonumber(S[i + 4]) or 0,
					timer = tonumber(S[i + 5]) or 0,
				}
				i = i + 6
			end
			self.schedules[#self.schedules + 1] = s
		end
	end

	self.towers = {}
	local locked_refs = {}
	if rec.T then
		local T = split(rec.T, ",")
		local n, i = tonumber(T[2]) or 0, 3
		for _ = 1, n do
			local t = {
				type = Towers.ORDER[tonumber(T[i]) or 0] or "GUN",
				x = tonumber(T[i + 1]) or 0, y = tonumber(T[i + 2]) or 0,
				level = tonumber(T[i + 3]) or 1,
				cd = tonumber(T[i + 4]) or 0,
				kills = tonumber(T[i + 5]) or 0,
				priority = Towers.PRIORITIES[tonumber(T[i + 6]) or 1] or "FIRST",
				spent = tonumber(T[i + 7]) or 0,
				hp = tonumber(T[i + 8]) or 0, max_hp = tonumber(T[i + 9]) or 0,
				hit_t = tonumber(T[i + 10]) or 0,
			}
			local nl = tonumber(T[i + 11]) or 0
			local refs = {}
			i = i + 12
			for _ = 1, nl do
				refs[#refs + 1] = { idx = tonumber(T[i]) or 0, heat = tonumber(T[i + 1]) or 0 }
				i = i + 2
			end
			locked_refs[#self.towers + 1] = refs
			self.towers[#self.towers + 1] = t
		end
	end

	self.enemies = {}
	if rec.E then
		local E = split(rec.E, ",")
		local n, i = tonumber(E[2]) or 0, 3
		for _ = 1, n do
			local kind = Enemies.ORDER[tonumber(E[i]) or 0] or "grunt"
			-- 先按基础值造，再逐字段覆盖成存档值（Enemies.new 不碰随机，安全）
			local e = Enemies.new(kind, tonumber(E[i + 1]) or 0, tonumber(E[i + 2]) or 0,
				{ hp = 1, speed = 1, reward = 1 })
			e.hp = tonumber(E[i + 3]) or e.hp
			e.max_hp = tonumber(E[i + 4]) or e.max_hp
			e.speed = tonumber(E[i + 5]) or e.speed
			e.bounty = tonumber(E[i + 6]) or e.bounty
			-- 空串 = 存档时该值为 0（fz 留空），不是"没存"：一律回落 0，
			-- 别让 Enemies.new 给护盾型预置的 shield=40 顶掉"护盾已打光"的事实
			e.shield = tonumber(E[i + 7]) or 0
			e.shield_cd = tonumber(E[i + 8]) or 0
			e.slow_t = tonumber(E[i + 9]) or 0
			e.slow_factor = tonumber(E[i + 10]) or 1
			e.burn_dps = tonumber(E[i + 11]) or 0
			e.burn_t = tonumber(E[i + 12]) or 0
			e.wave = tonumber(E[i + 13]) or 0
			e.mode = (tonumber(E[i + 14]) == 1) and "tower" or "core"
			local rc = tonumber(E[i + 15]) or 0
			e.reason = (rc == 1) and "block" or (rc == 2 and "reactor" or nil)
			e.retarget_t = tonumber(E[i + 16]) or 0
			local flags = tonumber(E[i + 17]) or 0
			e.dead = (flags % 2 == 1)
			e.leaked = (flags >= 2)
			e.target = self.towers[tonumber(E[i + 18]) or 0] or nil
			i = i + 19
			self.enemies[#self.enemies + 1] = e
		end
	end

	-- 地狱塔锁定：敌人建好后再把下标解析回对象（非法下标直接丢弃）
	for it, t in ipairs(self.towers) do
		local locked = {}
		for _, r in ipairs(locked_refs[it] or {}) do
			local e = self.enemies[r.idx]
			if e then locked[#locked + 1] = { e = e, heat = r.heat } end
		end
		t.locked = locked
	end

	self.strikes = {}
	if rec.K then
		local K = split(rec.K, ",")
		local n, i = tonumber(K[2]) or 0, 3
		for _ = 1, n do
			self.strikes[#self.strikes + 1] = { x = tonumber(K[i]) or 0,
				y = tonumber(K[i + 1]) or 0, t = tonumber(K[i + 2]) or 0 }
			i = i + 3
		end
	end

	self.fx = {}
	self.ev = {}
	self:compute_power()
	phos.sys.seed(rng_seed) -- 续局后随机可复现（非精确续流，见上）
	return self
end

return Game

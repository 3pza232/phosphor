-- map.lua —— 网格地形、生成、BFS 寻路场与"能不能建"的连通性校验。
--
-- 这一层只管**格子**：地形是什么、从磁芯出发的最短步数、以及"在这格建塔会不会
-- 把敌人关死"。它不认识塔、敌人这些实体，也不读键盘/不绘制。
-- 所有随机一律走 phos.sys.random：同 seed 必须生成同一张图（可复现）。
--
-- 格子用扁平数组存（index = y*w + x），比二维表省一次间接、也让 BFS 好写。
-- 0..5 的取值见下；不可走的格子（岩石/水/塔）在 BFS 里一律当墙。

local Map = {}
Map.__index = Map

Map.GRASS, Map.ROCK, Map.WATER, Map.GATE, Map.CORE, Map.TOWER = 0, 1, 2, 3, 4, 5
-- 地面敌人能踩的格子（磁芯与刷怪口也算路，否则 BFS 到不了目的地）
local PASSABLE = { [Map.GRASS] = true, [Map.GATE] = true, [Map.CORE] = true }

-- 平局时的固定邻居顺序：左→右→上→下（DESIGN §4）。
-- 顺序固定 = 同样的地图每次寻路结果一致，敌人不会"这次走左、下次走右"。
local DIRS = { { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }

-- 取整随机（区间整数）。函数体里才碰 phos：模块顶层加载时主机还没装配完 API。
local function ri(a, b) return phos.sys.random(a, b) end

-- 从磁芯做一次 BFS，返回扁平 dist 表（-1 = 走不到）。block_index 可选：把某格
-- 临时当墙（试占）。生成期与建塔校验共用它，就不再需要"先有 dist 才能算"的顺序。
local function bfs(m, block_index)
	local w, h = m.w, m.h
	local dist = {}
	for i = 0, w * h - 1 do dist[i] = -1 end
	local start = m.core.y * w + m.core.x
	dist[start] = 0
	local q = { start }
	local head = 1
	while head <= #q do
		local cur = q[head]
		head = head + 1
		local cxx = cur % w
		local cyy = (cur - cxx) / w
		local d = dist[cur]
		for k = 1, 4 do
			local nx, ny = cxx + DIRS[k][1], cyy + DIRS[k][2]
			if nx >= 0 and nx < w and ny >= 0 and ny < h then
				local ni = ny * w + nx
				if ni ~= block_index and dist[ni] == -1 and PASSABLE[m.cells[ni]] then
					dist[ni] = d + 1
					q[#q + 1] = ni
				end
			end
		end
	end
	return dist
end

-- 从任意格做一次 BFS（用于敌人"进攻某座塔"的寻路场）。起点可以是墙（塔），
-- 直接以它为 0 播撒，于是它四周的可走格得到 1——敌人走到 dist==1 即贴到塔边。
local function bfs_from(m, sx, sy)
	local w, h = m.w, m.h
	local dist = {}
	for i = 0, w * h - 1 do dist[i] = -1 end
	local start = sy * w + sx
	dist[start] = 0
	local q = { start }
	local head = 1
	while head <= #q do
		local cur = q[head]
		head = head + 1
		local cxx = cur % w
		local cyy = (cur - cxx) / w
		local d = dist[cur]
		for k = 1, 4 do
			local nx, ny = cxx + DIRS[k][1], cyy + DIRS[k][2]
			if nx >= 0 and nx < w and ny >= 0 and ny < h then
				local ni = ny * w + nx
				if dist[ni] == -1 and PASSABLE[m.cells[ni]] then
					dist[ni] = d + 1
					q[#q + 1] = ni
				end
			end
		end
	end
	return dist
end

function Map.new(w, h, style)
	local m = setmetatable({}, Map)
	m.w, m.h = w, h
	m.rand = ri
	m.style = style
	m.gates = {}
	-- 基地磁芯：右侧、且**范围供电圆不越出地图**——留出 ≥ 供电半径的边距，y 居中并夹住
	-- 上下也放得下整圆。（实际供电半径 towers.CORE_RADIUS = 5；这里保守留 6 格边距 +
	-- protect 半径 6 禁撒，于是"供电圆不越界、圆内无遮挡"由构造保证。）
	local CORE_R = 6
	local cy = math.floor(h / 2)
	m.core = { x = w - 2 - CORE_R, y = math.max(CORE_R, math.min(h - 1 - CORE_R, cy)) }
	m.cells = {}
	for i = 0, w * h - 1 do m.cells[i] = Map.GRASS end
	-- 地形/塔每次变动就 version+1：敌人拆塔用的"进攻寻路场"据此失效重算（见 assault_field）。
	m.version = 0
	m.af_cache, m.af_ver = {}, -1
	m:generate(style)
	m:compute_field()
	return m
end

-- 从存档重建一张地图：**不走 generate**（generate 会消耗 phos.sys.random，
-- 毁掉"续局随机可复现"）。直接接管格数组/刷怪口/磁芯，再算一次寻路场。
function Map.from_snapshot(w, h, style, core, gates, cells, version)
	local m = setmetatable({}, Map)
	m.w, m.h = w, h
	m.rand = ri
	m.style = style
	m.core = { x = core.x, y = core.y }
	m.gates = gates
	m.cells = cells
	m.version = version or 0
	m.af_cache, m.af_ver = {}, -1 -- 攻击寻路场缓存作废（version 已变）
	m:compute_field()
	return m
end

function Map:get(x, y)
	if x < 0 or x >= self.w or y < 0 or y >= self.h then return nil end
	return self.cells[y * self.w + x]
end

function Map:set(x, y, v)
	if x < 0 or x >= self.w or y < 0 or y >= self.h then return end
	self.cells[y * self.w + x] = v
	self.version = self.version + 1
end

-- 某格到磁芯的步数（-1 = 走不到）。给敌人寻路与 HUD 观测用。
function Map:dist_at(x, y)
	if x < 0 or x >= self.w or y < 0 or y >= self.h then return -1 end
	return self.dist[y * self.w + x] or -1
end

-- ── 生成 ─────────────────────────────────────────────────────────────

function Map:generate(style)
	if style == "RANDOM" then
		local pick = { "OPEN", "CANALS", "MAZE" }
		style = pick[ri(1, #pick)]
		self.style = style
	end
	local w, h = self.w, self.h

	-- 1) 四周一圈岩石边框：把地图封起来，只在左边留刷怪口
	for x = 0, w - 1 do
		self:set(x, 0, Map.ROCK)
		self:set(x, h - 1, Map.ROCK)
	end
	for y = 0, h - 1 do
		self:set(0, y, Map.ROCK)
		self:set(w - 1, y, Map.ROCK)
	end

	-- 2) 刷怪口：数量按风格（OPEN 1 / CANALS 2 / MAZE 2~3）
	local n_gate = (style == "OPEN") and 1 or (style == "CANALS" and 2 or ri(2, 3))
	local span = h - 8
	for i = 1, n_gate do
		local gy = 4 + math.floor(span * (i - 0.5) / n_gate) + ri(-2, 2)
		gy = math.max(3, math.min(h - 4, gy))
		-- 每个口上下各留一格空，避免贴死在角上
		self:set(0, gy, Map.GATE)
		self:set(1, gy, Map.GRASS)
		self.gates[#self.gates + 1] = { x = 0, y = gy }
	end

	-- 3) 磁芯：右缘内侧一格；周围清出一点空地，别一开局就被岩石埋住
	self:set(self.core.x, self.core.y, Map.CORE)
	for dy = -2, 2 do
		for dx = -2, 2 do
			if math.abs(dx) + math.abs(dy) <= 3 then
				local cx, cy = self.core.x + dx, self.core.y + dy
				-- 别动外围岩壁：磁芯贴着右缘，清空区会够到 x=w-1 那面墙；
				-- 一旦把墙清成空地，磁芯右侧的边框就"漏一段"（看着像缺了块围墙）。
				local on_border = (cx == 0 or cx == w - 1 or cy == 0 or cy == h - 1)
				if not on_border and (self:get(cx, cy) == Map.ROCK or self:get(cx, cy) == Map.WATER) then
					self:set(cx, cy, Map.GRASS)
				end
			end
		end
	end

	-- 4) 按风格撒地形。成簇（随机游走长一块）而不是逐格乱撒——逐格乱撒出的是
	--    均匀噪点，没有"绕来绕去"的迷宫感，也留不出通路。
	if style == "OPEN" then
		for _ = 1, 7 do self:blob(ri(3, w - 4), ri(3, h - 4), ri(4, 9), Map.ROCK) end
	elseif style == "MAZE" then
		for _ = 1, 26 do self:blob(ri(3, w - 4), ri(3, h - 4), ri(6, 16), Map.ROCK) end
		-- 迷宫再补几道直墙：成簇 + 直墙混在一起才"绕"
		for _ = 1, 5 do
			local wx, wy = ri(4, w - 8), ri(3, h - 4)
			local len = ri(4, 10)
			for k = 1, len do self:set(wx + k, wy, Map.ROCK) end
		end
	elseif style == "CANALS" then
		self:canals()
	end

	-- 5) 连通性兜底：任何一个刷怪口到不了磁芯，就强行挖一条 L 形通道。
	--    先挖再判，避免"挖了这条又断了那条"（BFS 每轮重算）。
	for _ = 1, 8 do
		local dist = bfs(self, nil)
		local all_ok = true
		for _, g in ipairs(self.gates) do
			if dist[g.y * self.w + g.x] < 0 then
				all_ok = false
				self:carve(g.x, g.y)
			end
		end
		if all_ok then break end
	end

	-- 兜底过后再确认一次磁芯与口都还在（挖通道时可能路过磁芯/口，保持其类型）
	self:set(self.core.x, self.core.y, Map.CORE)
	for _, g in ipairs(self.gates) do self:set(g.x, g.y, Map.GATE) end
end

-- 成簇长一块地形：从中心随机游走 size 步，每步画上一格。
-- 起点/落点太靠近磁芯、刷怪口、左边通路就跳过——别把开局堵死。
function Map:blob(cx, cy, size, val)
	local x, y = cx, cy
	for _ = 1, size do
		if self:protect(x, y) then return end
		self:set(x, y, val)
		local d = DIRS[ri(1, 4)]
		x, y = x + d[1], y + d[2]
		if x < 2 or x > self.w - 3 or y < 2 or y > self.h - 3 then return end
	end
end

-- 这格是否属于"保护区"（磁芯周围、刷怪口附近、最左两列）——生成时不许被堵。
function Map:protect(x, y)
	if x <= 2 then return true end -- 左边留给刷怪口的通道
	local dx, dy = x - self.core.x, y - self.core.y
	if dx * dx + dy * dy <= 36 then return true end -- 磁芯半径 6 内
	for _, g in ipairs(self.gates) do
		if math.abs(y - g.y) <= 1 then return true end
	end
	return false
end

-- 水道：几条横/竖水带，每条留 1~2 个桥（GRASS 缺口）。水挡地面不挡飞行，
-- 于是"绕桥"与"空袭"各有用武之地。
function Map:canals()
	local w, h = self.w, self.h
	local bands = ri(2, 3)
	for i = 1, bands do
		if ri(0, 1) == 0 then
			-- 纵向水道
			local bx = 8 + math.floor((w - 16) * (i - 0.5) / bands)
			local bridges = { ri(3, h - 4) }
			if ri(0, 1) == 0 then bridges[#bridges + 1] = ri(3, h - 4) end
			for y = 1, h - 2 do
				if not self:protect(bx, y) then
					local is_bridge = false
					for _, by in ipairs(bridges) do
						if math.abs(y - by) <= 0 then is_bridge = true end
					end
					if not is_bridge then self:set(bx, y, Map.WATER) end
				end
			end
		else
			local by = 6 + math.floor((h - 12) * (i - 0.5) / bands)
			local bridges = { ri(4, w - 6) }
			if ri(0, 1) == 0 then bridges[#bridges + 1] = ri(4, w - 6) end
			for x = 3, w - 3 do
				if not self:protect(x, by) then
					local is_bridge = false
					for _, bx in ipairs(bridges) do
						if math.abs(x - bx) <= 1 then is_bridge = true end
					end
					if not is_bridge then self:set(x, by, Map.WATER) end
				end
			end
		end
	end
end

-- 强行从 (gx,gy) 挖一条到磁芯的 L 形通道：先横到磁芯列，再竖到磁芯行。
-- 只在"确实走不通"时用，所以挖得糙一点没关系——它保证地图永远可解。
function Map:carve(gx, gy)
	local cx, cy = self.core.x, self.core.y
	for x = gx, cx do
		local v = self:get(x, gy)
		if v == Map.ROCK or v == Map.WATER or v == Map.TOWER then self:set(x, gy, Map.GRASS) end
	end
	local step = cy >= gy and 1 or -1
	for y = gy, cy, step do
		local v = self:get(cx, y)
		if v == Map.ROCK or v == Map.WATER or v == Map.TOWER then self:set(cx, y, Map.GRASS) end
	end
end

-- ── BFS 寻路场 ───────────────────────────────────────────────────────

-- 从磁芯出发做一次 BFS，得到每格到磁芯的步数。只在建/拆塔时重算（网格最大
-- 57x45=2565 格，一次 BFS 远低于一帧的量级）。
function Map:compute_field()
	self.dist = bfs(self, nil)
end

-- 所有刷怪口是否都还能到磁芯。可选地"多挡一格"（试占）后判定——
-- 这是 can_build 的核心：只要有一个口走不到，这次建造就得拒绝。
function Map:all_gates_reachable(block_index)
	local dist = bfs(self, block_index)
	for _, g in ipairs(self.gates) do
		if dist[g.y * self.w + g.x] < 0 then return false end
	end
	return true
end

-- 所有刷怪口是否都能到磁芯（无阻挡）。HUD/agent 观测用。
function Map:ground_path_exists()
	return self:all_gates_reachable()
end

-- 能不能在这格建（只看地形：空地即可；"有没有敌人站着"由 game.lua 叠加）。
-- 不再做连通性试占——玩家允许把磁芯整个围死，由怪物自己拆墙开路（DESIGN §AI/§B）。
function Map:can_build(x, y)
	return self:get(x, y) == Map.GRASS
end

-- 敌人寻路：在当前格 (cx,cy) 的四个邻居里挑 dist 最小的那个（平局按 DIRS 顺序）。
-- 返回邻居格坐标；找不到活路返回 nil（游戏侧会兜底）。
function Map:step_target(cx, cy)
	local best, bestd = nil, nil
	for k = 1, 4 do
		local nx, ny = cx + DIRS[k][1], cy + DIRS[k][2]
		local v = self:get(nx, ny)
		if v and PASSABLE[v] then
			local d = self:dist_at(nx, ny)
			if d >= 0 and (bestd == nil or d < bestd) then
				bestd, best = d, { x = nx, y = ny }
			end
		end
	end
	return best
end

-- 沿任意寻路场走一步（进攻寻路场用；与 step_target 同构，只是场是传入的）。
function Map:step_field(field, cx, cy)
	local best, bestd = nil, nil
	for k = 1, 4 do
		local nx, ny = cx + DIRS[k][1], cy + DIRS[k][2]
		local v = self:get(nx, ny)
		if v and PASSABLE[v] then
			local d = field[ny * self.w + nx]
			if d and d >= 0 and (bestd == nil or d < bestd) then
				bestd, best = d, { x = nx, y = ny }
			end
		end
	end
	return best
end

-- 从某座塔出发的"进攻寻路场"（敌人据此走到塔相邻格）。按地图 version 缓存：
-- 塔在被拆/新建前不重算，多只敌人打同一座塔共享一场。地形一变（version+1）即失效。
function Map:assault_field(tx, ty)
	if self.af_ver ~= self.version then
		self.af_cache = {}
		self.af_ver = self.version
	end
	local key = ty * self.w + tx
	local f = self.af_cache[key]
	if not f then
		f = bfs_from(self, tx, ty)
		self.af_cache[key] = f
	end
	return f
end

return Map

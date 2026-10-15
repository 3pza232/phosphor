-- view.lua —— 世界绘制：地形、射程轮廓、光标、塔、敌人、特效。
-- 只读状态，绝不改玩法。颜色一律经 phos.color 解析**色板槽位名**（存"red"不存 rgb）。
--
-- 文案不在这里：顶部/底部叠字归 hud.lua，侧栏归 panel.lua。这里只画"战场本身"。

local Towers = require("towers")
local Enemies = require("enemies")

local View = {}

-- 地形字符与颜色槽（DESIGN §2）。空地极稀疏地点几笔 `·`。
local CELL_CHAR = {
	[0] = nil,        -- GRASS：按稀疏图案点
	[1] = "#",        -- ROCK
	[2] = "~",        -- WATER
	[3] = "S",        -- GATE
	[4] = "@",        -- CORE
	[5] = nil,        -- TOWER：由塔自己画
}
local CELL_COLOR = { [1] = "gray", [2] = "blue", [3] = "magenta", [4] = "cyan" }

-- 以 (wx,wy) 为心、半径 r 画一圈字符（爆炸/火焰/脉动用）。稀疏采样避免太密。
local function ring(S, px, py, wx, wy, r, ch, color)
	local cx, cy = math.floor(wx), math.floor(wy)
	local ri = math.max(1, math.floor(r + 0.5))
	local steps = math.max(8, ri * 6)
	for i = 0, steps - 1 do
		local a = (i / steps) * math.pi * 2
		local x = cx + math.floor(math.cos(a) * ri + 0.5)
		local y = cy + math.floor(math.sin(a) * ri + 0.5)
		S.blend(px + x, py + y, ch, color)
	end
end

-- 沿 (x0,y0)→(x1,y1) 每格落一笔（曳光/激光/光束共用）。alt 给了就与 ch 交替，作虚线感。
local function trace(S, px, py, x0, y0, x1, y1, ch, alt, color)
	local dx, dy = x1 - x0, y1 - y0
	local dist = math.sqrt(dx * dx + dy * dy)
	local steps = math.max(1, math.floor(dist + 0.5))
	for i = 0, steps do
		local k = i / steps
		local c = (alt and (i % 2 == 0)) and ch or (alt or ch)
		S.blend(px + math.floor(x0 + dx * k + 0.5), py + math.floor(y0 + dy * k + 0.5), c, color)
	end
end

-- 给方向 (ux,uy) 选一个"像直线"的字符，并给出它的垂直字符（激光加粗时用）。
local function dir_chars(ux, uy)
	if math.abs(ux) >= 0.9 then return "-", "|" end
	if math.abs(uy) >= 0.9 then return "|", "-" end
	if ux * uy >= 0 then return "\\", "/" end
	return "/", "\\"
end

function View.draw(game, C)
	local S = phos.screen
	local px, py = S.playfield()
	local map = game.map

	-- ── 地形 ──
	for y = 0, game.MH - 1 do
		local sy = py + y
		for x = 0, game.MW - 1 do
			local v = map.cells[y * game.MW + x]
			local ch = CELL_CHAR[v]
			if ch then
				S.put(px + x, sy, ch, C[CELL_COLOR[v]])
			elseif v == 0 then
				-- 空地：稀疏点点（确定性图案，不是随机——同画面每帧一致）
				if (x * 7 + y * 11) % 13 == 0 then
					S.put(px + x, sy, "\u{00B7}", C.dark_gray)
				end
			end
		end
	end

	-- ── 建造光标：空心框 + 射程轮廓 + 非法标记 ──
	-- 射程圈的半径随光标下的内容走：塔上 = 那座塔的**实际**射程（含升级/光环），
	-- 空地 = 当前待建造塔型的射程。圈色也跟着，一眼分清自己在看谁的射程。
	local cx, cy = game.cx, game.cy
	local tsel = game:tower_at(cx, cy)
	local range, ring_col
	if tsel then
		local _, r = Towers.stats(tsel, tsel.aura)
		range = r
		ring_col = (tsel.level >= 3) and C[Towers.TYPES[tsel.type].color] or C.white
	else
		local _, r = Towers.stats({ type = game:selected_name(), level = 1 }, false)
		range = r
		ring_col = C.dark_gray
	end
	if range and range > 0 then
		local x0 = math.max(0, math.floor(cx - range - 1))
		local x1 = math.min(game.MW - 1, math.ceil(cx + range + 1))
		local y0 = math.max(0, math.floor(cy - range - 1))
		local y1 = math.min(game.MH - 1, math.ceil(cy + range + 1))
		for y = y0, y1 do
			for x = x0, x1 do
				local d = math.sqrt((x - cx) ^ 2 + (y - cy) ^ 2)
				if math.abs(d - range) < 0.5 then
					S.blend(px + x, py + y, "\u{00B7}", ring_col)
				end
			end
		end
	end
	-- 光标框：用 blend 叠加，不覆盖格子里的塔/敌人字形
	local box = { { -1, -1, "+" }, { 0, -1, "-" }, { 1, -1, "+" },
		{ -1, 0, "|" }, { 1, 0, "|" },
		{ -1, 1, "+" }, { 0, 1, "-" }, { 1, 1, "+" } }
	for _, b in ipairs(box) do
		S.blend(px + cx + b[1], py + cy + b[2], b[3], C.dark_gray)
	end
	if not game:can_build(cx, cy) and not game:tower_at(cx, cy) then
		S.blend(px + cx, py + cy, "x", C.red)
	end

	-- ── 塔 ──
	for _, t in ipairs(game.towers) do
		local d = Towers.TYPES[t.type]
		local ch = d.chars[t.level] or d.chars[1]
		local fg = (t.level >= 3) and C[d.color] or C.white
		-- 正在被拆：闪红（hit_t 由 game 在受击时刷新，towers.update 里衰减）
		if t.hit_t and t.hit_t > 0 and (math.floor(phos.sys.time() * 20) % 2 == 0) then
			fg = C.red
		end
		S.put(px + t.x, py + t.y, ch, fg)

		-- 雷达：每秒一次扩散脉动（点到为止）+ 被覆盖友塔头顶一个极轻的 ·。
		-- 覆盖判定这里现算（不依赖 combat 期才写好的 t.aura），布防期也看得见光环范围。
		if d.kind == "radar" then
			local _, arange = Towers.stats(t, false)
			ring(S, px, py, t.x + 0.5, t.y + 0.5,
				math.max(1, (phos.sys.time() % 1.0) * arange), "\u{00B7}", C.yellow)
			local r2 = arange * arange
			for _, o in ipairs(game.towers) do
				local ox, oy = o.x - t.x, o.y - t.y
				if o ~= t and ox * ox + oy * oy <= r2 then
					S.blend(px + o.x, py + o.y - 1, "\u{00B7}", C.dark_gray)
				end
			end
		-- 反应堆：极轻的慢脉动（供电感），别喧宾夺主。
		elseif d.kind == "reactor" then
			ring(S, px, py, t.x + 0.5, t.y + 0.5,
				math.max(1, (phos.sys.time() % 2.0) / 2.0 * 2.0), "\u{00B7}", C.blue)
		end
	end

	-- ── 敌人 ──
	for _, e in ipairs(game.enemies) do
		if not e.dead then
			local d = Enemies.TYPES[e.type]
			local fg = C[d.color]
			if e.slow_t > 0 then fg = C.cyan end -- 被冻住：一眼看出谁在减速
			S.put(px + math.floor(e.x), py + math.floor(e.y), d.char, fg)
		end
	end

	-- ── 特效 ──（全部用 blend，压在世界之上、不抹掉底下的字形）
	-- 每型一个 kind，画法只读 fx 上的字段；寿命由 game.fx_tick 统一回收，不放超长命的效果。
	for _, f in ipairs(game.fx) do
		local col = C[f.color or "white"]
		if f.kind == "shot" then
			-- 曳光：沿弹道一串 · / -，塔口一个亮字当枪口闪（旧版只点中一个 ·，太素）
			trace(S, px, py, f.x0, f.y0, f.x1, f.y1, "\u{00B7}", "-", col)
			S.blend(px + math.floor(f.x0), py + math.floor(f.y0), "+", C.white)
		elseif f.kind == "boom" then
			-- 爆炸：扩张圆环 + 中心亮点 + 几点爆屑（不同字符）
			local k = 1 - math.max(0, f.t) / (f.total or 0.28)
			local rr = f.r * (0.3 + 0.7 * k)
			ring(S, px, py, f.x, f.y, rr, "*", col)
			S.blend(px + math.floor(f.x), py + math.floor(f.y), "@", C.white)
			local fx0, fy0 = math.floor(f.x), math.floor(f.y)
			for _, b in ipairs({ { 0.0, "+" }, { 2.1, "x" }, { 4.1, "\u{00B7}" }, { 5.4, "+" } }) do
				S.blend(px + fx0 + math.floor(math.cos(b[1]) * rr * 0.7 + 0.5),
					py + fy0 + math.floor(math.sin(b[1]) * rr * 0.7 + 0.5), b[2], col)
			end
		elseif f.kind == "dmg" and f.amount and f.amount >= 1 then
			S.blend(px + math.floor(f.x), py + math.floor(f.y), "\u{00B7}", C.red)
		elseif f.kind == "frost" then
			-- 冰爆：目标格向外扩散的雪花/碎片（* / + / · 混合，短促）
			local k = 1 - math.max(0, f.t) / (f.total or 0.3)
			local rr = 0.6 + 1.4 * k
			local i = 0
			for _, a in ipairs({ 0.0, 1.05, 2.09, 3.14, 4.19, 5.24 }) do
				i = i + 1
				S.blend(px + math.floor(f.x + math.cos(a) * rr + 0.5),
					py + math.floor(f.y + math.sin(a) * rr + 0.5),
					(i % 2 == 0) and "*" or ((i % 3 == 0) and "\u{00B7}" or "+"), C.cyan)
			end
			S.blend(px + math.floor(f.x), py + math.floor(f.y), "*", C.white)
		elseif f.kind == "chain" then
			-- 锯齿闪电：沿两点间逐格垂直抖动偏移，亮头暗尾
			for si = 1, #f.pts - 1 do
				local a, b = f.pts[si], f.pts[si + 1]
				local dx, dy = b.x - a.x, b.y - a.y
				local dist = math.sqrt(dx * dx + dy * dy)
				local steps = math.max(1, math.floor(dist + 0.5))
				local nx, ny = (dist > 1e-6) and (-dy / dist) or 0, (dist > 1e-6) and (dx / dist) or 0
				for i = 0, steps do
					local k = i / steps
					local jit = ((i % 2 == 0) and 0.4 or -0.4) * math.sin(k * math.pi)
					local head = (i >= steps - 1)
					S.blend(px + math.floor(a.x + dx * k + nx * jit + 0.5),
						py + math.floor(a.y + dy * k + ny * jit + 0.5),
						head and "@" or ((i % 2 == 0) and "/" or "\\"),
						head and C.white or col)
				end
			end
		elseif f.kind == "flame" then
			-- 火舌/火锥：从塔口朝目标喷一簇 * / ^，随时间抖动（比旧版的单环像火）
			local x0, y0 = f.x0 or f.x, f.y0 or f.y
			local dx, dy = f.x - x0, f.y - y0
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist > 1e-6 then
				local ux, uy = dx / dist, dy / dist
				local nx, ny = -uy, ux
				for i = 1, 6 do
					local k = i / 6
					local wob = math.sin(f.t * 40 + i * 1.7) * 0.7 * k
					S.blend(px + math.floor(x0 + ux * dist * k + nx * wob + 0.5),
						py + math.floor(y0 + uy * dist * k + ny * wob + 0.5),
						(i % 3 == 0) and "*" or "^", col)
				end
			end
		elseif f.kind == "laser" then
			-- 直线光柱：按方向取 | - / \，thickness 越大越粗（垂直方向加笔）；亮头暗尾
			local dx, dy = f.x1 - f.x0, f.y1 - f.y0
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist > 1e-6 then
				local ux, uy = dx / dist, dy / dist
				local ch, uch = dir_chars(ux, uy)
				local nx, ny = -uy, ux
				local half = math.max(0, (f.thickness or 1) - 1)
				local steps = math.max(1, math.floor(dist + 0.5))
				for i = 0, steps do
					local k = i / steps
					local x, y = f.x0 + dx * k, f.y0 + dy * k
					S.blend(px + math.floor(x + 0.5), py + math.floor(y + 0.5),
						ch, (i >= steps - 1) and C.white or col)
					for j = 1, half do
						S.blend(px + math.floor(x + nx * j + 0.5), py + math.floor(y + ny * j + 0.5), uch, col)
						S.blend(px + math.floor(x - nx * j + 0.5), py + math.floor(y - ny * j + 0.5), uch, col)
					end
				end
			end
		elseif f.kind == "hell" then
			-- 脉冲光束：每个被锁目标一条（红→亮），宽度随热度变粗，用时间做脉冲
			local heat = f.heat or 0
			local pulse = 0.5 + 0.5 * math.sin(phos.sys.time() * 12)
			local beam = (pulse > 0.6) and C.white or C.red
			local dx, dy = f.x1 - f.x0, f.y1 - f.y0
			local dist = math.sqrt(dx * dx + dy * dy)
			if dist > 1e-6 then
				local ux, uy = dx / dist, dy / dist
				local nx, ny = -uy, ux
				local half = (heat >= 1.5) and 1 or 0
				local steps = math.max(1, math.floor(dist + 0.5))
				for i = 0, steps do
					local k = i / steps
					local x, y = f.x0 + dx * k, f.y0 + dy * k
					S.blend(px + math.floor(x + 0.5), py + math.floor(y + 0.5), "~", beam)
					for j = 1, half do
						S.blend(px + math.floor(x + nx * j + 0.5), py + math.floor(y + ny * j + 0.5), "\u{00B7}", col)
						S.blend(px + math.floor(x - nx * j + 0.5), py + math.floor(y - ny * j + 0.5), "\u{00B7}", col)
					end
				end
			end
		elseif f.kind == "sniper" then
			-- 一瞬细长曳光（整条线）+ 命中点火花
			trace(S, px, py, f.x0, f.y0, f.x1, f.y1, "-", "\u{00B7}", C.white)
			S.blend(px + math.floor(f.x1), py + math.floor(f.y1), "*", C.yellow)
		elseif f.kind == "shell" then
			-- 抛物线弧：由 (x0,y0)→(x1,y1) 与进度 1-t/total 纯函数算弧上点（一个 o + 拖尾 ·）
			local p = 1 - math.max(0, f.t) / (f.total or 0.5)
			local dx, dy = f.x1 - f.x0, f.y1 - f.y0
			local dist = math.sqrt(dx * dx + dy * dy)
			local lift = dist * 0.28 + 1.0
			for j = 0, 3 do
				local pp = math.max(0, p - j * 0.07)
				S.blend(px + math.floor(f.x0 + dx * pp + 0.5),
					py + math.floor(f.y0 + dy * pp - math.sin(pp * math.pi) * lift + 0.5),
					(j == 0) and "o" or "\u{00B7}", (j == 0) and col or C.dark_gray)
			end
		elseif f.kind == "heal" then
			-- 维修光束：从塔到被治塔画一条绿色脉冲，起点亮一下，末点冒 +N（DESIGN §C）
			local n = 8
			for i = 0, n do
				local k = i / n
				S.blend(px + math.floor(f.x0 + (f.x1 - f.x0) * k),
					py + math.floor(f.y0 + (f.y1 - f.y0) * k),
					(i == 0) and "*" or ((i % 2 == 0) and "+" or "\u{00B7}"), C.green)
			end
			if f.amount and f.amount >= 1 then
				S.print(px + math.floor(f.x1), py + math.floor(f.y1) - 1,
					"+" .. math.floor(f.amount), C.green)
			end
		elseif f.kind == "collapse" then
			-- 倒塌：灰 x 环 + 几点爆屑
			ring(S, px, py, f.x, f.y, f.r, "x", col)
			local cx0, cy0 = math.floor(f.x), math.floor(f.y)
			for _, b in ipairs({ { 0.7, "\u{00B7}" }, { 2.8, "+" }, { 4.9, "\u{00B7}" } }) do
				S.blend(px + cx0 + math.floor(math.cos(b[1]) * f.r * 0.6 + 0.5),
					py + cy0 + math.floor(math.sin(b[1]) * f.r * 0.6 + 0.5), b[2], col)
			end
		end
	end

	-- ── 空袭预警：落点闪 X（DESIGN §6.5）──
	for _, s in ipairs(game.strikes) do
		local blink = (math.floor(s.t * 10) % 2 == 0)
		if blink then
			S.put(px + s.x, py + s.y, "X", C.red)
		else
			S.put(px + s.x, py + s.y, "X", C.yellow)
		end
	end
end

return View

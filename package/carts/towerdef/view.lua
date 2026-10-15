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

-- 沿直线取一个中点格（弹道只有一格轨迹时用）
local function line_cell(x0, y0, x1, y1)
	local mx, my = (x0 + x1) / 2, (y0 + y1) / 2
	return math.floor(mx), math.floor(my)
end

-- 以 (wx,wy) 为心、半径 r 画一圈字符（爆炸/火焰用）。稀疏采样避免太密。
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
		ring_col = (tsel.level >= 3) and C.white or C[Towers.TYPES[tsel.type].color]
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
		local fg = (t.level >= 3) and C.white or C[d.color]
		S.put(px + t.x, py + t.y, ch, fg)
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
	for _, f in ipairs(game.fx) do
		if f.kind == "shot" then
			local sx, sy = line_cell(f.x0, f.y0, f.x1, f.y1)
			S.blend(px + sx, py + sy, "\u{00B7}", C[f.color or "white"])
		elseif f.kind == "boom" then
			ring(S, px, py, f.x, f.y, f.r, "*", C[f.color or "orange"])
		elseif f.kind == "dmg" and f.amount and f.amount >= 1 then
			S.blend(px + math.floor(f.x), py + math.floor(f.y), "\u{00B7}", C.red)
		elseif f.kind == "frost" then
			S.blend(px + math.floor(f.x), py + math.floor(f.y), "*", C.cyan)
		elseif f.kind == "chain" then
			for _, p in ipairs(f.pts) do
				S.blend(px + math.floor(p.x), py + math.floor(p.y), "~", C[f.color or "purple"])
			end
		elseif f.kind == "flame" then
			ring(S, px, py, f.x, f.y, f.r, "*", C[f.color or "red"])
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

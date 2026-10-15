-- ai.lua —— 怪物行为（DESIGN §8）。
--
-- 铁律：**只读**世界状态、只调用 ctx 提供的查询与 rng，**不绘制、不发声、不改世界**。
-- 决策的结果是一张"意图"表（move/attack/ranged/wait），由 world 去执行与校验。
-- 这样规则模块互相看不见，替换 AI 不会牵动渲染或结算。
--
-- 防卡死（§8.3）：用 BFS 求路而非贪心直走；游荡不进只有一个出口的格；
-- 对角线要求两个正交邻格都可通行；被逼住时允许原地等待。

local AI = {}

local DIRS8 = {
  { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 },
  { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 },
}

-- 视线：与 fov 同一套 Bresenham，只是查询换成 ctx。会穿透墙与否由 ctx.blocks 决定。
local function los(ctx, x0, y0, x1, y1)
  local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
  local sx = (x0 < x1) and 1 or -1
  local sy = (y0 < y1) and 1 or -1
  local err = dx - dy
  local x, y = x0, y0
  while true do
    if not (x == x0 and y == y0) and ctx.blocks(x, y) then
      return (x == x1 and y == y1)
    end
    if x == x1 and y == y1 then break end
    local e2 = 2 * err
    if e2 > -dy then err = err - dy; x = x + sx end
    if e2 < dx then err = err + dx; y = y + sy end
  end
  return true
end

local function diag_ok(ctx, cx, cy, d, phase)
  if d[1] == 0 or d[2] == 0 then return true end
  return (ctx.walkable(cx + d[1], cy) or phase) and (ctx.walkable(cx, cy + d[2]) or phase)
end

-- 该格的可通行"出口数"（4 向里能走的邻居数）。用来避开死胡同。
local function exits(ctx, x, y)
  local n = 0
  if ctx.walkable(x + 1, y) then n = n + 1 end
  if ctx.walkable(x - 1, y) then n = n + 1 end
  if ctx.walkable(x, y + 1) then n = n + 1 end
  if ctx.walkable(x, y - 1) then n = n + 1 end
  return n
end

-- BFS 首步：从 (x,y) 到 (tx,ty)，返回第一步的 (dx,dy) 或 nil。
-- 只在 chase 时对单只怪调用，范围受地图尺寸限制，远低于看门狗预算（§8.3）。
local function first_step(ctx, x, y, tx, ty, phase)
  if x == tx and y == ty then return nil end
  local w, h = ctx.w, ctx.h
  local function key(cx, cy) return cy * w + cx end
  local from = { [key(x, y)] = -1 }
  local qx, qy = { x }, { y }
  local head, found = 1, false
  while head <= #qx do
    local cx, cy = qx[head], qy[head]
    head = head + 1
    if cx == tx and cy == ty then found = true; break end
    for _, d in ipairs(DIRS8) do
      local nx, ny = cx + d[1], cy + d[2]
      if nx >= 0 and ny >= 0 and nx < w and ny < h and from[key(nx, ny)] == nil then
        if (ctx.walkable(nx, ny) or phase) and diag_ok(ctx, cx, cy, d, phase) then
          -- 别的怪占着的格不穿（目标格除外），免得排队挤成一团
          if not ctx.occ(nx, ny) or (nx == tx and ny == ty) then
            from[key(nx, ny)] = key(cx, cy)
            qx[#qx + 1], qy[#qy + 1] = nx, ny
          end
        end
      end
    end
  end
  if not found then return nil end
  local cx, cy = tx, ty
  while true do
    local prev = from[key(cx, cy)]
    if prev == nil or prev == -1 then return nil end
    local px, py = prev % w, math.floor(prev / w)
    if px == x and py == y then return cx - x, cy - y end
    cx, cy = px, py
  end
end

-- 随机走一步：优先非死胡同格；被逼住返回 nil（调用方转成 wait）。
local function wander_step(m, ctx, rng)
  local dirs = {}
  for _, d in ipairs(DIRS8) do dirs[#dirs + 1] = { d[1], d[2] } end
  rng.shuffle(dirs)
  local fallback
  for _, d in ipairs(dirs) do
    local nx, ny = m.x + d[1], m.y + d[2]
    if ctx.walkable(nx, ny) and not ctx.occ(nx, ny) and diag_ok(ctx, m.x, m.y, d, m.phase) then
      if exits(ctx, nx, ny) > 1 then return d end
      fallback = fallback or d
    end
  end
  return fallback
end

-- 逃/退：选"让与玩家距离最大"的可走相邻格
local function retreat(m, ctx)
  local p = ctx.player
  local best, bestd
  for _, d in ipairs(DIRS8) do
    local nx, ny = m.x + d[1], m.y + d[2]
    if ctx.walkable(nx, ny) and not ctx.occ(nx, ny) and diag_ok(ctx, m.x, m.y, d, m.phase) then
      local dd = (nx - p.x) ^ 2 + (ny - p.y) ^ 2
      if not bestd or dd > bestd then best, bestd = d, dd end
    end
  end
  if best then return best end
  return nil
end

-- 感知：在 perception 内且视线通畅（perception 由玩家的光照推，§7.3）
local function perceives(m, ctx)
  local p = ctx.player
  local dx, dy = p.x - m.x, p.y - m.y
  if dx * dx + dy * dy > ctx.perception * ctx.perception then return false end
  return los(ctx, m.x, m.y, p.x, p.y)
end

-- 决策主入口：返回意图表。
function AI.decide(m, ctx, rng)
  local p = ctx.player
  -- 睡着的怪：感知到才醒（受伤唤醒由 world 负责）
  if not m.awake then
    if perceives(m, ctx) then
      m.awake, m.known_x, m.known_y, m.lost = true, p.x, p.y, 0
    else
      return { kind = "wait" }
    end
  end

  local dx, dy = p.x - m.x, p.y - m.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local sees = los(ctx, m.x, m.y, p.x, p.y)
  if sees then
    m.known_x, m.known_y, m.lost = p.x, p.y, 0
  else
    m.lost = (m.lost or 0) + 1
  end
  -- 20 个玩家动作没视线就忘掉目标，回 sleep（防跨图无限追杀，§7.3）
  if not sees and m.lost > 20 then
    m.awake, m.lost = false, 0
    return { kind = "wait" }
  end

  local tx = sees and p.x or (m.known_x or p.x)
  local ty = sees and p.y or (m.known_y or p.y)
  local adjacent = math.max(math.abs(dx), math.abs(dy)) <= 1

  -- 邪教徒：有视线且在射程内先远程；贴太近则后撤；其余情况靠近
  if m.ranged then
    if sees and dist <= m.ranged and dist > 1.5 then return { kind = "ranged" } end
    if dist < 3 and not adjacent then
      local d = retreat(m, ctx)
      if d then return { kind = "move", dx = d[1], dy = d[2] } end
    end
  end

  -- 濒死逃跑（哥布林）
  if m.flee_at and m.hp <= m.max_hp * m.flee_at then
    local d = retreat(m, ctx)
    if d then return { kind = "move", dx = d[1], dy = d[2] } end
  end

  if adjacent then return { kind = "attack" } end

  -- 洞穴蝠：一半概率乱走（避开同一格来回抖，靠 shuffle 而非"记上一步"）
  if m.erratic and rng.float() < 0.5 then
    local d = wander_step(m, ctx, rng)
    if d then return { kind = "move", dx = d[1], dy = d[2] } end
  end

  -- 看不见玩家时，按记忆位置追；记忆也到不了就在附近游荡（搜人）
  local sx, sy = first_step(ctx, m.x, m.y, tx, ty, m.phase)
  if sx then return { kind = "move", dx = sx, dy = sy } end
  if not sees then
    local d = wander_step(m, ctx, rng)
    if d then return { kind = "move", dx = d[1], dy = d[2] } end
  end
  return { kind = "wait" }
end

return AI

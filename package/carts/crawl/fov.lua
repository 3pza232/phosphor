-- fov.lua —— 视野与迷雾（本作招牌系统，DESIGN §7）。
--
-- 光在这里同时是"看得见什么"的开关：半径由灯油推出（§7.1），视线靠 Bresenham
-- 光线投射逐格判定（§7.2）。**只算不画**——渲染三态（未探索/记忆/可见）由 main 决定。
-- 不 require 任何玩法模块，只对传进来的 map 对象做查询与写入（explored 只增不减）。

local Fov = {}

-- 灯油 → 光照半径。跨档处**恰好**按表变化（验收用例 3）。
function Fov.radius(fuel)
  if fuel >= 67 then return 9
  elseif fuel >= 34 then return 7
  elseif fuel >= 10 then return 5
  elseif fuel >= 1 then return 3
  else return 2 end
end

-- 两点间视线是否通畅。目标格若是墙，仍应被"看见"（墙要亮出来），
-- 所以撞到墙时只在"那堵墙就是目标"时才放行。返回 true = 能看见目标。
local function los(map, x0, y0, x1, y1)
  local dx, dy = math.abs(x1 - x0), math.abs(y1 - y0)
  local sx = (x0 < x1) and 1 or -1
  local sy = (y0 < y1) and 1 or -1
  local err = dx - dy
  local x, y = x0, y0
  while true do
    if not (x == x0 and y == y0) then
      if map:blocks_sight(x, y) then
        return (x == x1 and y == y1)
      end
    end
    if x == x1 and y == y1 then break end
    local e2 = 2 * err
    if e2 > -dy then err = err - dy; x = x + sx end
    if e2 < dx then err = err + dx; y = y + sy end
  end
  return true
end
Fov.los = los

-- 重算可见集：对以玩家为中心、欧氏距离 ≤ R + 0.5 的每格投线。
-- 返回 (visible 二维表, 可见格数)；同时把探索过的格写入 map.explored。
function Fov.compute(map, px, py, radius)
  local vis, count = {}, 0
  local r2 = (radius + 0.5) * (radius + 0.5)
  local span = math.ceil(radius) + 1
  for y = py - span, py + span do
    if y >= 0 and y < map.h then
      for x = px - span, px + span do
        if x >= 0 and x < map.w then
          local ddx, ddy = x - px, y - py
          if ddx * ddx + ddy * ddy <= r2 and los(map, px, py, x, y) then
            vis[y] = vis[y] or {}
            vis[y][x] = true
            count = count + 1
            map.explored[y][x] = true
          end
        end
      end
    end
  end
  return vis, count
end

return Fov

-- terrain.lua —— 地形：以**子格**为单位（1 个字符格 = 2x2 子格）
--
-- 数据是"每行一条字符串"（'1' 实心 / '0' 空）。选这个布局是因为：
--   * 破坏只需在行内拼接
--   * 命中判定只是取一个字节（main 里用 string.byte，不产生临时字符串）
--   * 480x180 的世界也只有 86 KB
-- 这个模块只管地形本身：不知道虫子，不做物理解算，不绘制。

local Terrain = {}
Terrain.__index = Terrain

-- 世界的**标准**宽度（子格）。每局的实际宽度由 Terrain.new 的倍率决定：
-- 宽窄只改横向，纵向（高度、海平面、山高）一律不变 —— 所以"大地图"是更宽，不是更高
Terrain.BASE_W, Terrain.H = 480, 180
Terrain.WATER_Y = 172                  -- 海平面：这里以下清空，落进去即死

local BYTE_ONE, BYTE_ZERO = string.byte("1"), string.byte("0")

local function clamp(v, lo, hi)
  if v < lo then return lo end
  if v > hi then return hi end
  return v
end

-- 高度场：**值噪声**。每隔 STEP 个子格放一个随机控制点，再用余弦插值连起来。
-- 不用"几层正弦叠加"是因为那样每局只是把相位挪一挪，山形永远是那几座，
-- 两局就看腻了；控制点自己随机，才会出现平台、陡坡、偶尔的小悬崖。
local NOISE_STEP = 26
local function noise_heights(seed, w)
  local n = math.ceil(w / NOISE_STEP) + 2
  local ctrl = {}
  for i = 1, n do ctrl[i] = phos.sys.random(0, 1000) / 1000 end
  local top, base = {}, Terrain.H * 0.40
  for x = 1, w do
    local f = (x - 1) / NOISE_STEP
    local i = math.floor(f)
    local t = f - i
    local k = (1 - math.cos(t * math.pi)) * 0.5          -- 平滑插值
    local h1 = ctrl[i + 1] or ctrl[#ctrl]
    local h2 = ctrl[i + 2] or ctrl[#ctrl]
    local v = h1 + (h2 - h1) * k
    -- 再叠一点细噪声，坡面就不会显得像圆规画出来的
    local fine = math.sin((x + seed * 0.37) * 0.19) * 2.5
    top[x] = clamp(math.floor(base + v * 48 + fine), 26, Terrain.WATER_Y - 14)
  end
  return top
end

-- 把一行里 [x0, x1] 清空：挖洞与爆炸都走这里，行为只有一份
function Terrain:clear_span(y, x0, x1)
  x0, x1 = clamp(x0, 1, self.W), clamp(x1, 1, self.W)
  if x1 < x0 then return end
  local row = self.rows[y]
  self.rows[y] = row:sub(1, x0 - 1) .. string.rep("0", x1 - x0 + 1) .. row:sub(x1 + 1)
end

-- 与 clear_span 对称：把一行里 [x0, x1] 填实（地形弹用它）
function Terrain:set_span(y, x0, x1)
  x0, x1 = clamp(x0, 1, self.W), clamp(x1, 1, self.W)
  if x1 < x0 then return end
  local row = self.rows[y]
  self.rows[y] = row:sub(1, x0 - 1) .. string.rep("1", x1 - x0 + 1) .. row:sub(x1 + 1)
end

-- 按高度场铺实心。整行用表拼接后一次成型：480x180 只要几十毫秒级。
-- 注意 top 是**生成时**的高度场：挖洞与填土都不会更新它，
-- 要"现在真正的地表"请用 foot_row / surface，不要读 top
function Terrain:fill_ground()
  local cells = {}
  for y = 1, self.WATER_Y - 1 do
    for x = 1, self.W do
      cells[x] = (y >= self.top[x]) and "1" or "0"
    end
    self.rows[y] = table.concat(cells)
  end
  for y = self.WATER_Y, self.H do
    self.rows[y] = string.rep("0", self.W)
  end
end

-- 挖一个椭圆洞：让地形有层次，而不是一整块实心山
function Terrain:carve(cx, cy, rx, ry)
  for y = math.floor(cy - ry), math.ceil(cy + ry) do
    if y >= 1 and y <= self.H then
      local t = (y - cy) / ry
      local half = math.floor(rx * math.sqrt(math.max(0, 1 - t * t)))
      if half > 0 then self:clear_span(y, cx - half, cx + half) end
    end
  end
end

-- 把某一列重设地表高度（出生平台用它压平）
function Terrain:set_top(x, y)
  for ry = 1, self.WATER_Y - 1 do
    local want = (ry >= y) and "1" or "0"
    local row = self.rows[ry]
    if row:sub(x, x) ~= want then
      self.rows[ry] = row:sub(1, x - 1) .. want .. row:sub(x + 1)
    end
  end
  self.top[x] = y
end

-- 压平一小段，给出生点用：地形是随机的，没人能保证某个坐标上空一定站得住。
-- "一出生就被埋进石头里"是最不能接受的随机结果，所以先压平台再放虫。
function Terrain:flatten(cx, half)
  local x0 = math.max(2, cx - half)
  local x1 = math.min(self.W - 1, cx + half)
  local sum, n = 0, 0
  for x = x0, x1 do
    sum, n = sum + self.top[x], n + 1
  end
  if n == 0 then return end
  local y = clamp(math.floor(sum / n), 26, self.WATER_Y - 14)
  for x = x0, x1 do self:set_top(x, y) end
end

-- 出生点：先压平再返回"脚下实心、头顶至少两格空"的那一格
function Terrain:spawn_spot(cx)
  cx = clamp(cx, 8, self.W - 8)
  self:flatten(cx, 6)
  return cx, self.top[cx] - 1
end

-- width_scale：世界宽度相对标准的倍率（1 = 标准，0.5 = 一半，2 = 两倍）。
-- 取整到偶数子格：一格 = 2 子格，奇数宽会让最右那一格只填一半，看着像被裁掉
function Terrain.new(width_scale)
  local self = setmetatable({}, Terrain)
  self.W = 2 * math.floor(Terrain.BASE_W * (width_scale or 1) / 2)
  self.seed = phos.sys.random(1, 9999)
  self.rows = {}
  self.top = noise_heights(self.seed, self.W)
  self:fill_ground()
  -- 洞穴：3~5 个横洞，让地形有层次（不是纯山丘）
  for _ = 1, phos.sys.random(3, 5) do
    self:carve(phos.sys.random(60, self.W - 60), phos.sys.random(80, 150),
               phos.sys.random(18, 36), phos.sys.random(5, 10))
  end
  return self
end

function Terrain:solid(x, y)
  if y < 1 or y > self.H or x < 1 or x > self.W then return false end
  return self.rows[y]:byte(x) == BYTE_ONE
end

-- 爆炸：挖掉半径内的地形（圆形，边缘带一点噪声）。
-- 完美的圆看着像贴图，锯齿状的坑才像"被炸过"——而且这层噪声还能让
-- 后续的抛物线多几种落点，不是每次都在同一个光滑碗里打转。
-- 返回挖掉的格数，供统计与音效使用
function Terrain:blast(cx, cy, r)
  local dug = 0
  for y = math.floor(cy - r), math.ceil(cy + r) do
    if y >= 1 and y <= self.H then
      local dy = y - cy
      local half = math.floor(math.sqrt(math.max(0, r * r - dy * dy)))
      if half > 0 then
        half = half + phos.sys.random(-1, 1)
        local x0, x1 = cx - half, cx + half
        for x = math.max(1, x0), math.min(self.W, x1) do
          if self:solid(x, y) then dug = dug + 1 end
        end
        self:clear_span(y, x0, x1)
      end
    end
  end
  return dug
end

-- 规整地挖一个矩形（天基炮的竖井用）：不做任何噪声，边界笔直。
-- 用圆去挖竖井会得到"糖葫芦"——圆心每跳都落在新的地表上，相邻两跳之间留着挖不净的肩，
-- 看上去就一段宽一段窄
function Terrain:carve_rect(x0, y0, x1, y1)
  local dug = 0
  local a, b = math.max(1, x0), math.min(self.W, x1)
  for y = math.max(1, y0), math.min(self.H, y1) do
    for x = a, b do
      if self:solid(x, y) then dug = dug + 1 end
    end
    self:clear_span(y, a, b)
  end
  return dug
end

-- 长出一块圆形地形（地形弹）：与 blast 同一套圆算法，只是把 "0" 写成 "1"，
-- 所以"炸出来的坑"和"长出来的丘"形状语言一致。返回新增的格数
function Terrain:fill_circle(cx, cy, r)
  local grew = 0
  for y = math.floor(cy - r), math.ceil(cy + r) do
    if y >= 1 and y <= self.H then
      local dy = y - cy
      local half = math.floor(math.sqrt(math.max(0, r * r - dy * dy)))
      if half > 0 then
        half = half + phos.sys.random(-1, 1)
        local x0, x1 = cx - half, cx + half
        for x = math.max(1, x0), math.min(self.W, x1) do
          if not self:solid(x, y) then grew = grew + 1 end
        end
        self:set_span(y, x0, x1)
      end
    end
  end
  return grew
end

-- 在 [y0, y1] 这一小段里找**落脚行**：本身空、下一行有实心（脚踩得上的那一行）。
-- 从**上往下**扫，取最靠上的那个 —— 角色一步步往上挪，不会一步跳过一整级台阶。
-- 逐子格扫而不是读 top：top 是生成时的高度场，挖过之后就不再等于真正的地表
function Terrain:foot_row_in(x0, x1, y0, y1)
  local top = math.min(math.floor(y1), self.WATER_Y - 2)
  for y = math.max(1, math.floor(y0)), top do
    if not (self:solid(x0, y) or self:solid(x1, y))
        and (self:solid(x0, y + 1) or self:solid(x1, y + 1)) then
      return y
    end
  end
  return nil
end

-- 从 from_y **向下**找这一段的落脚行：脚下那块地、或更低的坡（走空之后交给重力）。
-- 与 foot_row_in 的分工：这个只朝下（找"地"），那个在一小段窗口里上下都看（找"能站的位置"）
function Terrain:foot_row(x0, x1, from_y)
  for y = math.max(1, math.floor(from_y)), self.WATER_Y - 1 do
    if self:solid(x0, y) or self:solid(x1, y) then
      local above = y - 1
      if above >= 1 and not (self:solid(x0, above) or self:solid(x1, above)) then return above end
      return nil
    end
  end
  return nil
end

-- 从 from_y **向下**找地表：传送落点用它。
-- 与 find_ground 方向相反，用法也相反：那是"落到最近的支撑面"，
-- 这是"往下走到脚下那块地"。**方向必须朝下**，否则永远找不到落点
function Terrain:ground_below(x, from_y)
  for y = clamp(from_y, 1, self.WATER_Y - 1), self.WATER_Y - 1 do
    if not self:solid(x, y) and self:solid(x, y + 1) then return x, y end
  end
  return nil
end

return Terrain

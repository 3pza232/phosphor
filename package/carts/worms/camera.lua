-- camera.lua —— 相机：把世界坐标（子格）映射到视口（字符格）
--
-- 视口尺寸由调用方给：声明侧栏后内容区会变窄，写死宽度会有一截画在可见区之外。
-- 世界 480x180 子格，视口远小于它，所以必须滚动。
-- 相机只算坐标：不绘制，也不知道自己拍的是虫子还是飞行的弹药。
--
-- **原点恒为偶子格**，这是这台机器上"格"的唯一定义：视口的一格覆盖世界子格
-- 2g 与 2g+1，绘制、碰撞、光柱、降水全都按这个口径取格。原点若落在奇数上，
-- 同一屏就会长出两套差半格的网格 —— 表现是"贴着墙就陷进去"、
-- 以及"看着有空间却过不去"。所以对齐不是可选的修饰，而是这套坐标的前提。

local Camera = {}
Camera.__index = Camera

-- 视口尺寸（子格）由调用方给：写死的宽度在侧栏展开后会被主机裁掉右侧
Camera.VIEW_W, Camera.VIEW_H = 160, 90

function Camera.new(world_w, world_h, view_w, view_h)
  local self = setmetatable({}, Camera)
  self.world_w, self.world_h = world_w, world_h
  self.vw = view_w or Camera.VIEW_W
  self.vh = view_h or Camera.VIEW_H
  self.x, self.y = 0, 0
  self:center(world_w // 2, world_h // 2)
  return self
end

function Camera:clamp()
  local maxx = math.max(0, self.world_w - self.vw)
  local maxy = math.max(0, self.world_h - self.vh)
  self.x = math.max(0, math.min(maxx, self.x))
  self.y = math.max(0, math.min(maxy, self.y))
  -- 夹紧之后才对偶：夹到 0 本来就是对偶数，夹到右边界则可能不是
  self.x = self.x - self.x % 2
  self.y = self.y - self.y % 2
end

-- 把世界某点放到视口正中（子格坐标），并夹在世界内
function Camera:center(wx, wy)
  self.x = math.floor(wx - self.vw / 2)
  self.y = math.floor(wy - self.vh / 2)
  self:clamp()
end

-- 视口左上角对应的世界子格坐标。**唯一出口**：读的时候再对一次偶，
-- 于是别处直接改过 self.x 也不会漏出奇数格原点
function Camera:origin()
  self.x = self.x - self.x % 2
  self.y = self.y - self.y % 2
  return self.x, self.y
end

-- 世界子格 → 视口内的字符格下标（0 基）
-- 必须用 math.floor 而不是 //：虫子和弹药的位置是浮点子格，
-- 而 Lua 的 // 在两个浮点数之间仍返回浮点，主机写入格子的接口只收整数
function Camera:cell_of(wx, wy)
  local ox, oy = self:origin()
  return math.floor((wx - ox) / 2), math.floor((wy - oy) / 2)
end

return Camera

-- camera.lua —— 相机：把世界坐标（子格）映射到视口（字符格）
--
-- 视口尺寸由调用方给（声明侧栏后内容区会变窄，写死宽度会让右半边永远看不见）。
-- 世界 480x180 子格，视口远小于它，所以必须滚动。
-- 相机只算坐标：不绘制，也不知道自己拍的是虫子还是飞行的弹药。

local Camera = {}
Camera.__index = Camera

-- 视口尺寸（子格）**由调用方给**，不能写死：声明侧栏后内容区会变窄，
-- 写死 160 的话右侧那一截会被主机裁掉——画得再多玩家也看不见，
-- 看上去就像"敌人在地图外面"（踩过这个坑）
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
end

-- 把世界某点放到视口正中（子格坐标），并夹在世界内
function Camera:center(wx, wy)
  self.x = math.floor(wx - self.vw / 2)
  self.y = math.floor(wy - self.vh / 2)
  self:clamp()
end

function Camera:pan(dx, dy)
  self.x, self.y = self.x + dx, self.y + dy
  self:clamp()
end

-- 视口左上角对应的世界子格坐标
function Camera:origin() return self.x, self.y end

-- 世界子格 → 视口内的字符格下标（0 基）
-- 必须用 math.floor 而不是 //：虫子和弹药的位置是浮点子格，
-- 而 Lua 的 // 在两个浮点数之间仍返回浮点，主机写入格子的接口只收整数
function Camera:cell_of(wx, wy)
  return math.floor((wx - self.x) / 2), math.floor((wy - self.y) / 2)
end

function Camera:visible(wx, wy)
  return wx >= self.x and wx < self.x + self.vw
     and wy >= self.y and wy < self.y + self.vh
end

return Camera

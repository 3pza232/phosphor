-- map.lua —— 「长望站 LONGVIEW」房间图：12 房间 / 17 条无向边（GDD §4）。
--
-- 只认图结构、边代价与解锁状态；资源结算在 systems/game，剧情触发在 story_engine。
-- 边的 cost 同时是"移动耗时(min)"与"氧气消耗"的唯一来源（GDD §3.4 / §4.2）。
local Map = {}

-- pos = 地图屏上的示意坐标（列, 行）；art = 房间美术槽（art.lua 的块 id 前缀）
Map.ROOMS = {
  cryo     = { pos = { 1, 2 }, name = { zh = "休眠舱", en = "CRYO" },          art = "cryo",   unlocked = true,
               desc = { zh = "低温睡袋与冷凝水；手环在舱壁上投着一点绿光。", en = "Cryo pods and condensation; your wristband casts a green glow on the wall." } },
  med      = { pos = { 2, 1 }, name = { zh = "医疗舱", en = "MEDBAY" },        art = "med",    unlocked = true,
               desc = { zh = "十一只休眠舱沿墙排开，记录仪还亮着。", en = "Eleven pods line the wall; their recorders still glow." } },
  hub      = { pos = { 3, 2 }, name = { zh = "中央环廊", en = "HUB" },         art = "hub",    unlocked = true,
               desc = { zh = "环廊的应急灯每隔几秒亮一次，管道像一排肋骨。", en = "Emergency lights blink down the ring; the pipes look like ribs." } },
  galley   = { pos = { 2, 3 }, name = { zh = "生活舱", en = "HAB" },           art = "galley", unlocked = true,
               desc = { zh = "藻床还是绿的；厨房里两只杯子停在桌上。", en = "The algae bed is still green; two cups wait on the kitchen table." } },
  maint    = { pos = { 4, 3 }, name = { zh = "维护隧道", en = "MAINT" },       art = "maint",  unlocked = true,
               desc = { zh = "灯带只亮了一半；冷却管后面塞着一只黑匣子。", en = "Half the light strips are dead; a black box is jammed behind a coolant pipe." } },
  reactor  = { pos = { 5, 3 }, name = { zh = "反应堆", en = "REACTOR" },       art = "reactor",unlocked = true,
               desc = { zh = "冷却泵低鸣；配电盘上四路母线都还有余量。", en = "The coolant pump hums; all four buses still have headroom." } },
  obs      = { pos = { 4, 1 }, name = { zh = "观测甲板", en = "OBS" },         art = "obs",    unlocked = true,
               desc = { zh = "舷窗外，默尔的光被拉成一条细白的弧。", en = "Outside the port, MORS is drawn into a thin white arc." } },
  bridge   = { pos = { 5, 1 }, name = { zh = "舰桥", en = "BRIDGE" },          art = "bridge", unlocked = true,
               desc = { zh = "主屏一片安静的红；导航解算停在七年前。", en = "The main screen is a quiet red; the nav solution stopped seven years ago." } },
  array    = { pos = { 6, 1 }, name = { zh = "通信阵列", en = "ARRAY" },       art = "array",  unlocked = false,
               desc = { zh = "长望环像一只贴在天线上的耳朵。", en = "The Longview ring is an ear pressed to the antenna." } },
  airlock  = { pos = { 6, 2 }, name = { zh = "气闸", en = "AIRLOCK" },         art = "airlock",unlocked = true,
               desc = { zh = "外舱门结着霜；渡鸦号的挂架空着。", en = "Frost on the outer door; the RAVEN's cradle is empty." } },
  null     = { pos = { 5, 0 }, name = { zh = "零号观测室", en = "NULL BAY" },  art = "null",   unlocked = false,
               desc = { zh = "站体图上没有这间舱室。门缝里透出一点低频震动。", en = "This bay is not on the plans. A low vibration leaks from the seam." } },
  pod      = { pos = { 7, 3 }, name = { zh = "视界吊舱", en = "POD" },         art = "pod",    unlocked = false,
               desc = { zh = "下降舱「渡鸦」的检修口；舱体上还留着焦黑的再入痕。", en = "The descent craft RAVEN's service hatch, still scorched by re-entry." } },
}

Map.ORDER = { "cryo", "med", "hub", "galley", "maint", "reactor", "obs",
              "bridge", "array", "airlock", "null", "pod" }

-- 无向边（GDD §4.2）：{ a, b, o2, min }。按 id 字典序存一遍即可
Map.EDGES = {
  { "airlock", "bridge",  1, 8 },
  { "airlock", "pod",     3, 16 },  -- STR>=50 才可走（game 判定）
  { "array",   "bridge",  2, 14 },
  { "cryo",    "hub",     1, 10 },
  { "cryo",    "med",     1, 6 },
  { "galley",  "hub",     1, 6 },
  { "galley",  "maint",   2, 12 },
  { "galley",  "med",     1, 8 },
  { "hub",     "maint",   1, 8 },
  { "hub",     "obs",     1, 8 },
  { "hub",     "bridge",  1, 8 },
  { "maint",   "reactor", 2, 12 },
  { "maint",   "airlock", 2, 12 },
  { "obs",     "null",    1, 8 },
  { "obs",     "bridge",  1, 10 },
  { "reactor", "pod",     2, 12 },
  { "med",     "hub",     1, 6 },
}

local ADJ = {}
for _, id in ipairs(Map.ORDER) do ADJ[id] = {} end
for _, e in ipairs(Map.EDGES) do
  local a, b, o2, minutes = e[1], e[2], e[3], e[4]
  ADJ[a][#ADJ[a] + 1] = { id = b, o2 = o2, min = minutes }
  ADJ[b][#ADJ[b] + 1] = { id = a, o2 = o2, min = minutes }
end
for _, id in ipairs(Map.ORDER) do
  table.sort(ADJ[id], function(x, y) return x.id < y.id end)
end

function Map.new()
  local self = setmetatable({}, { __index = Map })
  self.current = "cryo"
  self.unlocked = {}
  self.damaged = {}
  self.done = {}
  self.visited = { cryo = true }
  for id, room in pairs(Map.ROOMS) do
    if room.unlocked then self.unlocked[id] = true end
  end
  return self
end

function Map:room(id) return id and Map.ROOMS[id] or nil end
function Map:is_unlocked(id) return self.unlocked[id] == true end

function Map:unlock(id)
  if Map.ROOMS[id] then self.unlocked[id] = true end
end

-- 出口：按房间 id 稳定排序；allow(room, edge) 由调用方叠加"门禁/结构"条件
function Map:exits(allow)
  local out = {}
  for _, edge in ipairs(ADJ[self.current] or {}) do
    local room = Map.ROOMS[edge.id]
    if room and (allow == nil or allow(room, edge)) then
      out[#out + 1] = { id = edge.id, room = room, o2 = edge.o2, min = edge.min,
                        unlocked = self:is_unlocked(edge.id) }
    end
  end
  return out
end

function Map:edge(a, b)
  for _, edge in ipairs(ADJ[a] or {}) do
    if edge.id == b then return edge end
  end
  return nil
end

function Map:can_move(id, allow)
  local edge = self:edge(self.current, id)
  if not edge then return false end
  local room = Map.ROOMS[id]
  return room ~= nil and (allow == nil or allow(room, edge))
end

function Map:move(id)
  if not Map.ROOMS[id] then return false end
  self.current = id
  self.visited[id] = true
  return true
end

function Map:serialize()
  local unlocked, damaged, done, visited = {}, {}, {}, {}
  for _, id in ipairs(Map.ORDER) do
    if self.unlocked[id] then unlocked[#unlocked + 1] = id end
    if self.damaged[id] then damaged[#damaged + 1] = id end
    if self.visited[id] then visited[#visited + 1] = id end
  end
  for key in pairs(self.done) do done[#done + 1] = key end
  table.sort(done)
  return { current = self.current, unlocked = unlocked, damaged = damaged,
           done = done, visited = visited }
end

function Map:deserialize(data)
  if type(data) ~= "table" or not Map.ROOMS[data.current] then return false end
  self.current = data.current
  self.unlocked, self.damaged, self.done, self.visited = {}, {}, {}, {}
  for _, id in ipairs(data.unlocked or {}) do if Map.ROOMS[id] then self.unlocked[id] = true end end
  for _, id in ipairs(data.damaged or {}) do if Map.ROOMS[id] then self.damaged[id] = true end end
  for _, key in ipairs(data.done or {}) do if type(key) == "string" then self.done[key] = true end end
  for _, id in ipairs(data.visited or {}) do if Map.ROOMS[id] then self.visited[id] = true end end
  self.visited[data.current] = true
  self.unlocked[data.current] = true
  return true
end

return Map

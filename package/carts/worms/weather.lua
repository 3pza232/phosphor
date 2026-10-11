-- weather.lua —— 时间与天气：24 小时制时钟、日夜天色、天气状态机与降水
--
-- 一条主线：**时钟是唯一真源**。天色、日月、云、雨雪全由它推出来，
-- 而不是各自记一套"第几回合第几档"——否则加一种天气就要改三处。
--
-- 气候在开局随机：温带（晴 / 雨 / 暴风雨）、寒带（晴 / 雪 / 暴雪）、
-- 炎热（晴 / 酷热）。每 2~4 回合重掷一次；
-- **但风大到夸张时立刻转成暴风雨 / 暴雪**——风是真正影响弹道的东西，
-- 画面上就该看得出来；风一落回正常，天气退一档。
--
-- 天气只影响画面与读数，**不碰弹道与伤害**：那是玩法层的事

local Weather = {}
Weather.__index = Weather

Weather.HOURS_PER_ROUND = 2 -- 一回合两小时：一局里能看全一个昼夜
Weather.START_HOUR = 6 -- 开局清晨 06:00
Weather.STORM_WIND = 5 -- |wind| 到这个数就是暴风 / 暴雪（物理上限为 6）
Weather.CHANGE_MIN, Weather.CHANGE_MAX = 2, 4 -- 天气持续几回合

-- 温带两条、寒带一条、炎热一条：默认多半是温和气候
local CLIMATES = { "temperate", "temperate", "cold", "hot" }

-- 每种天气：降水密度、下落速度（子格/秒）、被风吹歪多少倍、字形、颜色名。
-- drops = 0 表示天上不掉东西（晴；酷热自己画热气）。
-- **drift 是"风能不能被看出来"的那根旋钮**：横向速度 = wind × drift × 每滴自己的系数，
-- 风最大（±6）时雨的横移可达 40+ 子格/秒——斜得一眼能读出方向来。
-- 雪比雨轻得多（下落才 13~20 子格/秒），所以 drift 更大：稍微有点风就被吹着横着走
local STATES = {
  clear = { drops = 0 },
  rain = { drops = 60, speed = 52, drift = 6.0, slant = true, tone = "cyan" },
  storm = { drops = 110, speed = 70, drift = 7.5, slant = true, heavy = true, tone = "blue" },
  snow = { drops = 70, speed = 13, drift = 7.0, glyph = "*", tone = "white" },
  blizzard = { drops = 130, speed = 20, drift = 9.0, glyph = "*", heavy = true, tone = "white" },
  heat = { drops = 0, heat = true, tone = "orange" },
}

local Text = {
  zh = { clear = "晴", rain = "雨", storm = "暴风雨", snow = "雪", blizzard = "暴雪", heat = "酷热" },
  en = { clear = "CLEAR", rain = "RAIN", storm = "STORM", snow = "SNOW", blizzard = "BLIZZARD", heat = "HEAT" },
}

-- 天顶色关键帧（小时 → RGB）。相邻两档**插值**，所以天色是连续变化的，
-- 不会在整点"啪"地跳一下
local SKY_STOPS = {
  { 0, { 10, 12, 32 } },
  { 4, { 20, 24, 52 } },
  { 6, { 92, 58, 74 } },
  { 9, { 34, 62, 108 } },
  { 13, { 42, 80, 134 } },
  { 17, { 98, 64, 60 } },
  { 19, { 76, 40, 62 } },
  { 21, { 26, 24, 56 } },
  { 24, { 10, 12, 32 } },
}

-- 太阳：**纯 ASCII**，所以可以按字节逐字切
local SUN_ROWS = { "\\|/", "-O-", "/|\\" }
-- 月亮：四分之一块拼的一轮**满月**（和地形同一套块字形，风格才统一）。
-- 不用弯月：这个分辨率下一格就是一个"像素"，弯月只会读成一个毛边方块；
-- 上下各窄一格的圆盘更干净，也不会被看成一个字母。
-- 表里写"第几格放哪个**整字形**"：▄█▀ 每个都是 3 字节，`string.sub` 按字节切，
-- 切出来的半截 UTF-8 会变成一排豆腐块
local MOON_CELLS = {
  { 1, 0, "▄" }, { 2, 0, "▄" },
  { 0, 1, "█" }, { 1, 1, "█" }, { 2, 1, "█" }, { 3, 1, "█" },
  { 1, 2, "▀" }, { 2, 2, "▀" },
}

local function sky_base(hour)
  for k = 1, #SKY_STOPS - 1 do
    local a, b = SKY_STOPS[k], SKY_STOPS[k + 1]
    if hour >= a[1] and hour <= b[1] then
      local t = (hour - a[1]) / (b[1] - a[1])
      return {
        a[2][1] + (b[2][1] - a[2][1]) * t,
        a[2][2] + (b[2][2] - a[2][2]) * t,
        a[2][3] + (b[2][3] - a[2][3]) * t,
      }
    end
  end
  return { 10, 12, 32 }
end

-- 这种气候下"下点什么"：风力极端时升一档。
-- 炎热气候的极端就是酷热，但它只在**白天**成立——半夜三更"酷热"没人信
local function wet_state(climate, extreme, hour)
  if climate == "cold" then
    return extreme and "blizzard" or "snow"
  end
  if climate == "hot" then
    local h = math.floor(hour) % 24
    return (h >= 9 and h <= 18) and "heat" or "clear"
  end
  return extreme and "storm" or "rain"
end

function Weather.new(terrain)
  local self = setmetatable({}, Weather)
  self.hour = Weather.START_HOUR
  self.climate = CLIMATES[phos.sys.random(1, #CLIMATES)]
  self.state = "clear"
  self.left = phos.sys.random(Weather.CHANGE_MIN, Weather.CHANGE_MAX)
  self.vw, self.vh = 80, 45
  self.world_w = terrain and terrain.W or 480
  self.drops, self.stars, self.clouds = {}, {}, {}
  self.anim, self.flash, self.next_bolt = 0, 0, 3
  self.wind_dir, self.wind_abs = 0, 0
  self.col = {
    cloud = phos.color.rgb(96, 108, 132),
    star = phos.color.rgb(200, 208, 228),
    sun = phos.color.rgb(255, 226, 150),
    dim_sun = phos.color.rgb(184, 156, 96),
    moon = phos.color.rgb(226, 232, 248),
  }
  -- 云相对**地表**撒：相机会一直盯着地上的虫子，视口顶也就到地表上方二三十子格；
  -- 按世界绝对高度撒的话，云全落在视口上面，等于没有
  for _ = 1, 8 do
    local x = phos.sys.random(1, self.world_w)
    local surf = (terrain and terrain.top[x]) or 90
    self.clouds[#self.clouds + 1] = {
      x = x,
      y = math.max(6, surf - phos.sys.random(26, 54)),
      w = phos.sys.random(10, 26),
    }
  end
  self:tile_drops()
  self:tile_stars()
  return self
end

-- 视口变了（侧栏展开/收起）：降水与星按屏幕格铺，所以要重新平铺
function Weather:resize(w, h)
  if w and h then
    self.vw, self.vh = w, h
  end
  self:tile_drops()
  self:tile_stars()
end

function Weather:tile_drops()
  local st = STATES[self.state] or STATES.clear
  self.drops = {}
  for _ = 1, st.drops or 0 do
    self.drops[#self.drops + 1] = {
      i = phos.sys.random(0, self.vw - 1),
      j = phos.sys.random(3, self.vh - 1),
      v = 0.6 + phos.sys.random(0, 80) / 100, -- 每滴自己的快慢，看着才不像一道帘子
    }
  end
end

function Weather:tile_stars()
  self.stars = {}
  for _ = 1, 34 do
    self.stars[#self.stars + 1] = {
      i = phos.sys.random(0, self.vw - 1),
      j = phos.sys.random(0, math.max(4, math.floor(self.vh * 0.42))),
    }
  end
end

-- 切天气：状态真的变了才重铺降水。不判一下的话，某些组合（炎热气候的白天）
-- 会每帧请求一次同一个状态，白铺一遍表
function Weather:set_state(name)
  if name ~= self.state then
    self.state = name
    self:tile_drops()
  end
end

function Weather:is_night()
  return self.hour < 6 or self.hour >= 19
end

function Weather:clock_text()
  local h = math.floor(self.hour) % 24
  local m = math.floor((self.hour - math.floor(self.hour)) * 60)
  return string.format("%02d:%02d", h, m)
end

function Weather:name()
  local dict = Text[phos.sys.language()] or Text.zh
  return dict[self.state] or dict.clear
end

-- 状态行里那一段的字色：晴天用暗色（不抢戏），恶劣天气用对应的颜色
function Weather:tone(C)
  local st = STATES[self.state] or STATES.clear
  return st.tone and C[st.tone] or C.gray
end

function Weather:is_severe()
  local s = self.state
  return s == "storm" or s == "blizzard"
end

-- 天顶色：按小时取基色，再按天气推一把（压暗 / 提亮 / 偏暖）
function Weather:sky_rgb()
  local base = sky_base(self.hour)
  local r, g, b = base[1], base[2], base[3]
  if self:is_severe() then
    -- 压暗并向灰靠：恶劣天气的天是"没有颜色"的
    local avg = (r + g + b) / 3
    r, g, b = r * 0.5 + avg * 0.25, g * 0.5 + avg * 0.25, b * 0.5 + avg * 0.25
  elseif self.state == "rain" then
    r, g, b = r * 0.78, g * 0.80, b * 0.86
  elseif self.state == "snow" then
    -- 雪天反而更亮更白：云把光散开了
    r, g, b = r * 1.05 + 58, g * 1.05 + 60, b * 1.02 + 64
  elseif self.state == "heat" then
    -- 酷热：整体往橙黄推
    r, g, b = r * 1.10 + 28, g * 1.00 + 8, b * 0.82
  end
  local function clamp(v)
    return math.max(0, math.min(255, math.floor(v)))
  end
  return clamp(r), clamp(g), clamp(b)
end

-- 换回合：时钟往前走，天气重掷。
-- 风力已经很大时**直接进暴风/暴雪**，别等下一次重掷
function Weather:advance_round(wind)
  self.hour = (self.hour + Weather.HOURS_PER_ROUND) % 24
  self.left = self.left - 1
  if math.abs(wind) >= Weather.STORM_WIND then
    self:set_state(wet_state(self.climate, true, self.hour))
    self.left = Weather.CHANGE_MIN
  elseif self.left <= 0 or self.climate == "hot" then
    -- 炎热气候的天气是**跟着时辰**走的（白天酷热、入夜转晴），
    -- 所以它每回合都要重看一眼，而不是等持续时长耗尽
    self.left = phos.sys.random(Weather.CHANGE_MIN, Weather.CHANGE_MAX)
    self:set_state((phos.sys.random(1, 100) <= 50) and wet_state(self.climate, false, self.hour) or "clear")
  end
end

function Weather:update(dt, wind)
  self.anim = self.anim + dt

  -- 风大到夸张 / 落回正常：**立刻**升降一档，不等换回合。
  -- 风是几帧内就能变的东西，画面要跟得上
  local extreme = math.abs(wind) >= Weather.STORM_WIND
  if extreme and not self:is_severe() then
    self:set_state(wet_state(self.climate, true, self.hour))
  elseif not extreme and self:is_severe() then
    self:set_state(wet_state(self.climate, false, self.hour))
  end

  -- 风向 / 风速记下来给绘制用：字形往哪边倒、"拉丝"往哪边长，都靠这两个数
  self.wind_dir = (wind > 0 and 1) or (wind < 0 and -1) or 0
  self.wind_abs = math.abs(wind)

  local st = STATES[self.state] or STATES.clear
  -- 风大了雨也急：下落速度跟着风速加 —— 又快又斜，"暴"才立得住
  local fall = (st.speed or 40) + math.abs(wind) * 3
  for _, d in ipairs(self.drops) do
    d.j = d.j + fall * d.v * dt
    d.i = d.i + wind * (st.drift or 0) * d.v * dt
    if d.j >= self.vh then
      -- 落到底就回顶上接着落；横向兜圈，风再大也不会把雨吹空
      d.j = d.j - self.vh
      d.i = (d.i + 37) % self.vw
    end
    if d.i < 0 then
      d.i = d.i + self.vw
    elseif d.i >= self.vw then
      d.i = d.i - self.vw
    end
  end

  -- 雷雨里偶尔打一道闪：极短的一瞬，只为让"暴风雨"不只是雨密一点
  self.flash = math.max(0, self.flash - dt)
  if self.state == "storm" then
    self.next_bolt = self.next_bolt - dt
    if self.next_bolt <= 0 then
      self.next_bolt = phos.sys.random(25, 60) / 10
      self.flash = 0.12
      phos.audio.beep(48, 0.5, { wave = "noise", volume = 0.2, release = 0.3 })
    end
  end

  -- 云随风漂：风越大飘得越快，风向变了云也换方向
  for _, c in ipairs(self.clouds) do
    c.x = c.x + (wind * 1.6 + 3) * dt
    if c.x > self.world_w + 30 then
      c.x = -30
    elseif c.x < -30 then
      c.x = self.world_w + 30
    end
  end
end

-- 天空：底色 + 星 / 日 / 月 / 云 / 风痕。cx, cy 是相机原点的世界坐标
function Weather:draw_sky(S, C, cx, cy, time, wind)
  local r, g, b = self:sky_rgb()
  S:clear(nil, C.rgb(r, g, b))

  -- 星星只属于清朗的夜：屏幕空间（"无限远"的东西不该跟着镜头平移）
  if self:is_night() and not self:is_severe() then
    for _, s in ipairs(self.stars) do
      S:put(s.i, s.j, "·", self.col.star)
    end
  end

  self:draw_sun_moon(S, C)

  for _, c in ipairs(self.clouds) do
    local i = math.floor((c.x - cx) / 2)
    local j = math.floor((c.y - cy) / 2)
    local tone = self:is_severe() and C.dark_gray or self.col.cloud
    if i > -24 and i < self.vw and j >= 0 and j < self.vh then
      for k = 0, math.floor(c.w / 2) do
        local x = i + k
        if x >= 0 and x < self.vw then
          S:put(x, j, "~", tone)
          if j + 1 < self.vh and (k % 3 ~= 1) then
            S:put(x, j + 1, "~", tone)
          end
        end
      end
    end
  end

  -- 风大时给几道走向痕迹，**风越大道数越多**：风是真正影响弹道的东西，
  -- 画面该把它说出来，而且要说得出"到哪一档了"
  if math.abs(wind) >= 4 then
    local dir = (wind > 0) and 1 or -1
    local streaks = math.min(9, 2 + math.floor(math.abs(wind) * 1.5))
    for k = 0, streaks do
      local x = math.floor((time * 70 * dir + k * 41) % (self.vw - 6)) + 3
      local y = 4 + k * 4
      if y < self.vh then
        S:put(x, y, dir > 0 and "`" or "'", self.col.cloud)
      end
    end
  end

end

-- 闪电：一整片提亮半屏，只在零点几秒内。
-- **单独一个方法**、由上层画在 fx 层（世界与角色都已画完之后）：夹在 draw_sky 里的话，
-- 紧接着的地形会把它的下半部整个盖掉，闪电就只能照亮天空、照不到地形与虫子
function Weather:draw_flash(S, C)
  if self.flash <= 0 then return end
  S:fill(0, 0, self.vw, math.max(1, math.floor(self.vh * 0.55)), " ", nil,
    C.rgb(120, 130, 170))
end

function Weather:draw_sun_moon(S, C)
  if self:is_severe() then
    return -- 暴风雨里看不见日月
  end
  local t
  if not self:is_night() then
    t = (self.hour - 6) / 12
  else
    t = (((self.hour + 24) - 19) % 24) / 11
  end
  if t < 0 or t > 1 then
    return
  end
  local i = 2 + math.floor(t * (self.vw - 8))
  -- 正午最高（j 最小）：sin 在弧顶取 1
  local j = 3 + math.floor(4 * (1 - math.sin(math.pi * t)))
  if self:is_night() then
    local tone = self.col.moon
    for _, cell in ipairs(MOON_CELLS) do
      local x, y = i + cell[1], j + cell[2]
      if x >= 0 and x < self.vw and y >= 0 and y < self.vh then
        S:put(x, y, cell[3], tone)
      end
    end
    return
  end
  local tone = (self.state == "snow" or self.state == "rain") and self.col.dim_sun or self.col.sun
  for k, row in ipairs(SUN_ROWS) do
    for c = 1, #row do
      local ch = row:sub(c, c)
      local x, y = i + c - 1, j + k - 1
      if ch ~= " " and x >= 0 and x < self.vw and y >= 0 and y < self.vh then
        S:put(x, y, ch, tone)
      end
    end
  end
end

-- 降水：画在**角色之后**（雨雪在人和地形前面），顶三行留给状态栏
function Weather:draw_precip(S, C)
  local st = STATES[self.state] or STATES.clear
  if st.heat then
    self:draw_heat(S, C)
    return
  end
  if #self.drops == 0 then
    return
  end
  local tone = (st.tone and C[st.tone]) or C.cyan
  -- 雨丝跟着风向倒：往右飘画 "\"，往左飘画 "/"，风小才竖着落。
  -- 雨滴本身在动，但一格一格的画面里，"往哪边斜"才是能静态读出来的方向
  local glyph = st.glyph
  if st.slant then
    glyph = (self.wind_dir > 0 and "\\") or (self.wind_dir < 0 and "/") or "|"
  end
  for _, d in ipairs(self.drops) do
    local i, j = math.floor(d.i), math.floor(d.j)
    if j >= 3 and j < self.vh and i >= 0 and i < self.vw then
      S:put(i, j, glyph, tone)
      -- 大风时往来路补一格：雨雪被拉成一条斜线，速度感全靠它
      if st.heavy and self.wind_dir ~= 0 then
        local ti = i - self.wind_dir * 2
        if ti >= 0 and ti < self.vw and j - 1 >= 3 then
          S:put(ti, j - 1, glyph, C.gray)
        end
      end
    end
  end
end

-- 酷热：地面附近升腾的热气。稀疏的 ~ 往上飘，越靠地面越密
function Weather:draw_heat(S, C)
  local step = math.max(6, self.vh // 2)
  for k = 1, 24 do
    local i = (k * 17 + math.floor(self.anim * 2)) % self.vw
    local j = self.vh - 3 - ((k * 7 + math.floor(self.anim * 6)) % step)
    if j >= 3 then
      S:put(i, j, "~", C.orange)
    end
  end
end

return Weather

-- systems.lua —— 数值与规则：资源/计数器/时间、条件求值、失败与结局判定、
-- 房间动作表、移动代价、两个小游戏（GDD §3/§7/§10/§11）。
--
-- 不读键盘、不画东西、不 require 剧情；动作表把"剧情动作"作为数据给出，由 main/game 执行。
local Systems = {}

-- ── 资源（GDD §3.2；HUD 用短 id + 双语名）────────────────────────────
Systems.RES = {
  { id = "o2",  name = { zh = "氧气", en = "O2" },  max = 100, warn = 50, crit = 25 },
  { id = "pwr", name = { zh = "电力", en = "PWR" }, max = 100, warn = 50, crit = 25 },
  { id = "str", name = { zh = "结构", en = "STR" }, max = 100, warn = 50, crit = 25 },
  { id = "san", name = { zh = "理智", en = "SAN" }, max = 100, warn = 50, crit = 25 },
}
Systems.RES_ORDER = { "o2", "pwr", "str", "san" }
Systems.RES_BY_ID = {}
for _, def in ipairs(Systems.RES) do Systems.RES_BY_ID[def.id] = def end

-- 计数器上限（GDD §11.2）：只增、钳制
Systems.COUNTER_CAPS = { trust = 3, communion = 4, understand = 3, mercy = 2, signal_windows = 7 }

-- 允许的 flag（GDD §11.1）：剧情校验与运行时写 flag 都只认这些键
Systems.FLAGS = {}
for _, name in ipairs({
  "wake_confirmed", "hestia_trusted", "hestia_confronted", "hestia_mission_known",
  "gu_log1", "gu_log2", "gu_log3", "gu_badge_found", "comms_priority",
  "lensing_explained", "raven_contacted", "raven_alliance", "null_bay_visited",
  "crew_cryo_alive", "crew_awakened", "ada_awake", "mercy_given",
  "power_ok", "power_fail", "signal_locked", "signal_fail",
  "counter_signal_ok", "counter_signal_fail", "pod_repaired", "reactor_overdrive",
  "station_stable", "left_lights_on", "auto_e4_triggered",
}) do Systems.FLAGS[name] = true end

Systems.TIME_TOTAL = 2520            -- 42 小时（分钟）
Systems.FINAL_CHAPTER = 8

Systems.INITIAL = {
  o2 = 78, pwr = 55, str = 86, san = 72,
  sys = { life = 18, obs = 0, comms = 0, shield = 10, drive = 0, reactor_ok = false },
}

-- ── 基础读写 ─────────────────────────────────────────────────────────
function Systems.clamp_res(id, value)
  local def = Systems.RES_BY_ID[id]
  if not def or type(value) ~= "number" then return 0 end
  if value < 0 then return 0 end
  if value > def.max then return def.max end
  return value
end

function Systems.add_res(state, id, delta)
  local res = state.res
  if not res or not Systems.RES_BY_ID[id] or type(delta) ~= "number" then return 0 end
  local before = res[id] or 0
  local after = Systems.clamp_res(id, before + delta)
  res[id] = after
  return after - before
end

function Systems.set_res(state, id, value)
  if not state.res or not Systems.RES_BY_ID[id] or type(value) ~= "number" then return 0 end
  state.res[id] = Systems.clamp_res(id, value)
  return state.res[id]
end

function Systems.add_counter(state, name, delta)
  local cap = Systems.COUNTER_CAPS[name]
  if not cap or type(delta) ~= "number" then return 0 end
  local before = state.counters[name] or 0
  local after = math.max(0, math.min(cap, before + delta))
  state.counters[name] = after
  return after - before
end

function Systems.res_ratio(state, id)
  local def = Systems.RES_BY_ID[id]
  if not def then return 0 end
  return (state.res[id] or 0) / def.max
end

function Systems.clock(minutes_left)
  local m = math.max(0, math.floor(minutes_left or 0))
  return string.format("%02d:%02d", m // 60, m % 60)
end

-- ── 条件求值（STORY_SCHEMA §7，唯一实现）──────────────────────────────
local function cmp(value, op, target)
  if op == ">=" then return value >= target
  elseif op == ">" then return value > target
  elseif op == "<=" then return value <= target
  elseif op == "<" then return value < target
  elseif op == "==" then return value == target end
  return false
end

-- 返回 true/false；nil/省略 = 恒真
function Systems.check(state, cond)
  if cond == nil then return true end
  if type(cond) ~= "table" then return false end
  if cond.all ~= nil then
    for _, sub in ipairs(cond.all) do if not Systems.check(state, sub) then return false end end
    return true
  end
  if cond.any ~= nil then
    for _, sub in ipairs(cond.any) do if Systems.check(state, sub) then return true end end
    return false
  end
  if cond.none ~= nil then
    for _, sub in ipairs(cond.none) do if Systems.check(state, sub) then return false end end
    return true
  end
  if cond.flag ~= nil then
    local value = state.flags[cond.flag] == true
    if cond.is ~= nil then return value == (cond.is == true) end
    return value
  end
  if cond.res ~= nil then
    return cmp(state.res[cond.res] or 0, cond.op or ">=", cond.v or 0)
  end
  if cond.counter ~= nil then
    return cmp(state.counters[cond.counter] or 0, cond.op or ">=", cond.v or 0)
  end
  if cond.chapter ~= nil then return cmp(state.chapter or 0, cond.op or ">=", cond.v or 0) end
  if cond.time_left ~= nil then
    return cmp((Systems.TIME_TOTAL - (state.time or 0)), cond.op or ">=", cond.v or 0)
  end
  if cond.room ~= nil then return (state.room or "") == cond.room end
  return false
end

-- ── 时间与周期惩罚（GDD §3.2/§3.3）──────────────────────────────────
-- 每跨过 30 分钟结算一次：低氧掉理智、黑站损结构、有电时灯光回理智。
function Systems.advance_time(state, minutes)
  local notes = {}
  if type(minutes) ~= "number" or minutes <= 0 then return notes end
  local before = state.time or 0
  state.time = math.min(Systems.TIME_TOTAL, before + minutes)
  local blocks_before = math.floor(before / 30)
  local blocks_after = math.floor(state.time / 30)
  for _ = blocks_before + 1, blocks_after do
    if (state.res.o2 or 0) < 20 then
      Systems.add_res(state, "san", -1)
      notes[#notes + 1] = { kind = "low_oxygen_san" }
    end
    if (state.res.pwr or 0) <= 0 then
      Systems.add_res(state, "str", -3)
      notes[#notes + 1] = { kind = "blackout_hull" }
    end
  end
  -- 灯光：PWR>=20 每小时 +1 SAN（按整小时结算）
  if (state.res.pwr or 0) >= 20 then
    local hours = math.floor(state.time / 60) - math.floor(before / 60)
    if hours > 0 then
      Systems.add_res(state, "san", hours)
      notes[#notes + 1] = { kind = "light_san" }
    end
  end
  if state.time >= Systems.TIME_TOTAL then notes[#notes + 1] = { kind = "time_up" } end
  return notes
end

-- ── 失败判定（GDD §10）：F1 缺氧 / F2 解体 / SAN 归零强制 E4 ──────────
function Systems.failure(state)
  if (state.res.o2 or 0) <= 0 then return "F1" end
  if (state.res.str or 0) <= 0 then return "F2" end
  return nil
end

function Systems.forced_ending(state)
  if (state.res.san or 0) <= 0 then return "E4" end
  return nil
end

-- ── 结局判定（GDD §10；结局门用 choice.requires 显示，这里给程序裁决兜底）──
local ENDING_RULES = {
  E1 = function(s)
    return s.room == "airlock" and s.flags.raven_contacted == true
       and (s.time or 0) >= Systems.TIME_TOTAL
       and (s.res.o2 or 0) > 0 and (s.res.str or 0) > 0
  end,
  E2 = function(s)
    return s.flags.crew_cryo_alive == true
       or ((s.res.str or 0) >= 45 and (s.res.pwr or 0) >= 35)
  end,
  E3 = function(s)
    return s.flags.pod_repaired == true
       and (s.counters.understand or 0) >= 2
       and (s.res.o2 or 0) >= 30 and (s.res.san or 0) >= 35
  end,
  E4 = function(s)
    return s.flags.null_bay_visited == true and s.flags.signal_locked == true
       and ((s.res.san or 0) <= 20 or (s.counters.communion or 0) >= 2)
  end,
}

function Systems.ending_available(state, id)
  local rule = ENDING_RULES[id]
  if not rule then return false, "" end
  return rule(state) and true or false
end

function Systems.available_endings(state)
  local out = {}
  for _, id in ipairs({ "E1", "E2", "E3", "E4" }) do
    if ENDING_RULES[id](state) then out[#out + 1] = id end
  end
  return out
end

-- ── 移动（GDD §3.4/§4.2）────────────────────────────────────────────
-- 返回 ok, cost（cost = {o2=, min=}）或失败原因
function Systems.travel_cost(map, room_id)
  local edge = map:edge(map.current, room_id)
  if not edge then return nil end
  return { o2 = edge.o2, min = edge.min }
end

function Systems.can_travel(state, map, room_id)
  local edge = map:edge(map.current, room_id)
  if not edge then return false, "no_route" end
  if not map:is_unlocked(room_id) then return false, "locked" end
  if map.current == "airlock" and room_id == "pod" and (state.res.str or 0) < 50 then
    return false, "hull"   -- 检修通道要求结构 >= 50
  end
  return true, edge
end

function Systems.apply_travel(state, edge)
  local notes = {}
  Systems.add_res(state, "o2", -(edge.o2 or 0))
  for _, note in ipairs(Systems.advance_time(state, edge.min or 0)) do notes[#notes + 1] = note end
  return notes
end

-- ── 房间动作表（GDD §3.4 / §4.3 / §6）───────────────────────────────
-- 动作字段：id / kind(utility|story|minigame) / label / requires(cond) /
--           cost{min,pwr,o2,...} / effects(effects DSL) / story(scene id) /
--           uses_per_chapter / once / disabled_reason(条件不满足时的原因文案)
local function action(def) return def end

local UTILITY = {
  repair = action{
    id = "repair", kind = "utility", label = { zh = "维护修复（STR +7）", en = "Repair hull (STR +7)" },
    room = "maint", requires = { res = "str", op = "<", v = 100 },
    cost = { min = 20, pwr = 8 }, effects = { { res = "str", add = 7 } }, uses_per_chapter = 2,
    disabled_reason = { zh = "结构已满或电力不足", en = "Hull full or no power" } },
  oxygen = action{
    id = "oxygen", kind = "utility", label = { zh = "医疗补氧（O₂ +18）", en = "Medical oxygen (O2 +18)" },
    room = "med", requires = { res = "pwr", op = ">=", v = 8 },
    cost = { min = 30, pwr = 8 }, effects = { { res = "o2", add = 18 } }, uses_per_chapter = 2,
    disabled_reason = { zh = "电力不足（需 8）", en = "Not enough power (need 8)" } },
  algae = action{
    id = "algae", kind = "utility", label = { zh = "藻床制氧（O₂ +10 / SAN +2）", en = "Algae oxygen (O2 +10 / SAN +2)" },
    room = "galley", requires = { res = "pwr", op = ">=", v = 5 },
    cost = { min = 60, pwr = 5 }, effects = { { res = "o2", add = 10 }, { res = "san", add = 2 } },
    uses_per_chapter = 2, disabled_reason = { zh = "电力不足（需 5）", en = "Not enough power (need 5)" } },
  rest = action{
    id = "rest", kind = "utility", label = { zh = "休息（SAN +14）", en = "Rest (SAN +14)" },
    cost = { min = 180, o2 = 6, pwr = 4 }, effects = { { res = "san", add = 14 } },
    uses_per_chapter = 1, disabled_reason = { zh = "本章已休息过", en = "Already rested this chapter" } },
  cycle = action{
    id = "cycle", kind = "utility", label = { zh = "反应堆稳定循环（PWR +12）", en = "Reactor cycle (PWR +12)" },
    room = "reactor", requires = { all = { { chapter = 2, op = ">=", v = 2 }, { flag = "reactor_ok" } } },
    cost = { min = 40 }, effects = { { res = "pwr", add = 12 } }, uses_per_chapter = 1,
    disabled_reason = { zh = "反应堆未稳定，或本章已循环", en = "Reactor unstable, or already used" } },
  short_sleep = action{
    id = "short_sleep", kind = "utility", label = { zh = "休眠舱短睡（SAN +10）", en = "Short sleep (SAN +10)" },
    room = "cryo", requires = { chapter = 1, op = "==", v = 1 },
    cost = { min = 240, o2 = 6 }, effects = { { res = "san", add = 10 } }, once = true,
    disabled_reason = { zh = "只在第 1 章可用", en = "Chapter 1 only" } },
  badge_door = action{
    id = "badge_door", kind = "story", story = "c5_s02",
    label = { zh = "刷开门禁（零号观测室）", en = "Badge the door (NULL BAY)" },
    room = "hub", requires = { all = {
      { flag = "gu_badge_found" }, { res = "pwr", op = ">=", v = 12 } } },
    cost = { min = 15, pwr = 12 }, once = true,
    disabled_reason = { zh = "缺少门禁卡或电力不足（需 12）", en = "No badge or not enough power (need 12)" } },
  pod_repair = action{
    id = "pod_repair", kind = "story", story = "c7_s01",
    label = { zh = "吊舱检修", en = "Service the pod" },
    room = "pod", requires = { all = {
      { chapter = 7, op = ">=", v = 7 }, { counter = "understand", op = ">=", v = 1 } } },
    cost = { min = 60, pwr = 10, o2 = 2 }, once = true,
    disabled_reason = { zh = "第 7 章且理解 ≥1 才能检修", en = "Chapter 7 and insight 1 required" } },
}

-- 可选调查节点（GDD 支线表）：不阻塞主线；once
local INVESTIGATE = {
  { id = "inv_med_records", room = "med", chapter = 1,
    label = { zh = "查看休眠舱记录（SAN -1）", en = "Read the cryo records (SAN -1)" },
    effects = { { res = "san", add = -1 }, { flag = "wake_confirmed" } } },
  { id = "inv_maint_scratches", room = "maint", chapter = 2,
    label = { zh = "查看隧道抓痕（SAN -3）", en = "Inspect the scratches (SAN -3)" },
    effects = { { res = "san", add = -3 } } },
  { id = "inv_galley_recording", room = "galley", chapter = 4,
    label = { zh = "播放私人录音（SAN +2）", en = "Play the private recording (SAN +2)" },
    effects = { { res = "san", add = 2 } } },
  { id = "inv_obs_echo", room = "obs", chapter = 4,
    label = { zh = "听第 13 次回声（SAN -2）", en = "Listen to the 13th echo (SAN -2)" },
    effects = { { res = "san", add = -2 } } },
  { id = "inv_cryo_recording", room = "cryo", chapter = 6,
    label = { zh = "播放自己的旧录音（SAN -4）", en = "Play your old recording (SAN -4)" },
    effects = { { res = "san", add = -4 } } },
}

-- 生成当前房间动作表。返回数组；每项含 cost/effects/requires/story 等。
-- story 参数只需提供 has_scene(id) 与（可选）chapter；没有剧情的动作照常列出。
function Systems.room_actions(state, map, story)
  local out = {}
  local chapter = state.chapter or 1
  for _, def in ipairs(UTILITY) do
    if def.room then
      if map.current == def.room then out[#out + 1] = def end
    else
      out[#out + 1] = def   -- rest：任意房间
    end
  end
  for _, def in ipairs(INVESTIGATE) do
    if map.current == def.room and chapter >= def.chapter then
      out[#out + 1] = { id = def.id, kind = "utility", label = def.label,
                        effects = def.effects, once = true, investigate = true }
    end
  end
  -- 剧情动作：数据里指向的场景必须存在，否则不列（避免空动作）
  local filtered = {}
  for _, def in ipairs(out) do
    if def.kind == "story" then
      if story and story.has_scene and story.has_scene(def.story) then filtered[#filtered + 1] = def end
    else
      filtered[#filtered + 1] = def
    end
  end
  -- 稳定顺序：utility 在前（按 id），story 在后
  table.sort(filtered, function(a, b)
    if a.kind ~= b.kind then return a.kind == "utility" end
    return a.id < b.id
  end)
  return filtered
end

-- ── 小游戏（GDD §7）─────────────────────────────────────────────────
-- 电力配给：4/3 条母线、相位制、绿区。返回对象（metatable）；用 U.update/mg_adjust 驱动。
local Power = {}
Power.__index = Power

local POWER_SETUP = {
  power_01 = { cap = 55, phases = 6, phase_time = 8,
    buses = { { id = "LIFE", lo = 16, hi = 22 }, { id = "COMMS", lo = 12, hi = 16 },
              { id = "SHIELD", lo = 8, hi = 12 }, { id = "DRIVE", lo = 6, hi = 10 } },
    alloc = { LIFE = 18, COMMS = 14, SHIELD = 10, DRIVE = 8 }, shift = 1 },
  power_02 = { cap = 40, phases = 6, phase_time = 8,
    buses = { { id = "LIFE", lo = 12, hi = 16 }, { id = "COMMS", lo = 6, hi = 10 },
              { id = "DRIVE", lo = 22, hi = 28 } },
    alloc = { LIFE = 12, COMMS = 6, DRIVE = 22 }, shift = 2 },
}

-- 约束卡：每相位移动若干条绿区（确定性：第 p 相位移动第 (p-1)%#buses+1 条，按 shift）
local function power_constraints(setup, phase)
  local bands = {}
  for i, bus in ipairs(setup.buses) do bands[i] = { lo = bus.lo, hi = bus.hi } end
  for round = 1, setup.shift do
    local idx = ((phase - 1 + round - 1) % #setup.buses) + 1
    local delta = (phase % 2 == 1) and 4 or -3
    bands[idx] = { lo = math.max(0, bands[idx].lo + delta), hi = math.min(99, bands[idx].hi + delta) }
  end
  return bands
end

function Systems.new_power(encounter)
  local setup = POWER_SETUP[encounter] or POWER_SETUP.power_01
  local mg = setmetatable({}, Power)
  mg.kind = "power"
  mg.id = encounter or "power_01"
  mg.cap = setup.cap
  mg.phase, mg.phases, mg.phase_time = 1, setup.phases, setup.phase_time
  mg.buses = {}
  for i, bus in ipairs(setup.buses) do
    mg.buses[i] = { id = bus.id, lo = bus.lo, hi = bus.hi, value = setup.alloc[bus.id] or bus.lo }
  end
  mg.bands = power_constraints(setup, 1)
  mg.setup = setup
  mg.t = 0
  mg.elapsed = 0
  mg.over_t = 0
  mg.out_t = {}
  mg.phase_bad = false
  mg.green = 0
  mg.result = nil
  mg.sel = 1
  mg.message = ""
  return mg
end

function Power:total()
  local sum = 0
  for _, bus in ipairs(self.buses) do sum = sum + bus.value end
  return sum
end

function Power:band(i) return self.bands[i] end

function Power:in_band(i)
  local bus, band = self.buses[i], self.bands[i]
  return bus.value >= band.lo and bus.value <= band.hi
end

function Power:adjust(delta)
  local bus = self.buses[self.sel]
  if not bus then return end
  bus.value = math.max(0, math.min(self.cap, bus.value + delta))
end

function Power:select(delta)
  self.sel = ((self.sel - 1 + delta) % #self.buses) + 1
end

function Power:update(dt)
  if self.result then return end
  self.t = self.t + dt
  self.elapsed = self.elapsed + dt
  self.over_t = self:total() > self.cap and (self.over_t + dt) or 0
  for i = 1, #self.buses do
    if not self:in_band(i) then
      self.out_t[i] = (self.out_t[i] or 0) + dt
    else
      self.out_t[i] = math.max(0, (self.out_t[i] or 0) - dt)  -- 回到绿区可恢复
    end
  end
  if self.over_t >= 2 then self.result = "fail"; self.message = "overload" ; return end
  for i = 1, #self.buses do
    if (self.out_t[i] or 0) >= 3 then self.result = "fail"; self.message = "bus_out" ; return end
  end
  if self.t >= self.phase_time then
    local all_green = true
    for i = 1, #self.buses do if not self:in_band(i) then all_green = false end end
    if all_green then self.green = self.green + 1 else self.phase_bad = true end
    self.t = 0
    self.out_t = {}
    self.over_t = 0
    self.phase = self.phase + 1
    if self.phase > self.phases then
      self.result = (not self.phase_bad and self.green >= self.phases) and "success" or "fail"
    else
      self.bands = power_constraints(self.setup, self.phase)
    end
  end
end

-- 信号解调：频率/相位两参数，线索与相干度（GDD §7.2）
local Signal = {}
Signal.__index = Signal

local SIGNAL_SETUP = {
  signal_01 = { target_freq = 12, targets = { 3, 7 }, windows = 3, duration = 90, inverted = false },
  signal_02 = { target_freq = 4, targets = { 5 }, windows = 2, duration = 75, inverted = true },
}

function Systems.new_signal(encounter, state)
  local setup = SIGNAL_SETUP[encounter] or SIGNAL_SETUP.signal_01
  local mg = setmetatable({}, Signal)
  mg.kind = "signal"
  mg.id = encounter or "signal_01"
  mg.targets = setup.targets
  mg.target_freq = setup.target_freq
  mg.windows = setup.windows
  mg.total_windows = setup.windows
  mg.duration = setup.duration
  mg.inverted = setup.inverted
  mg.understand = (state and state.counters and state.counters.understand) or 0
  mg.freq = 12
  mg.phase = 2
  mg.sel = 1                      -- 1=FREQ 2=PHASE
  mg.elapsed = 0
  mg.result = nil
  mg.message = ""
  mg.locking = false
  mg.lock_t = 0
  mg.last_dist = nil
  return mg
end

local function phase_dist(a, b)
  local d = math.abs((a or 0) - (b or 0))
  d = d % 8
  return math.min(d, 8 - d)
end

function Signal:coherence()
  local best = 0
  for _, phase in ipairs(self.targets) do
    local coh = 100 - 8 * math.abs(self.freq - self.target_freq) - 10 * phase_dist(self.phase, phase)
    if coh > best then best = coh end
  end
  if best < 0 then best = 0 end
  if best > 100 then best = 100 end
  return best
end

-- 反相台：信号_02 的左右是"读数反了"（understand≥2 时才有提示）
function Signal:adjust(param, delta)
  local step = self.inverted and -delta or delta
  if param == "freq" or self.sel == 1 then
    self.freq = math.max(0, math.min(24, self.freq + step))
  else
    self.phase = (self.phase + step) % 8
    if self.phase < 0 then self.phase = self.phase + 8 end
  end
end

function Signal:select(delta)
  self.sel = self.sel == 1 and 2 or 1
end

-- 消耗一次窗口试解调：相干度够就进入 6 秒锁定；返回是否开始锁定
function Signal:try_lock()
  if self.result or self.windows <= 0 then return false end
  self.windows = self.windows - 1
  local coh = self:coherence()
  if coh >= 85 then
    self.locking = true
    self.lock_t = 0
    self.message = "locking"
  else
    self.locking = false
    self.lock_t = 0
    local dist = math.abs(self.freq - self.target_freq) + phase_dist(self.phase, self.targets[1])
    if self.last_dist and dist < self.last_dist then
      self.message = "closer"
    elseif math.abs(self.freq - self.target_freq) > 3 then
      self.message = "freq_off"
    else
      self.message = "phase_off"
    end
    self.last_dist = dist
  end
  return self.locking
end

function Signal:update(dt)
  if self.result then return end
  self.elapsed = self.elapsed + dt
  if self.elapsed >= self.duration then
    self.result = "fail"
    self.message = "timeout"
    return
  end
  if self.locking then
    if self:coherence() >= 85 then
      self.lock_t = self.lock_t + dt
      if self.lock_t >= 6 then self.result = "success" end
    else
      self.locking = false
      self.lock_t = 0
    end
  elseif self.windows <= 0 then
    self.result = "fail"
    self.message = "no_window"
  end
end

Systems.POWER_SETUP = POWER_SETUP
Systems.SIGNAL_SETUP = SIGNAL_SETUP

-- 小游戏结算效果（GDD §7.1/§7.2）：成功/失败各自的资源与 flag
function Systems.minigame_result(mg)
  local ok = mg.result == "success"
  local effects = {}
  if mg.kind == "power" then
    if ok then
      effects[#effects + 1] = { res = "pwr", add = 6 }
      effects[#effects + 1] = { flag = "power_ok" }
      if mg.id == "power_02" then effects[#effects + 1] = { flag = "pod_repaired" } end
    else
      effects[#effects + 1] = { res = "pwr", add = -10 }
      effects[#effects + 1] = { res = "str", add = -8 }
      effects[#effects + 1] = { res = "san", add = -5 }
      effects[#effects + 1] = { flag = "power_fail" }
    end
  else
    if ok then
      effects[#effects + 1] = { counter = "signal_windows", add = 1 }
      if mg.id == "signal_01" then effects[#effects + 1] = { flag = "signal_locked" }
      else effects[#effects + 1] = { flag = "counter_signal_ok" } end
    else
      effects[#effects + 1] = { flag = "signal_fail" }
      if mg.id == "signal_02" then
        effects[#effects + 1] = { flag = "counter_signal_fail" }
        effects[#effects + 1] = { counter = "communion", add = 2 }
        effects[#effects + 1] = { res = "san", add = -12 }
      else
        effects[#effects + 1] = { res = "san", add = -8 }
        effects[#effects + 1] = { res = "pwr", add = -4 }
      end
    end
  end
  return ok, effects
end

return Systems

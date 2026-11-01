-- game.lua —— 世界状态与规则（GDD §3）：资源/时间/flag/counter/房间动作/结局判定/存档。
--
-- 不读键盘、不画东西、不出声；剧情数据交来的 effects 在这里被解释成状态变更，
-- 并把 goto/minigame/ending/failure 等控制指令回传给 story_engine。
local Map = require("map")
local Systems = require("systems")

local Game = {}
Game.__index = Game

Game.SAVE_KEY = "state"
Game.SETTINGS_KEY = "settings"
Game.META_KEY = "meta"
Game.SUMMARY_KEY = "summary"
Game.SLOT_MAX = 3
Game.AUTO_SLOT = 0

local function copy(src)
  local out = {}
  for k, v in pairs(src or {}) do
    if type(v) == "table" then out[k] = copy(v) else out[k] = v end
  end
  return out
end

local function as_list(value)
  if value == nil then return {} end
  if type(value) == "table" and value[1] ~= nil then return value end
  return { value }
end

-- ── 生命周期与状态初始化（GDD §3.1）──────────────────────────────────
function Game.new()
  local self = setmetatable({}, Game)
  self.map = Map.new()
  self.state = self:_new_state()
  self.settings = { speed = "normal", auto_wait = true }
  self.meta = { cleared = false, endings = {}, bad_stay = false }
  self:load_meta()
  self.ending_id = nil
  self.failure_id = nil
  return self
end

function Game:_new_state()
  local st = {
    schema = 1, chapter = 1, scene = "", line = 1, time = 0, room = "cryo",
    res = { o2 = Systems.INITIAL.o2, pwr = Systems.INITIAL.pwr,
            str = Systems.INITIAL.str, san = Systems.INITIAL.san },
    sys = copy(Systems.INITIAL.sys),
    flags = {}, counters = {}, seen = {}, route = "", objective = nil,
  }
  st.flags.crew_cryo_alive = true
  return st
end

function Game:new_run()
  self.map = Map.new()
  self.state = self:_new_state()
  self.ending_id, self.failure_id = nil, nil
  return self.state
end

-- ── 效果解释器（STORY_SCHEMA §8）────────────────────────────────────
-- 返回控制指令表：{ goto, minigame, encounter, on_success, on_fail,
--                  ending, failure, checkpoint, toast, sfx, music, art, variant }
function Game:apply_effects(effects)
  local dir = {}
  for _, e in ipairs(as_list(effects)) do
    if type(e) == "table" then
      if e.flag ~= nil then
        if Systems.FLAGS[e.flag] ~= true then
          phos.sys.log("story writes unknown flag: " .. tostring(e.flag))
        end
        if e.set == false then self.state.flags[e.flag] = nil
        else self.state.flags[e.flag] = true end
      elseif e.res ~= nil then
        if e.add ~= nil then Systems.add_res(self.state, e.res, e.add) end
        if e.set ~= nil then Systems.set_res(self.state, e.res, e.set) end
      elseif e.counter ~= nil then
        Systems.add_counter(self.state, e.counter, e.add or 0)
      elseif e.unlock ~= nil then
        self.map:unlock(e.unlock)
      elseif e.objective ~= nil then
        if e.objective == false then self.state.objective = nil
        else self.state.objective = e.objective end
      elseif e.objective_done ~= nil then
        self.state.rooms_done = self.state.rooms_done or {}
        self.state.rooms_done[e.objective_done] = true
        dir.done = true
      elseif e.checkpoint ~= nil then
        dir.checkpoint = true
      elseif e.minigame ~= nil then
        dir.minigame = e.minigame
        dir.encounter = e.encounter
        dir.on_success = e.on_success
        dir.on_fail = e.on_fail
      elseif e["goto"] ~= nil then
        dir["goto"] = e["goto"]
        return dir
      elseif e.ending ~= nil then
        dir.ending = e.ending
        return dir
      elseif e.failure ~= nil then
        dir.failure = e.failure
        return dir
      elseif e.toast ~= nil then
        dir.toast = e.toast
      elseif e.sfx ~= nil then
        dir.sfx = e.sfx
      elseif e.music ~= nil then
        dir.music = e.music
      elseif e.art ~= nil then
        dir.art = e.art
        dir.variant = e.variant
      else
        phos.sys.log("unknown effect in story data: " .. tostring(e[1]))
      end
    end
  end
  local failure = Systems.failure(self.state)
  if failure then dir.failure = failure; return dir end
  local forced = Systems.forced_ending(self.state)
  if forced then dir.ending = forced; return dir end
  return dir
end

function Game:check(cond)
  return Systems.check(self.state, cond)
end

-- ── 时间 / 结局 / 失败 ──────────────────────────────────────────────
function Game:advance_time(minutes)
  local notes = Systems.advance_time(self.state, minutes)
  return notes
end

function Game:update(dt)
  -- 时间只在动作/移动里推进（GDD §3.3）；这里只做"强制终章"与失败兜底
  local notes = {}
  if self.ending_id or self.failure_id then return notes end
  if (self.state.time or 0) >= Systems.TIME_TOTAL and (self.state.chapter or 1) < Systems.FINAL_CHAPTER then
    notes[#notes + 1] = { kind = "time_up" }
  end
  local fail = Systems.failure(self.state)
  if fail then
    self.failure_id = fail
    notes[#notes + 1] = { kind = "failure", id = fail }
  end
  local forced = Systems.forced_ending(self.state)
  if forced then
    self.ending_id = forced
    notes[#notes + 1] = { kind = "ending", id = forced }
  end
  return notes
end

function Game:available_endings() return Systems.available_endings(self.state) end
function Game:ending() return self.ending_id end
function Game:failure() return self.failure_id end

function Game:set_ending(id)
  self.ending_id = id
  self.state.route = id
  self:record_ending(id)
end

function Game:set_failure(id)
  self.failure_id = id
end

-- ── 房间 / 动作 / 移动 ─────────────────────────────────────────────
function Game:room() return Map.ROOMS[self.map.current] end

function Game:exits()
  local state = self.state
  local out = {}
  for _, exit in ipairs(self.map:exits(function(room)
    return Systems.check(state, room.requires)
  end)) do
    local ok, why = Systems.can_travel(state, self.map, exit.id)
    out[#out + 1] = { id = exit.id, room = exit.room, o2 = exit.o2, min = exit.min,
                      enabled = ok, reason = why }
  end
  return out
end

function Game:travel(room_id)
  local ok, edge = Systems.can_travel(self.state, self.map, room_id)
  if not ok then
    local reasons = {
      no_route = { zh = "这里去不了", en = "No route" },
      locked = { zh = "舱门锁着", en = "Locked" },
      hull = { zh = "结构低于 50，检修通道危险", en = "Hull below 50: the service passage is unsafe" },
    }
    local why = reasons[edge or "no_route"] or { zh = "无法移动", en = "Cannot move" }
    return false, phos.lang.pick(why)
  end
  if (self.state.res.o2 or 0) < (edge.o2 or 0) then
    return false, phos.lang.pick({ zh = "氧气不足", en = "Not enough oxygen" })
  end
  local notes = Systems.apply_travel(self.state, edge)
  self.map:move(room_id)
  self.state.room = self.map.current
  self.state.line = 1
  return true, nil, notes
end

function Game:actions(story)
  local list = Systems.room_actions(self.state, self.map, story)
  local out = {}
  for _, action in ipairs(list) do
    local enabled, reason = self:action_state(action)
    out[#out + 1] = { action = action, enabled = enabled, reason = reason,
                      label = action.label }
  end
  return out
end

-- 动作可用性：requires / 次数 / 一次 / 资源
function Game:action_state(action)
  local st = self.state
  if action.requires and not Systems.check(st, action.requires) then
    return false, phos.lang.pick(action.disabled_reason or { zh = "条件不满足", en = "Requirement not met" })
  end
  if action.once and self:is_done("act:" .. action.id) then
    return false, phos.lang.pick({ zh = "已经做过了", en = "Already done" })
  end
  if action.uses_per_chapter then
    local used = self:count_done("act:" .. action.id .. ":" .. tostring(st.chapter))
    if used >= action.uses_per_chapter then
      return false, phos.lang.pick(action.disabled_reason or { zh = "本章次数已用完", en = "No uses left this chapter" })
    end
  end
  local cost = action.cost or {}
  if cost.o2 and (st.res.o2 or 0) < cost.o2 then return false, phos.lang.pick({ zh = "氧气不足", en = "Not enough oxygen" }) end
  if cost.pwr and (st.res.pwr or 0) < cost.pwr then return false, phos.lang.pick(action.disabled_reason or { zh = "电力不足", en = "Not enough power" }) end
  if cost.min and (st.time or 0) + cost.min > Systems.TIME_TOTAL then
    return false, phos.lang.pick({ zh = "时间不够了", en = "Not enough time left" })
  end
  return true, ""
end

function Game:is_done(key) return self.state.rooms_done and self.state.rooms_done[key] == true end
function Game:count_done(prefix)
  local n = 0
  for key in pairs(self.state.rooms_done or {}) do
    if key:sub(1, #prefix + 1) == prefix .. ":" or key == prefix then n = n + 1 end
  end
  return n
end

-- 执行一个动作；返回 ok, msg, directive（directive.story = 要进入的场景 id）
function Game:perform_action(action)
  local enabled, reason = self:action_state(action)
  if not enabled then return false, reason end
  local st = self.state
  local cost = action.cost or {}
  if cost.o2 then Systems.add_res(st, "o2", -cost.o2) end
  if cost.pwr then Systems.add_res(st, "pwr", -cost.pwr) end
  local notes = {}
  if cost.min then
    for _, note in ipairs(self:advance_time(cost.min)) do notes[#notes + 1] = note end
  end
  local directive = {}
  if action.effects then directive = self:apply_effects(action.effects) end
  local chapter = tostring(st.chapter)
  if action.once then self.state.rooms_done = self.state.rooms_done or {}; self.state.rooms_done["act:" .. action.id] = true end
  if action.uses_per_chapter then
    self.state.rooms_done = self.state.rooms_done or {}
    local used = self:count_done("act:" .. action.id .. ":" .. chapter) + 1
    self.state.rooms_done["act:" .. action.id .. ":" .. chapter .. ":" .. tostring(used)] = true
  end
  if action.story then directive.story = action.story end
  local fail = Systems.failure(st)
  if fail then directive.failure = fail end
  local forced = Systems.forced_ending(st)
  if forced then directive.ending = forced end
  return true, "", directive, notes
end

-- ── 存档（GDD §9：0=自动，1..3 手动；state/settings/meta 三键）──────
function Game:serialize()
  local st = self.state
  return {
    schema = 1, chapter = st.chapter, time = st.time, room = st.room,
    res = copy(st.res), sys = copy(st.sys), flags = copy(st.flags),
    counters = copy(st.counters), seen = copy(st.seen), route = st.route or "",
    objective = st.objective and copy(st.objective) or nil,
    rooms_done = copy(st.rooms_done or {}),
    map = self.map:serialize(),
  }
end

function Game:deserialize(data)
  if type(data) ~= "table" or data.schema ~= 1 then return false end
  if type(data.res) ~= "table" then return false end
  local st = self:_new_state()
  st.chapter = tonumber(data.chapter) or 1
  st.time = tonumber(data.time) or 0
  for _, id in ipairs(Systems.RES_ORDER) do
    st.res[id] = Systems.clamp_res(id, tonumber(data.res[id]) or 0)
  end
  st.sys = copy(data.sys or st.sys)
  st.flags = copy(data.flags or {})
  st.counters = {}
  for name in pairs(Systems.COUNTER_CAPS) do
    local v = (data.counters or {})[name]
    st.counters[name] = math.max(0, math.min(Systems.COUNTER_CAPS[name], tonumber(v) or 0))
  end
  st.seen = copy(data.seen or {})
  st.route = data.route or ""
  st.objective = data.objective or nil
  st.rooms_done = copy(data.rooms_done or {})
  local map = Map.new()
  if not map:deserialize(data.map or {}) then return false end
  self.map = map
  st.room = map.current
  self.state = st
  self.ending_id = st.route ~= "" and st.route or nil
  self.failure_id = nil
  return true
end

-- 槽位内读写：切到目标槽，完成后切回调用前的槽
local function with_slot(slot, fn)
  local prev = phos.save.slot_index()
  if slot ~= prev then
    if not phos.save.slot(slot) then return nil end
  end
  local ok, result = pcall(fn)
  if slot ~= prev then phos.save.slot(prev) end
  if not ok then phos.sys.log("save slot error: " .. tostring(result)); return nil end
  return result
end

function Game:save(slot, story)
  local payload = {
    schema = 1,
    state = self:serialize(),
    story = story and story:serialize() or nil,
    settings = copy(self.settings),
  }
  local summary = {
    chapter = self.state.chapter, time = self.state.time, room = self.state.room,
    scene = story and (story:current_scene() or story:queued()) or "",
    chapter_title = story and story:chapter_title() or nil,
    res = copy(self.state.res),
  }
  return with_slot(slot or 0, function()
    local ok = phos.save.write(Game.SAVE_KEY, payload)
    phos.save.write(Game.SETTINGS_KEY, self.settings)
    phos.save.write(Game.SUMMARY_KEY, summary)
    return ok == true
  end) == true
end

function Game:load(slot, story)
  local payload = with_slot(slot or 0, function() return phos.save.read(Game.SAVE_KEY) end)
  if type(payload) ~= "table" or payload.schema ~= 1 then return false end
  if not self:deserialize(payload.state) then return false end
  if type(payload.settings) == "table" then
    self.settings.speed = payload.settings.speed or self.settings.speed
  end
  if story then
    if payload.story then story:deserialize(payload.story) end
    story.settings.speed = self.settings.speed
  end
  return true
end

function Game:has_save(slot)
  local payload = with_slot(slot or 0, function() return phos.save.read(Game.SAVE_KEY) end)
  return type(payload) == "table" and payload.schema == 1
end

function Game:save_summary(slot)
  local summary = with_slot(slot or 0, function() return phos.save.read(Game.SUMMARY_KEY) end)
  return type(summary) == "table" and summary or nil
end

function Game:save_settings()
  with_slot(Game.AUTO_SLOT, function() phos.save.write(Game.SETTINGS_KEY, self.settings) end)
end

function Game:load_settings()
  local settings = with_slot(Game.AUTO_SLOT, function() return phos.save.read(Game.SETTINGS_KEY) end)
  if type(settings) == "table" and settings.speed then self.settings.speed = settings.speed end
end

function Game:load_meta()
  local meta = with_slot(Game.AUTO_SLOT, function() return phos.save.read(Game.META_KEY) end)
  if type(meta) == "table" then
    self.meta.cleared = meta.cleared == true
    self.meta.bad_stay = meta.bad_stay == true
    self.meta.endings = type(meta.endings) == "table" and copy(meta.endings) or {}
  end
end

function Game:save_meta()
  with_slot(Game.AUTO_SLOT, function() phos.save.write(Game.META_KEY, self.meta) end)
end

function Game:record_ending(id)
  self.meta.cleared = true
  self.meta.endings[id] = true
  if id == "E2" and not (self.state.flags.crew_cryo_alive == true) then
    self.meta.bad_stay = true
  end
  self:save_meta()
end

function Game:endings_seen()
  local n = 0
  for _, id in ipairs({ "E1", "E2", "E3", "E4" }) do
    if self.meta.endings[id] then n = n + 1 end
  end
  return n
end

return Game

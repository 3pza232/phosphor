-- story_engine.lua —— 剧情引擎：装载 story/*、条件/效果求值接线、场景推进、已读、存档态。
--
-- 数据契约见 design/STORY_SCHEMA.md（权威）。本文件只做"播放与校验"：
--   * effect 交给 opts.apply（game 执行状态变更，并把 goto/minigame/ending/failure 等控制指令回传）；
--   * cond 交给 opts.check（systems 的唯一求值实现）；
--   * 文本排版/逐字/分页在此完成，ui 只负责把结果画出来。
local Systems = require("systems")
local Map = require("map")

local Story = {}
Story.__index = Story

Story.SPEED = { slow = 20, normal = 34, fast = 52, instant = 9999 }  -- 列/秒（GDD §8.4）
Story.PAGE_LINES = 3                                                  -- 每页正文行数
Story.PAGE_COLS = 74                                                  -- 每行可用列数
Story.HISTORY_MAX = 200

-- ── 文本排版：按显示列宽折行（中文 2 列），并给出逐字/分页进度 ─────────
function Story.wrap(text, cols)
  cols = math.max(1, math.floor(cols or Story.PAGE_COLS))
  local lines, line, width = {}, "", 0
  for _, cp in utf8.codes(text or "") do
    local ch = utf8.char(cp)
    local w = phos.text.width(ch)
    if width + w > cols and width > 0 then
      lines[#lines + 1] = line
      line, width = "", 0
    end
    line = line .. ch
    width = width + w
  end
  lines[#lines + 1] = line
  return lines
end

local function as_list(value)
  if value == nil then return {} end
  if type(value) == "table" and value[1] ~= nil then return value end
  return { value }
end

local function pick(fields)
  if type(fields) == "string" then return fields end
  if type(fields) ~= "table" then return "" end
  return phos.lang.pick(fields)
end

local function text_cols(text)
  return phos.text.width(text or "")
end

-- 稳定装载：模块不存在时返回 nil（剧情组按章交付，程序侧不至于崩）
local function load_module(name)
  if not phos.assets.exists(name:gsub("%.", "/") .. ".lua") then return nil end
  local ok, mod = pcall(require, name)
  if ok and type(mod) == "table" then return mod end
  phos.sys.log("story module load failed: " .. tostring(name))
  return nil
end

-- 场景序号（GDD §11 / STORY_SCHEMA §11）：seen 用
local CH_OFFSET = { 0, 0, 6, 13, 19, 26, 33, 41, 47 }
local ENDING_ORDINAL = { e_leave = 54, e_stay = 55, e_cross = 56, e_signal = 57,
                         f_suffocate = 58, f_hull = 59 }

function Story.new(opts)
  opts = opts or {}
  local self = setmetatable({}, Story)
  self.apply = opts.apply or function() return {} end
  self.check = opts.check or function() return true end
  self.toast = opts.toast or function() end
  self.sfx = opts.sfx or function() end
  self.music = opts.music or function() end
  self.checkpoint = opts.checkpoint or function() end
  self.on_scene = opts.on_scene or function() end      -- (scene_def)
  self.on_room = opts.on_room or function() end
  self.on_chapter = opts.on_chapter or function() end
  self.mark_seen = opts.mark_seen or function() end
  self.is_seen = opts.is_seen or function() return false end
  self.on_art = opts.on_art or function() end
  self.on_ending = opts.on_ending or function() end
  self.mark_done = opts.mark_done or function() end
  self.is_done = opts.is_done or function() return false end
  self.settings = { speed = "normal", auto_wait = true }
  self.auto = false
  self.ff = false
  self.history = {}
  self.chapter = 1
  self.scene = nil            -- 当前 scene 定义
  self.scene_id = nil
  self.scene_was_seen = false
  self.line_i = 0
  self.page = 0
  self.pages = {}
  self.shown = 0
  self.typing = false
  self.wait = 0
  self.choices = nil          -- 过滤后的选项（含 disabled）
  self.queued_next = nil      -- 退出到探索后"继续主线"的目标
  self.ending = nil
  self.failure = nil
  self.loaded = false
  self:load_chapters()
  self:validate()
  return self
end

function Story:load_chapters()
  self.chapters, self.scenes, self.ordinals = {}, {}, {}
  self.characters = load_module("story.characters")
  self.endings_data = load_module("story.endings")
  for ch = 1, 8 do
    local mod = load_module("story.ch" .. ch)
    if mod and mod.schema == 1 and mod.chapter == ch then
      self.chapters[ch] = mod
      for index, scene in ipairs(mod.scenes or {}) do
        if type(scene) == "table" and type(scene.id) == "string" then
          self.scenes[scene.id] = scene
          self.ordinals[scene.id] = (CH_OFFSET[ch] or 0) + index
        end
      end
    end
  end
  -- 结局/失败场景也入索引（ending 场景无 next）
  if self.endings_data then
    for _, scene in ipairs(self.endings_data.scenes or {}) do
      if type(scene) == "table" and type(scene.id) == "string" then
        self.scenes[scene.id] = scene
        self.ordinals[scene.id] = ENDING_ORDINAL[scene.id] or 99
      end
    end
    self.endings_meta = self.endings_data.endings or {}
    self.failures_meta = self.endings_data.failures or {}
  else
    self.endings_meta, self.failures_meta = {}, {}
  end
  -- 剧情组按章交付：数据未就绪/语法未通过时用内置占位章兜底，
  -- 保证"标题 → 开始 → 第一章 → 探索"这条管线始终可跑（不冒充正式剧情）。
  if not self.chapters[1] then
    self.placeholder_active = true
    local ph = Story.placeholder_chapter()
    self.chapters[1] = ph
    for index, scene in ipairs(ph.scenes) do
      self.scenes[scene.id] = scene
      self.ordinals[scene.id] = index
    end
  end
  self.loaded = next(self.scenes) ~= nil
end

function Story.placeholder_chapter()
  return {
    schema = 1, chapter = 1,
    title = { zh = "静默（占位）", en = "SILENCE (PLACEHOLDER)" },
    start = "c1_s01",
    scenes = {
      { id = "c1_s01", chapter = 1, room = "cryo", art = "awake", checkpoint = true,
        on_enter = {
          { objective = { zh = "走到医疗舱（占位目标）", en = "Reach the medbay (placeholder)" } },
          { toast = { zh = "剧情数据加载中：当前为占位章节", en = "Story data pending: placeholder chapter" } },
        },
        lines = {
          { speaker = "narrator", text = { zh = "冷。站体的呼吸被调成了省电模式。" } },
          { speaker = "hestia", text = { zh = "你醒着。很好。站内还有四十二小时。" } },
          { speaker = "ye", text = { zh = "其他人呢？" } },
          { speaker = "hestia", text = { zh = "……记录显示他们在舱。" } },
        },
        next = "c1_s02",
      },
      { id = "c1_s02", chapter = 1, art = "observe",
        lines = {
          { speaker = "narrator", text = { zh = "舷窗外，默尔的光被拉成一条细白的弧。" } },
          { speaker = "hestia", text = { zh = "先恢复供电吧。医疗舱在环廊尽头。" } },
        },
        next = nil,
      },
    },
  }
end

-- 结构校验（STORY_SCHEMA §12 的运行时子集）：只记日志、不阻塞装载；
-- 数据问题不应该让玩家开不了机，但必须让 QA/剧情组看得见。
function Story:validate()
  self.validation = { errors = {}, warnings = {} }
  local function err(msg) self.validation.errors[#self.validation.errors + 1] = msg end
  local function warn(msg) self.validation.warnings[#self.validation.warnings + 1] = msg end
  local cast = self.characters and self.characters.cast or {}
  local Map_rooms = Map.ROOMS
  local seen_ids = {}
  for ch = 1, 8 do
    local mod = self.chapters[ch]
    if mod then
      if mod.schema ~= 1 then err("ch" .. ch .. ": schema ~= 1") end
      if mod.chapter ~= ch then err("ch" .. ch .. ": chapter mismatch") end
      if not mod.start or not self.scenes[mod.start] then err("ch" .. ch .. ": bad start") end
      for _, scene in ipairs(mod.scenes or {}) do
        local id = scene.id or "?"
        if seen_ids[id] then err("duplicate scene id: " .. id) end
        seen_ids[id] = true
        if not id:match("^c[1-8]_s%d%d$") then err("bad scene id: " .. id) end
        if scene.speaker ~= nil and type(scene.speaker) ~= "string" then warn(id .. ": speaker on scene ignored") end
        local lines = scene.lines or {}
        if #lines == 0 and not (scene.choices and #scene.choices > 0) then
          err(id .. ": empty lines and no choices")
        end
        for _, line in ipairs(lines) do
          if line.speaker and not cast[line.speaker] then err(id .. ": unknown speaker " .. line.speaker) end
          if type(line.text) ~= "table" and type(line.text) ~= "string" then err(id .. ": missing text") end
          for _, e in ipairs(line.effects or {}) do self:_check_effect(id, e, err) end
        end
        if scene.choices and #scene.choices > 5 then err(id .. ": >5 choices") end
        if scene.choices and scene.next then warn(id .. ": choices and next both present") end
        for _, ch2 in ipairs(scene.choices or {}) do
          if ch2.next and not self.scenes[ch2.next] then err(id .. ": choice next missing " .. ch2.next) end
          for _, e in ipairs(ch2.effects or {}) do self:_check_effect(id, e, err) end
        end
        if scene.next and not self.scenes[scene.next] then err(id .. ": next missing " .. scene.next) end
        if scene.room and not (Map_rooms and Map_rooms[scene.room]) then
          warn(id .. ": unknown room " .. scene.room)
        end
        for _, e in ipairs(scene.on_enter or {}) do self:_check_effect(id, e, err) end
        for _, e in ipairs(scene.on_exit or {}) do self:_check_effect(id, e, err) end
      end
    end
  end
  for _, msg in ipairs(self.validation.errors) do phos.sys.log("story validate error: " .. msg) end
  for _, msg in ipairs(self.validation.warnings) do phos.sys.log("story validate warn: " .. msg) end
  return self.validation
end

function Story:_check_effect(scene_id, e, err)
  if type(e) ~= "table" then err(scene_id .. ": effect is not a table"); return end
  if e.flag and not Systems.FLAGS[e.flag] then err(scene_id .. ": unknown flag " .. tostring(e.flag)) end
  if e.counter and not Systems.COUNTER_CAPS[e.counter] then
    err(scene_id .. ": unknown counter " .. tostring(e.counter))
  end
  if e.res and not Systems.RES_BY_ID[e.res] then err(scene_id .. ": unknown res " .. tostring(e.res)) end
  if e.minigame and not (e.encounter == "power_01" or e.encounter == "power_02"
      or e.encounter == "signal_01" or e.encounter == "signal_02") then
    err(scene_id .. ": unknown minigame encounter " .. tostring(e.encounter))
  end
end

function Story:has_scene(id)
  return type(id) == "string" and self.scenes[id] ~= nil
end

function Story:chapter_def(n) return self.chapters[n or self.chapter] end

function Story:chapter_title()
  local def = self:chapter_def()
  return def and def.title or { zh = "", en = "" }
end

-- ── 条件：直接转交 systems 的唯一实现 ─────────────────────────────────
function Story:choices_available(scene)
  local out = {}
  for i, ch in ipairs(scene.choices or {}) do
    local used = ch.once and self.is_done("choice:" .. tostring(ch.id or i))
    if type(ch) == "table" and not used and self.check(ch.if_) then
      local enabled = self.check(ch.requires)
      out[#out + 1] = {
        index = i, id = ch.id or ("choice" .. i), text = pick(ch.text),
        disabled = not enabled,
        reason = (not enabled) and pick(ch.disabled_reason or { zh = "", en = "" }) or "",
        marker = ch.marker or "normal",
      }
    end
  end
  return out
end

-- ── 效果执行：game 执行状态，并把控制指令回传 ─────────────────────────
function Story:_run(effects)
  local directive = self.apply(effects)
  if type(directive) ~= "table" then return {} end
  if directive.checkpoint then self.checkpoint() end
  if directive.toast then self.toast(directive.toast) end
  if directive.sfx then self.sfx(directive.sfx) end
  if directive.music then self.music(directive.music) end
  if directive.art then self.on_art(directive.art, directive.variant) end
  if directive.minigame then
    self.pending_minigame = { kind = directive.minigame, encounter = directive.encounter,
                              on_success = directive.on_success, on_fail = directive.on_fail }
  end
  return directive
end

-- ── 场景进入与推进 ───────────────────────────────────────────────────
function Story:enter(id, opts)
  opts = opts or {}
  local scene = self.scenes[id]
  if not scene then return false end
  self.scene, self.scene_id = scene, id
  self.line_i, self.page, self.pages, self.shown, self.wait = 0, 0, {}, 0, 0
  self.choices, self.queued_next, self.pending_minigame = nil, nil, nil
  self.typing = false
  local was_seen = self.is_seen(self.ordinals[id] or 0)
  self.scene_was_seen = was_seen
  self.mark_seen(self.ordinals[id] or 0)
  if scene.chapter and scene.chapter ~= self.chapter then
    self.chapter = scene.chapter
    self.on_chapter(self.chapter)
  end
  if scene.room then self.on_room(scene.room) end
  self.on_scene(scene)
  if scene.music then self.music(scene.music) end
  if scene.art then self.on_art(scene.art, scene.art_variant) end
  if scene.checkpoint and not opts.skip_enter then self.checkpoint() end
  if not opts.skip_enter and scene.on_enter then
    local d = self:_run(scene.on_enter)
    if d["goto"] and self:has_scene(d["goto"]) then return self:enter(d["goto"], {}) end
    if d.ending or d.failure then return self:_finish(d) end
  end
  if not was_seen and self.ff then
    self.ff = false
    self.toast({ zh = "未读内容，快进已停止", en = "Unread content: fast-forward stopped" })
  end
  self:_next_line()
  return true
end

function Story:_line()
  return self.scene and self.scene.lines and self.scene.lines[self.line_i] or nil
end

function Story:_next_line()
  self.line_i = self.line_i + 1
  local line
  repeat
    line = self:_line()
    if not line then break end
    if line.if_ ~= nil and not self.check(line.if_) then
      self.line_i = self.line_i + 1
    else
      break
    end
  until false
  if not line then return self:_end_scene() end
  -- 行效果先于显示（STORY_SCHEMA §5）
  if line.effects then
    local d = self:_run(line.effects)
    if d["goto"] and self:has_scene(d["goto"]) then return self:enter(d["goto"], {}) end
    if d.ending or d.failure then return self:_finish(d) end
  end
  if line.sfx then self.sfx(line.sfx) end
  if line.art then self.on_art(line.art, line.art_variant) end
  local who = line.speaker and self:_speaker_name(line.speaker) or ""
  self:_push_history(who, pick(line.text))
  self.page = 1
  self.pages = self:_paginate(pick(line.text))
  self.shown = 0
  self.wait = 0
  self.typing = true
  self.choices = nil
end

function Story:_paginate(text)
  local lines = Story.wrap(text, Story.PAGE_COLS)
  local pages = {}
  for i = 1, #lines, Story.PAGE_LINES do
    local page = {}
    for k = i, math.min(#lines, i + Story.PAGE_LINES - 1) do page[#page + 1] = lines[k] end
    pages[#pages + 1] = page
  end
  if #pages == 0 then pages[1] = { "" } end
  return pages
end

function Story:_push_history(who, text)
  self.history[#self.history + 1] = { chapter = self.chapter, scene = self.scene_id or "",
                                      who = who, text = text }
  while #self.history > Story.HISTORY_MAX do table.remove(self.history, 1) end
end

function Story:_speaker_name(id)
  local cast = self.characters and self.characters.cast
  local entry = cast and cast[id]
  return entry and pick(entry.name) or tostring(id)
end

function Story:speaker_id()
  local line = self:_line()
  return line and line.speaker or nil
end

function Story:speaker_color()
  local id = self:speaker_id()
  if id and self.characters and self.characters.cast and self.characters.cast[id] then
    return self.characters.cast[id].color or "gray"
  end
  return "gray"
end

function Story:_end_scene()
  local scene = self.scene
  if not scene then return end
  if scene.on_exit then
    local d = self:_run(scene.on_exit)
    if d["goto"] and self:has_scene(d["goto"]) then return self:enter(d["goto"], {}) end
    if d.ending or d.failure then return self:_finish(d) end
  end
  local next_id = scene.next
  if next_id and next_id ~= "" then
    self.scene, self.scene_id = nil, nil
    self.queued_next = next_id       -- 回到探索：由"继续主线"进入
  else
    self.scene, self.scene_id = nil, nil
    self.queued_next = nil
  end
  self.typing = false
end

function Story:_finish(directive)
  self.scene, self.scene_id, self.queued_next = nil, nil, nil
  self.typing = false
  if directive.ending then
    self.ending = directive.ending
    self.on_ending(directive.ending)
  elseif directive.failure then
    self.failure = directive.failure
    self.on_ending(directive.failure)
  end
end

-- ── 玩家推进 ─────────────────────────────────────────────────────────
function Story:full_text()
  local line = self:_line()
  if not line then return "" end
  return pick(line.text)
end

function Story:page_lines()
  return self.pages[self.page] or {}
end

function Story:page_cols()
  local total = 0
  for _, line in ipairs(self:page_lines()) do total = total + text_cols(line) end
  return total
end

function Story:typing_done()
  return not self.typing or self.shown >= self:page_cols()
end

-- 可见文本：按已显示列数切当前页（逐字显示）
function Story:visible_page()
  local out = {}
  local left = self.typing and self.shown or math.huge
  for _, line in ipairs(self:page_lines()) do
    if left <= 0 then
      out[#out + 1] = ""
    else
      local take, width = "", 0
      for _, cp in utf8.codes(line) do
        local ch = utf8.char(cp)
        local w = phos.text.width(ch)
        if width + w > left then break end
        take = take .. ch
        width = width + w
      end
      out[#out + 1] = take
      left = left - width
    end
  end
  return out
end

local PACE_MULT = { slow = 0.6, normal = 1, fast = 1.5 }

function Story:update(dt)
  if not self.scene or type(dt) ~= "number" or dt <= 0 then return end
  if self.typing then
    local speed = Story.SPEED[self.settings.speed] or 34
    local line = self:_line()
    local mult = line and line.pace and PACE_MULT[line.pace] or 1
    self.shown = self.shown + speed * mult * dt
    if self.shown >= self:page_cols() then
      self.shown = self:page_cols()
      if self.page >= #self.pages then self.typing = false end
    end
    if self.ff and self.typing then self.shown = self:page_cols(); self.typing = false end
    return
  end
  if self.ff then
    if not self:_ff_allowed() then
      self.ff = false
      self.toast({ zh = "未读内容，快进已停止", en = "Unread content: fast-forward stopped" })
      return
    end
    self.wait = self.wait + dt
    if self.wait >= 0.05 then self.wait = 0; self:advance() end
    return
  end
  if self.auto then
    if self.choices then self.auto = false; return end
    local line = self:_line()
    local wait = 0.9 + 0.02 * (self:page_cols() or 0)
    wait = math.min(3.5, math.max(0.9, wait))
    if line and line.wait then wait = wait + line.wait end
    self.wait = self.wait + dt
    if self.wait >= wait then self.wait = 0; self:advance() end
  end
end

function Story:_ff_allowed()
  if self.failure or self.ending then return false end
  if self.scene and self.scene.no_skip then return false end
  local line = self:_line()
  if line and line.no_skip then return false end
  return self.scene_was_seen
end

function Story:toggle_auto()
  self.auto = not self.auto
  if self.auto then self.ff = false end
  return self.auto
end

function Story:toggle_ff()
  self.ff = not self.ff
  if self.ff then self.auto = false end
  return self.ff
end

-- A：未显示完 → 立即显示；否则翻页/下一行；到底 → 显示选项或结束场景
function Story:advance()
  if not self.scene then
    if self.queued_next and self:has_scene(self.queued_next) then
      local id = self.queued_next
      self.queued_next = nil
      return self:enter(id, {})
    end
    return false
  end
  if self.typing or self.shown < self:page_cols() then
    self.shown = self:page_cols()
    if self.page >= #self.pages then self.typing = false end
    return true
  end
  if self.page < #self.pages then
    self.page = self.page + 1
    self.shown = 0
    self.typing = true
    return true
  end
  local choices = self:_available_choices()
  if choices and #choices > 0 then
    self.choices = choices
    self.auto = false
    return false
  end
  self:_next_line()
  return true
end

function Story:_available_choices()
  if not self.scene or not self.scene.choices then return nil end
  return self:choices_available(self.scene)
end

function Story:has_choices()
  return self.choices ~= nil and #self.choices > 0
end

function Story:select(visible_index)
  if not self.choices then return false end
  local entry = self.choices[visible_index]
  if not entry or entry.disabled then return false end
  local ch = self.scene.choices[entry.index]
  self.choices = nil
  if ch.once then self.mark_done("choice:" .. tostring(ch.id or entry.index)) end
  if ch.effects then
    local d = self:_run(ch.effects)
    if d["goto"] and self:has_scene(d["goto"]) then return self:enter(d["goto"], {}) end
    if d.ending or d.failure then return self:_finish(d) end
    if d.minigame then return true end
  end
  if ch.once then
    local done = self.apply and self.apply({ { objective_done = ch.id } }) or nil
    if type(done) == "table" and done.done then end
  end
  if ch.next and self:has_scene(ch.next) then
    self.scene, self.scene_id, self.queued_next = nil, nil, nil
    return self:enter(ch.next, {})
  end
  self:_end_scene()
  return true
end

-- 小游戏结算后：进入 on_success / on_fail
function Story:finish_minigame(success)
  local pending = self.pending_minigame
  self.pending_minigame = nil
  if not pending then return false end
  local target = success and pending.on_success or pending.on_fail
  if target and self:has_scene(target) then return self:enter(target, {}) end
  self.scene, self.scene_id = nil, nil
  return false
end

function Story:peek_minigame()
  return self.pending_minigame
end

function Story:take_minigame()
  local m = self.pending_minigame
  self.pending_minigame = nil
  return m
end

function Story:idle()
  return self.scene == nil and self.queued_next ~= nil
end

function Story:done()
  return self.scene == nil and self.queued_next == nil
end

function Story:current_scene() return self.scene_id end
function Story:queued() return self.queued_next end
function Story:objective() return nil end  -- objective 存在 game.state.objective（HUD 用）

-- ── 存读档：存档只保存"当前场景"（GDD §9：总是从场景第 1 行恢复）─────
function Story:serialize()
  return { chapter = self.chapter, scene = self.scene_id or self.queued_next or "",
           auto = self.auto, ff = self.ff, speed = self.settings.speed }
end

function Story:deserialize(data)
  if type(data) ~= "table" then return false end
  if type(data.chapter) == "number" then self.chapter = data.chapter end
  if type(data.speed) == "string" then self.settings.speed = data.speed end
  self.auto = data.auto == true
  self.ff = false
  if type(data.scene) == "string" and data.scene ~= "" then
    if self:has_scene(data.scene) then return self:enter(data.scene, { skip_enter = true }) end
    return false
  end
  self.scene, self.scene_id, self.queued_next = nil, nil, nil
  return true
end

-- 从第 1 章开始
function Story:start()
  local first = self.chapters[1]
  if not first or not first.start then return false end
  self.history = {}
  self.ending, self.failure = nil, nil
  return self:enter(first.start, {})
end

return Story

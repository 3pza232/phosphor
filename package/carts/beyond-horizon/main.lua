-- main.lua —— 《视界线外》入口：生命周期、屏幕状态机、场景栈、输入→意图、存档、观测。
--
-- 屏幕：title / play(explore|dialogue) / ending / failure；浮窗全是 phos.scene（modal,
-- pause_world + audio_pause）：status / map / history / pause / save / load / settings /
-- chapter_card / mg_power / mg_signal。同一帧只有一个 render 的 input=true。
local Map = require("map")
local Systems = require("systems")
local Game = require("game")
local Story = require("story_engine")
local UI = require("ui")

local Text = {
  zh = { saved = "已保存", save_fail = "保存失败", loaded = "已读取", no_save = "没有可读取的存档",
         new_run = "观测开始", auto_on = "自动播放", auto_off = "自动关闭",
         ff_on = "快进", ff_off = "快进关闭", ff_stop = "未读内容，快进已停止",
         pause = "暂停", continue = "继续主线", clear_seen = "已清除已读记录",
         no_action = "现在做不了这件事", moved = "抵达 %s（%d 分钟）",
         time_up = "站体进入不可回收轨道", ending_seen = "结局已记录" },
  en = { saved = "SAVED", save_fail = "SAVE FAILED", loaded = "LOADED", no_save = "NO SAVES",
         new_run = "OBSERVATION BEGINS", auto_on = "AUTO", auto_off = "AUTO OFF",
         ff_on = "FAST FORWARD", ff_off = "FF OFF", ff_stop = "Unread content: FF stopped",
         pause = "PAUSED", continue = "CONTINUE", clear_seen = "READ MARKS CLEARED",
         no_action = "NOT AVAILABLE", moved = "ARRIVED %s (%d min)",
         time_up = "The station has entered an unrecoverable orbit", ending_seen = "ENDING RECORDED" },
}
local function T() return phos.lang.dict(Text) end
local function pick(fields)
  if type(fields) == "string" then return fields end
  return phos.lang.pick(fields)
end

local cart = {}
local game, story
local mode = "title"       -- title / play / ending / failure
local screen = "explore"   -- play 内：explore / dialogue
local title_grace = 0
local pending = {}         -- 每个 render 屏幕上一帧返回的事件
local ui_screen = "title"
local ending_id = nil
local failure_id = nil
local minigame = nil
local mg_kind = nil
local chapter_shown = 0
local ending_played = false
local failure_scene_played = false
local choice_guard = 0       -- 选项刚出现时吞几帧 A，避免连按把关键选择直接选掉
local choice_guard_used = false  -- 同一组选项只启动一次 guard，否则计数归零后会无限重置
local history_scroll = 0     -- 历史从最新行往回退的行数（0 = 当前对白在最后一行）
local input_guard = 0
local mg_launched = nil   -- 已 push 的 minigame 待结算对象（避免 after_story 每帧重复压栈）   -- 浮窗/小游戏弹栈后吞 1-2 帧按键，避免 B 穿透到对话（历史）
local debug_tuning = {}
local play_sfx, play_music   -- 前向声明：剧情回调在 init 里引用它们

local function init_pending()
  pending = { title = {}, explore = {}, dialogue = {}, pause = {}, status = {}, map = {},
              history = {}, save = {}, load = {}, settings = {}, mg = {}, chapter = {} }
end

local function collect(name, events)
  for _, ev in ipairs(events or {}) do pending[name][#pending[name] + 1] = ev end
end

local function take(name)
  local out = pending[name]
  pending[name] = {}
  return out
end

-- ── 存档 / 检查点 ───────────────────────────────────────────────────
local function checkpoint()
  if not game or not story then return end
  game:save(Game.AUTO_SLOT, story)
end

local function load_slot(slot)
  if not game:load(slot, story) then
    phos.ui.toast(T().no_save)
    return false
  end
  game.story = story
  mode = "play"
  screen = story:current_scene() and "dialogue" or "explore"
  ending_id, failure_id = game:ending(), game:failure()
  if game:ending() then mode = "ending"; ending_id = game:ending() end
  phos.ui.reset()
  phos.ui.toast(T().loaded)
  return true
end

local function start_new_run()
  game:new_run()
  game.story = story
  story.history = {}
  story.auto, story.ff = false, false
  story.ending, story.failure = nil, nil
  ending_played = false
  mode, screen, ending_id, failure_id = "play", "explore", nil, nil
  chapter_shown = 0
  phos.ui.reset()
  local ok = story:start()
  if ok then
    screen = story:current_scene() and "dialogue" or "explore"
    checkpoint()
  end
  phos.audio.beep(440, 0.08, { wave = "triangle", volume = 0.2 })
end

-- ── 剧情引擎接线 ────────────────────────────────────────────────────
local function make_story()
  return Story.new{
    apply = function(effects) return game:apply_effects(effects) end,
    check = function(cond) return game:check(cond) end,
    toast = function(fields) phos.ui.toast(pick(fields)) end,
    sfx = function(id) play_sfx(id) end,
    music = function(id) play_music(id) end,
    checkpoint = function() checkpoint() end,
    on_scene = function(scene_def) end,
    on_room = function(id)
      game.map:unlock(id)
      game.map:move(id)
      game.state.room = id
    end,
    on_chapter = function(ch)
      game.state.chapter = ch
      if ch ~= chapter_shown then
        chapter_shown = ch
        push_chapter_card(ch)
      end
      checkpoint()
    end,
    mark_done = function(key)
      game.state.rooms_done = game.state.rooms_done or {}
      game.state.rooms_done[key] = true
    end,
    is_done = function(key)
      return game.state.rooms_done and game.state.rooms_done[key] == true
    end,
    mark_seen = function(ordinal)
      if ordinal and ordinal > 0 and not game.state.seen[ordinal] then
        game.state.seen[ordinal] = true
      end
    end,
    is_seen = function(ordinal) return game.state.seen[ordinal] == true end,
    on_art = function(slot, variant)
      game.state.art, game.state.art_variant = slot, variant
    end,
    on_ending = function(id)
      if id and id:sub(1, 1) == "F" then
        -- 失败场景的 on_exit 也会走到这里；F 开头必须进失败屏，不能当结局
        failure_id = id
        ending_played = true
        mode = "failure"
        phos.audio.beep(90, 0.5, { wave = "sine", volume = 0.2 })
        return
      end
      ending_id = id
      if id and id:sub(1, 1) == "E" then
        game:set_ending(id)
        game:record_ending(id)
      end
      ending_played = true
      mode = "ending"
      phos.audio.beep(90, 0.5, { wave = "sine", volume = 0.2 })
    end,
  }
end

-- 音效/音乐：GDD §13.4 的最小实现（不阻塞、缺资源只警告）
play_sfx = function(id)
  local kind, value = tostring(id):match("^(%a+):(.+)$")
  if kind == "beep" then
    local hz = tonumber(value) or 440
    phos.audio.beep(hz, 0.05, { wave = "square", volume = 0.18 })
  elseif kind == "perc" then
    phos.audio.perc(value)
  else
    phos.audio.beep(660, 0.04, { wave = "square", volume = 0.15 })
  end
end

play_music = function(id)
  -- 极缓、极简的深空环境音：低音持续音 + 稀疏的单音，无打击乐。
  -- 40 BPM、16 分音符一格 => 每段 64 格约 24 秒；三段轮转约 1.5 分钟才回环。
  -- 旋律刻意只用小调/空五度与长休止，不写“欢快”的密集节奏。
  local function pad(track, steps, volume)
    return { wave = track, volume = volume, release = 2.4, attack = 0.8, steps = steps }
  end
  local ambient = {
    cold = {
      bpm = 40, loop = true, wave = "sine",
      patterns = {
        A = {
          lead = pad("sine", "D4 = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.34),
          bass = pad("triangle", "D2 = = = = = = = = = = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.46),
        },
        B = {
          lead = pad("sine", "- - - - - - - - A3 = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.32),
          bass = pad("triangle", "A1 = = = = = = = = = = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.44),
        },
        C = {
          lead = pad("sine", "- - - - - - - - - - - - - - - - F4 = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.30),
          bass = pad("triangle", "D2 = = = = = = = = = = = = = = = = A1 = = = = = = = = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.44),
        },
      },
      order = { "A", "B", "A", "C" },
    },
    deep = {
      bpm = 38, loop = true, wave = "sine",
      patterns = {
        A = {
          lead = pad("sine", "A3 = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.30),
          bass = pad("triangle", "A1 = = = = = = = = = = = = = = = = = = = = = = = = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.42),
        },
        B = {
          lead = pad("sine", "- - - - - - - - - - - - - - - - E4 = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.28),
          bass = pad("triangle", "E1 = = = = = = = = = = = = = = = = A1 = = = = = = = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.42),
        },
      },
      order = { "A", "B", "A" },
    },
    signal = {
      bpm = 42, loop = true, wave = "sine",
      patterns = {
        A = {
          lead = pad("sine", "A4 = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.24),
          bass = pad("triangle", "D2 = = = = = = = = = = = = = = = = A1 = = = = = = = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.40),
        },
        B = {
          lead = pad("sine", "- - - - - - - - - - - - - - - - F4 = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.26),
          bass = pad("triangle", "D2 = = = = = = = = = = = = = = = = D2 = = = = = = = = = = = = = - - - - - - - - - - - - - - - - - - - - - - - - - - -", 0.40),
        },
      },
      order = { "A", "B", "A", "B" },
    },
  }
  local tune = ambient[id] or ambient.cold
  phos.audio.music(tune)
end

-- ── 场景：暂停 / 状态 / 地图 / 历史 / 存档 / 设置 / 章卡 / 小游戏 ──────
local function open_overlay(fn) fn() end

function push_chapter_card(ch)
  local title = story:chapter_title()
  phos.scene.push{
    id = "chapter_card", modal = true, pause_world = true, audio_pause = true,
    update = function(dt)
      local events = take("chapter")
      if phos.input.pressed("a") or phos.input.pressed("start") then phos.scene.pop() end
      for _, ev in ipairs(events) do if ev.kind == "cancelled" then phos.scene.pop() end end
    end,
    draw = function() UI.chapter_card(ch, title) end,
  }
end

function push_pause()
  local function update(dt)
    if phos.input.pressed("start") then phos.scene.pop() end
    for _, ev in ipairs(take("pause")) do
      if ev.kind == "cancelled" then phos.scene.pop()
      elseif ev.kind == "changed" and ev.confirm then
        if ev.id == "pause/resume" then phos.scene.pop()
        elseif ev.id == "pause/save" then push_save()
        elseif ev.id == "pause/load" then push_load()
        elseif ev.id == "pause/settings" then push_settings()
        elseif ev.id == "pause/title" then
          phos.scene.clear()
          mode = "title"
        end
      end
    end
  end
  phos.scene.push{
    id = "pause", modal = true, pause_world = true, audio_pause = true,
    update = update,
    draw = function() collect("pause", UI.pause(game:has_save(Game.AUTO_SLOT))) end,
  }
end

function push_status()
  local function update()
    for _, ev in ipairs(take("status")) do
      if ev.kind == "cancelled" then phos.scene.pop() end
    end
    if phos.input.pressed("tab") or phos.input.pressed("b") then phos.scene.pop() end
  end
  phos.scene.push{
    id = "status", modal = true, pause_world = true, audio_pause = true,
    update = update, draw = function() collect("status", UI.status(game, story)) end,
  }
end

function push_map()
  local function update()
    for _, ev in ipairs(take("map")) do if ev.kind == "cancelled" then phos.scene.pop() end end
    if phos.input.pressed("m") or phos.input.pressed("b") then phos.scene.pop() end
  end
  phos.scene.push{
    id = "map", modal = true, pause_world = true, audio_pause = true,
    update = update, draw = function() collect("map", UI.map(game)) end,
  }
end

function push_history()
  local _, max_offset = UI.history_metrics(story)
  history_scroll = 0  -- 默认显示最新一行在底部
  local closed = false
  local armed = false   -- 打开历史的那次 B 必须先松开
  local opened_at = phos.sys.time()
  local function close()
    if closed then return end
    closed = true
    phos.scene.pop()
  end
  local function update()
    if not armed and not phos.input.down("b") then armed = true end
    local settled = phos.sys.time() - opened_at > 0.2   -- 覆盖打开时那次按键的边沿/松开
    for _, ev in ipairs(take("history")) do
      if ev.kind == "cancelled" and armed and settled then close() end
    end
    if phos.input.pressed("up") then history_scroll = math.min(max_offset, history_scroll + 1) end
    if phos.input.pressed("down") then history_scroll = math.max(0, history_scroll - 1) end
    if (armed and settled and phos.input.pressed("b")) or phos.input.pressed("start") then close() end
  end
  phos.scene.push{
    id = "history", modal = true, pause_world = true, audio_pause = true,
    update = update, draw = function() collect("history", UI.history(story, history_scroll)) end,
  }
end

function push_save()
  local function update()
    for _, ev in ipairs(take("save")) do
      if ev.kind == "cancelled" then phos.scene.pop()
      elseif ev.kind == "changed" and ev.confirm then
        local slot = tonumber(tostring(ev.id):match("^save/(%d+)$") or "")
        if slot then
          if game:save(slot, story) then phos.ui.toast(T().saved) else phos.ui.toast(T().save_fail) end
          phos.scene.pop()
        end
      end
    end
    if phos.input.pressed("b") then phos.scene.pop() end
  end
  phos.scene.push{
    id = "save", modal = true, pause_world = true, audio_pause = true,
    update = update, draw = function() collect("save", UI.slots(game, false)) end,
  }
end

function push_load()
  local function update()
    for _, ev in ipairs(take("load")) do
      if ev.kind == "cancelled" then phos.scene.pop()
      elseif ev.kind == "changed" and ev.confirm then
        local slot = tonumber(tostring(ev.id):match("^load/(%d+)$") or "")
        if slot and load_slot(slot) then phos.scene.clear() end
      end
    end
    if phos.input.pressed("b") then phos.scene.pop() end
  end
  phos.scene.push{
    id = "load", modal = true, pause_world = true, audio_pause = true,
    update = update, draw = function() collect("load", UI.slots(game, true)) end,
  }
end

function push_settings()
  local speeds = { "slow", "normal", "fast", "instant" }
  local function update()
    for _, ev in ipairs(take("settings")) do
      if ev.kind == "cancelled" then phos.scene.pop()
      elseif ev.kind == "changed" and ev.confirm then
        local id = tostring(ev.id)
        local speed = id:match("^settings/(%a+)$")
        if speed then
          game.settings.speed = speed
          story.settings.speed = speed
          game:save_settings()
          phos.ui.toast(phos.lang.pick({ zh = "文字速度：" .. speed, en = "TEXT SPEED: " .. speed }))
        elseif id == "settings/clear" then
          game.state.seen = {}
          phos.ui.toast(T().clear_seen)
        end
      end
    end
    if phos.input.pressed("b") then phos.scene.pop() end
  end
  phos.scene.push{
    id = "settings", modal = true, pause_world = true, audio_pause = true,
    update = update, draw = function() collect("settings", UI.settings(game)) end,
  }
end

-- 小游戏场景：电力/信号；结果结算后弹栈并进入 on_success/on_fail
function push_minigame(kind, encounter)
  mg_kind = kind
  minigame = (kind == "power") and Systems.new_power(encounter) or Systems.new_signal(encounter, game.state)
  local function update(dt)
    if not minigame then phos.scene.pop(); return end
    if minigame.result then
      local ok, effects = Systems.minigame_result(minigame)
      game:apply_effects(effects)
      story:finish_minigame(ok)
      mg_launched = nil
      minigame = nil
      input_guard = 3
      phos.scene.pop()
      screen = story:current_scene() and "dialogue" or "explore"
      return
    end
    if kind == "power" then
      if phos.input.pressed("up") then minigame:select(-1) end
      if phos.input.pressed("down") then minigame:select(1) end
      if phos.input.pressed("left") then minigame:adjust(-1) end
      if phos.input.pressed("right") then minigame:adjust(1) end
      if phos.input.pressed("b") then minigame.result = "fail"; minigame.message = "abort" end
    else
      if phos.input.pressed("up") or phos.input.pressed("down") then minigame:select(1) end
      if phos.input.pressed("left") then minigame:adjust(nil, -1) end
      if phos.input.pressed("right") then minigame:adjust(nil, 1) end
      if phos.input.pressed("a") then minigame:try_lock(); phos.audio.beep(880, 0.04) end
      if phos.input.pressed("b") then minigame.result = "fail"; minigame.message = "abort" end
    end
    minigame:update(dt)
  end
  phos.scene.push{
    id = kind == "power" and "mg_power" or "mg_signal",
    modal = true, pause_world = true, audio_pause = false,
    update = update,
    draw = function()
      if minigame then
        if kind == "power" then UI.power_mg(minigame) else UI.signal_mg(minigame) end
      end
    end,
  }
end

-- ── 探索 ────────────────────────────────────────────────────────────
local function explore_items()
  local items = {}
  if story:queued() then
    local title = story:chapter_title()
    items[#items + 1] = { label = T().continue .. "：" .. pick(title), kind = "continue", enabled = true }
  end
  for _, entry in ipairs(game:actions(story)) do
    items[#items + 1] = { label = pick(entry.label), kind = "action", action = entry.action,
                          enabled = entry.enabled, reason = entry.reason }
  end
  for _, exit in ipairs(game:exits()) do
    local reason = exit.reason and ({
      locked = phos.lang.pick({ zh = "舱门锁着", en = "Locked" }),
      hull = phos.lang.pick({ zh = "结构不足（需 50）", en = "Hull too low (need 50)" }),
      no_route = "",
    })[exit.reason] or ""
    items[#items + 1] = {
      label = string.format("%s %s（O₂ -%d / %d min）",
        phos.lang.pick({ zh = "前往", en = "GO TO" }), pick(exit.room.name), exit.o2, exit.min),
      kind = "travel", id = exit.id, enabled = exit.enabled, reason = reason,
    }
  end
  return items
end

local function do_travel(id)
  local ok, msg, notes = game:travel(id)
  if not ok then
    phos.ui.toast(msg or T().no_action)
    phos.audio.beep(140, 0.12, { wave = "square", volume = 0.15 })
    return
  end
  local room = Map.ROOMS[id]
  phos.ui.toast(string.format(T().moved, pick(room.name), 0))
  phos.audio.beep(320, 0.03, { wave = "square", volume = 0.12 })
  for _, note in ipairs(notes or {}) do
    if note.kind == "low_oxygen_san" or note.kind == "blackout_hull" then
      phos.ui.toast(phos.lang.pick({ zh = "周期结算：站体状态恶化", en = "Cycle check: station worsening" }))
    end
  end
  game:update(0)
  if game:failure() then failure_id = game:failure(); mode = "failure" end
  if game:ending() then ending_id = game:ending(); mode = "ending" end
end

local function do_action(action)
  local ok, msg, directive = game:perform_action(action)
  if not ok then
    phos.ui.toast(msg or T().no_action)
    phos.audio.beep(140, 0.1)
    return
  end
  phos.audio.beep(520, 0.04)
  if directive and directive.story then
    if story:has_scene(directive.story) then
      story:enter(directive.story, {})
      screen = "dialogue"
      return
    end
  end
  if directive and directive.minigame then
    checkpoint()
    push_minigame(directive.minigame, directive.encounter)
  elseif directive and directive.failure then
    failure_id = directive.failure
    mode = "failure"
  elseif directive and directive.ending then
    ending_id = directive.ending
    mode = "ending"
  end
end

-- ── 主循环 ──────────────────────────────────────────────────────────
function init()
  cart = phos.cart.info()
  init_pending()
  game = Game.new()
  game:load_settings()
  story = make_story()
  story.settings.speed = game.settings.speed
  game.story = story
  chapter_shown = 0
  ending_played = false
  register_observe()
  register_debug()
end

function register_observe()
  phos.observe{
    mode = function() return mode end,
    ui_screen = function()
      if phos.scene.depth() > 0 then return phos.scene.top() or "overlay" end
      if mode == "title" or mode == "ending" or mode == "failure" then return mode end
      return screen
    end,
    chapter = function() return game.state.chapter end,
    scene = function() return story:current_scene() or "" end,
    text = function() return story:current_scene() and story:full_text() or "" end,
    speaker = function() return story:current_scene() and story:speaker_id() or "" end,
    idle = function() return story:current_scene() == nil end,
    queued = function() return story:queued() or "" end,
    history_len = function() return #story.history end,
    line = function() return story.line_i or 0 end,
    room = function() return game.state.room end,
    time_left = function() return math.max(0, Systems.TIME_TOTAL - (game.state.time or 0)) end,
    time = function() return game.state.time or 0 end,
    t_minus = function() return Systems.clock(math.max(0, Systems.TIME_TOTAL - (game.state.time or 0))) end,
    res = function() return game.state.res end,
    oxygen = function() return game.state.res.o2 end,
    power = function() return game.state.res.pwr end,
    structure = function() return game.state.res.str end,
    sanity = function() return game.state.res.san end,
    flags = function() return game.state.flags end,
    counters = function() return game.state.counters end,
    objective = function() return game.state.objective end,
    endings_available = function() return game:available_endings() end,
    ending = function() return ending_id or game:ending() or "" end,
    failure = function() return failure_id or game:failure() or "" end,
    mg = function()
      return { active = minigame ~= nil, id = minigame and minigame.id or mg_kind or "",
               phase = minigame and minigame.phase or 0,
               result = minigame and (minigame.result or "") or "" }
    end,
    typing = function() return story:current_scene() ~= nil and not story:typing_done() end,
    choices = function()
      if not story:has_choices() then return {} end
      local out = {}
      for _, ch in ipairs(story.choices) do out[#out + 1] = ch.text end
      return out
    end,
    auto = function() return story.auto end,
    ff = function() return story.ff end,
    paused = function() return phos.scene.depth() > 0 end,
    exits = function()
      local out = {}
      for _, exit in ipairs(game:exits()) do if exit.enabled then out[#out + 1] = exit.id end end
      return out
    end,
    has_save = function() return game:has_save(Game.AUTO_SLOT) end,
    endings_seen = function() return game:endings_seen() end,
    save_available = function() return phos.save.available() end,
  }
end

-- QA 调试钩子：把资源/时间推到边界（GDD 12 的数值自检也靠它）
local function jump_chapter(n)
  local ch = story.chapters[n]
  if not ch or not ch.start then
    phos.ui.toast(phos.lang.pick({ zh = "该章剧情尚未装载", en = "Chapter not loaded" }))
    return false
  end
  for _, id in ipairs(Map.ORDER) do game.map:unlock(id) end
  game.state.chapter = n
  story.chapter = n
  story.auto, story.ff = false, false
  story.scene, story.scene_id, story.queued_next = nil, nil, nil
  story:enter(ch.start, { skip_enter = true })
  mode = "play"
  screen = story:current_scene() and "dialogue" or "explore"
  chapter_shown = n
  checkpoint()
  return true
end

local function force_ending(k)
  local id = "E" .. tostring(k)
  if k < 1 or k > 4 then return end
  game:set_ending(id)
  ending_id = id
  ending_played = true
  story.auto, story.ff = false, false
  mode = "ending"
  phos.ui.reset()
end

function register_debug()
  local specs = {
    { key = "o2", label = { zh = "氧气", en = "Oxygen" }, min = 0, max = 100, step = 1 },
    { key = "pwr", label = { zh = "电力", en = "Power" }, min = 0, max = 100, step = 1 },
    { key = "str", label = { zh = "结构", en = "Hull" }, min = 0, max = 100, step = 1 },
    { key = "san", label = { zh = "理智", en = "Sanity" }, min = 0, max = 100, step = 1 },
  }
  for _, spec in ipairs(specs) do
    phos.debug.integer(spec.label,
      function() return math.floor(game.state.res[spec.key] or 0) end,
      function(v) Systems.set_res(game.state, spec.key, v) end,
      { min = spec.min, max = spec.max, step = spec.step, group = { zh = "调试", en = "DEBUG" } })
  end
  phos.debug.integer({ zh = "站内时间(分)", en = "Station time (min)" },
    function() return math.floor(game.state.time or 0) end,
    function(v) game.state.time = math.max(0, math.min(Systems.TIME_TOTAL, v)) end,
    { min = 0, max = Systems.TIME_TOTAL, step = 30, group = { zh = "调试", en = "DEBUG" } })
  phos.debug.integer({ zh = "章节(调试)", en = "Chapter (debug)" },
    function() return game.state.chapter end,
    function(v) game.state.chapter = math.max(1, math.min(8, v)); story.chapter = game.state.chapter end,
    { min = 1, max = 8, step = 1, group = { zh = "调试", en = "DEBUG" } })
  phos.debug.toggle({ zh = "跳到章节起点(调试)", en = "Jump to chapter start" },
    function() return false end,
    function(v) if v then jump_chapter(game.state.chapter) end end,
    { group = { zh = "调试", en = "DEBUG" } })
  phos.debug.toggle({ zh = "解锁全部房间(调试)", en = "Unlock all rooms" },
    function() return false end,
    function(v) if v then for _, id in ipairs(Map.ORDER) do game.map:unlock(id) end end end,
    { group = { zh = "调试", en = "DEBUG" } })
  phos.debug.integer({ zh = "强制结局(0-4, 调试)", en = "Force ending (0-4)" },
    function() return 0 end,
    function(v) if v and v >= 1 and v <= 4 then force_ending(v) end end,
    { min = 0, max = 4, step = 1, group = { zh = "调试", en = "DEBUG" } })
end

local function handle_explore_input()
  for _, ev in ipairs(take("explore")) do
    if ev.kind == "activated" then
      local items = explore_items()
      local item = items[ev.index]
      if item and item.enabled then
        if item.kind == "continue" then
          story:advance()  -- 进入 queued next
          screen = story:current_scene() and "dialogue" or "explore"
        elseif item.kind == "action" then
          do_action(item.action)
        elseif item.kind == "travel" then
          do_travel(item.id)
        end
      elseif item and not item.enabled then
        phos.ui.toast(item.reason ~= "" and item.reason or T().no_action)
      end
    end
  end
  if phos.input.pressed("m") then push_map() end
  if phos.input.pressed("tab") then push_status() end
  if phos.input.pressed("start") then push_pause() end
end

local function handle_dialogue_input()
  local had_choices = story:has_choices()
  if had_choices and not choice_guard_used then
    choice_guard = 12
    choice_guard_used = true
  elseif not had_choices then
    choice_guard_used = false
    choice_guard = 0
  end
  for _, ev in ipairs(take("dialogue")) do
    if ev.kind == "activated" and ev.id == "dialogue/choices" then
      -- guard 期内不执行：玩家必须再按一次 A，避免“最后一句的 A”直接选掉刚出现的选项
      if choice_guard == 0 then
        story:select(ev.index)
        screen = story:current_scene() and "dialogue" or "explore"
      end
    elseif ev.kind == "cancelled" then
      -- B 的打开/关闭由下面显式的 pressed("b") 单一路径处理；
      -- 不再从 cancelled 再 push 一次，否则同一次按键会开出两层历史
    end
  end
  if choice_guard > 0 then choice_guard = choice_guard - 1 end
  if story:has_choices() then
    -- 选项由 render 的 list 消费方向键与 A；这里不抢
  else
    if phos.input.pressed("a") or phos.input.pressed("space") then
      story:advance()
      if not story:current_scene() then screen = "explore" end
    end
  end
  if phos.input.pressed("b") then push_history() end
  if phos.input.pressed("x") then
    phos.ui.toast(story:toggle_auto() and T().auto_on or T().auto_off)
  end
  if phos.input.pressed("y") then
    phos.ui.toast(story:toggle_ff() and T().ff_on or T().ff_off)
  end
  if phos.input.pressed("tab") then push_status() end
  if phos.input.pressed("m") then push_map() end
  if phos.input.pressed("start") then push_pause() end
end

-- 失败：优先播放失败结算场景（f_suffocate / f_hull），播完才进失败屏
local function failure_scene_id(id)
  local mapped = (id == "F1") and "f_suffocate" or ((id == "F2") and "f_hull" or nil)
  for _, meta in ipairs(story.failures_meta or {}) do
    if meta.id == id and meta.scene then return meta.scene end
  end
  if mapped and story:has_scene(mapped) then return mapped end
  return nil
end

local function enter_failure(id)
  failure_id = id
  failure_scene_played = false
  local scene_id = failure_scene_id(id)
  if scene_id and not story:has_scene("__noop") then
    story.auto, story.ff = false, false
    story.scene, story.scene_id, story.queued_next = nil, nil, nil
    story:enter(scene_id, { skip_enter = true })
    failure_scene_played = true
    screen = story:current_scene() and "dialogue" or "explore"
    return true
  end
  mode = "failure"
  return false
end

local function after_story()
  local mini = story:peek_minigame()
  if mini and mg_launched ~= mini then
    mg_launched = mini
    checkpoint()
    push_minigame(mini.kind == "signal" and "signal" or "power", mini.encounter)
    return true
  end
  if game:ending() then
    ending_id = game:ending()
    if not ending_played and story:has_scene("e_signal") and ending_id == "E4" then
      ending_played = true
      story:enter("e_signal", { skip_enter = true })
      screen = "dialogue"
      return true
    end
    mode = "ending"
    return true
  end
  if game:failure() then
    -- 已经在播失败结算场景时不要每帧重新 enter（会把 line 重置成 1，A 永远推不动）
    if not failure_scene_played then return enter_failure(game:failure()) end
    return false
  end
  if failure_scene_played and not story:current_scene() then
    failure_scene_played = false
    mode = "failure"
    return true
  end
  return false
end

function update(dt)
  ui_screen = (phos.scene.depth() > 0) and (phos.scene.top() or "overlay") or ui_screen
  -- 浮窗/场景栈打开时只跑场景自己的 update；卡带世界 update 不能再消费同一按键
  -- （否则 B 关闭历史后又被这里重新 push，看起来像“B 无效”）
  if phos.scene.depth() > 0 then return end
  if mode == "title" then
    ui_screen = "title"
    if title_grace > 0 then title_grace = title_grace - 1; take("title") ; return end
    for _, ev in ipairs(take("title")) do
      if ev.kind == "changed" and ev.confirm then
        if ev.id == "title/new" then start_new_run()
        elseif ev.id == "title/load" then push_load()
        elseif ev.id == "title/settings" then push_settings()
        elseif ev.id == "title/about" then phos.ui.toast(phos.lang.pick({
            zh = "在黑洞边缘，听见里面。", en = "At the edge of a black hole, listening inward." }), 3) end
      end
    end
    return
  end
  -- 浮窗打开时（pause_world）本函数不会被调用；此处 mode 只会是 play/ending/failure
  if mode == "ending" then
    ui_screen = "ending"
    if phos.input.pressed("a") or phos.input.pressed("start") then
      mode = "title"
      title_grace = 2
      story.auto, story.ff = false, false
    end
    return
  end
  if mode == "failure" then
    ui_screen = "failure"
    if phos.input.pressed("a") then
      if load_slot(Game.AUTO_SLOT) then failure_id = nil end
    elseif phos.input.pressed("b") then
      mode = "title"; title_grace = 2
    end
    return
  end
  -- play
  if screen == "dialogue" and not story:current_scene() then
    screen = story:queued() and "explore" or "explore"
  end
  if story:current_scene() == nil then screen = "explore" end
  ui_screen = screen
  if input_guard > 0 then
    input_guard = input_guard - 1
    take("explore")
    take("dialogue")
  elseif screen == "explore" then
    handle_explore_input()
  else
    handle_dialogue_input()
  end
  story:update(dt)
  local scene = story.scene
  if scene and story:typing_done() and story.page >= #story.pages
     and story.line_i >= #(scene.lines or {}) and not story:has_choices() then
    -- 最后一行显示完 → 选项自动出现（不必多按一次 A）
    local list = story:_available_choices()
    if list and #list > 0 then story.choices = list end
  end
  if story:current_scene() == nil then screen = "explore" end
  after_story()
  for _, note in ipairs(game:update(dt)) do
    if note.kind == "time_up" then
      phos.ui.toast(T().time_up)
      if (game.state.chapter or 1) < Systems.FINAL_CHAPTER then
        game.state.chapter = Systems.FINAL_CHAPTER
        story.chapter = Systems.FINAL_CHAPTER
        if story:has_scene("c8_s01") then
          story.scene, story.scene_id, story.queued_next = nil, nil, nil
          story:enter("c8_s01", { skip_enter = true })
          screen = "dialogue"
        end
        checkpoint()
      end
    end
  end
  -- 失败/结局由 after_story 统一处分（先播结算场景，再切屏）
  if game:failure() and not failure_scene_played and not story:current_scene() then
    enter_failure(game:failure())
  end
end

function draw()
  if mode == "title" then
    collect("title", UI.title(cart, game:has_save(Game.AUTO_SLOT) or game:has_save(1)))
    return
  end
  if mode == "ending" then
    local meta = nil
    for _, e in ipairs(story.endings_meta or {}) do if e.id == ending_id then meta = e end end
    for _, e in ipairs(story.failures_meta or {}) do if e.id == ending_id then meta = e end end
    local title = meta and meta.title or (game.state.route ~= "" and game.state.route or "END")
    local blurb = meta and (meta.blurb or meta.desc) or nil
    UI.ending(game, ending_id, title, blurb and phos.lang.pick(blurb) or "")
    return
  end
  if mode == "failure" then
    UI.failure(game, failure_id)
    return
  end
  UI.hud(game, story)
  UI.room_art(game, story)
  if screen == "dialogue" then
    collect("dialogue", UI.dialogue(game, story))
  else
    collect("explore", UI.explore(game, {
      items = explore_items(), room_name = pick((Map.ROOMS[game.state.room] or {}).name or ""),
      objective = game.state.objective and pick(game.state.objective) or "",
    }))
  end
end

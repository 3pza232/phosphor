-- 场景栈样板：按 start 压入暂停场景；世界冻结、音频暂停；RESUME 出栈恢复。
--
-- 分工：
--   * 场景的 update：消费上一帧界面产生的事件（界面在 draw 里声明并拿到事件）；
--   * 场景的 draw：用 phos.ui.render 画浮窗（input=true，按键归这一层）；
--   * 场景声明 pause_world：引擎跳过本卡带的 update，世界因此冻结；
--   * 场景声明 audio_pause：引擎在压栈期间暂停音频，出栈恢复。
local ticks = 0
local pending = {}
local entered, exited = 0, 0
local KEY = function(n) return phos.input.key_name(n) end

local function pause_update(dt)
  for _, e in ipairs(pending) do
    if e.kind == "activated" and e.id == "menu" then
      if e.index == 1 then phos.scene.pop() end       -- RESUME
      phos.audio.beep(880, 0.05)
    elseif e.kind == "cancelled" then
      phos.scene.pop()                                 -- B：同样回到世界
    end
  end
  pending = {}
end

local function pause_draw()
  local events = phos.ui.render{
    screen = "pause",
    rect = { x = 20, y = 15, w = 40, h = 10 },
    kind = "box", title = "PAUSED", border = "single", opaque = true, bg = "black",
    children = {
      { kind = "stat", text = "SCENE", value = "pause" },
      { kind = "list", id = "menu", items = { "RESUME", "QUIT" }, indent = 2, text_gap = 2 },
      { kind = "hint", items = { KEY("a"), "ok", KEY("b"), "back" } },
    },
  }
  for i = 1, #events do pending[#pending + 1] = events[i] end
end

function init() end

function update(dt)
  ticks = ticks + 1
  if phos.input.pressed("start") and phos.scene.depth() == 0 then
    phos.scene.push{
      id = "pause",
      modal = true,
      pause_world = true,
      audio_pause = true,
      update = pause_update,
      draw = pause_draw,
      on_enter = function() entered = entered + 1 end,
      on_exit = function() exited = exited + 1 end,
    }
  end
end

function draw()
  local S, C = phos.screen, phos.color
  S.clear()
  S.print(1, 1, "SCENE DEMO", C.yellow)
  S.print(1, 3, "ticks=" .. ticks .. "  depth=" .. phos.scene.depth(), C.gray)
  S.print(1, 5, "press " .. KEY("start") .. " to push the pause scene", C.white)
  S.print(1, 7, "while paused: world frozen, audio paused", C.dark_gray)
end

function debug_state()
  return {
    ticks = ticks,
    depth = phos.scene.depth(),
    top = phos.scene.top() or "",
    pause_world = phos.scene.pause_world(),
    modal = phos.scene.modal(),
    audio_pause = phos.scene.audio_pause(),
    entered = entered,
    exited = exited,
  }
end

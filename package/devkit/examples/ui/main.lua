-- 界面样板：phos.ui.render 的完整用法（组件 / 布局 / 主题 / 焦点 / 事件）
--
-- 要点：
--   * 界面在 draw() 里声明，引擎负责布局、焦点、滚动、勾选与文本输入；
--   * 事件只在本帧有效：这里在下一帧的 update 里消费（存进 pending）；
--   * 同一帧只让"负责输入"的那次 render 处理按键（侧栏那次 input = false）；
--   * 颜色写色板名（"green"）或 {r,g,b}；其余样式都走元素字段（见 docs/api-reference.md）。

local Text = {
  zh = { title = "界面样板", score = "得分", pick = "选一个", sound = "音效",
         name = "昵称", hp = "耐久", keys = "操作", last = "事件" },
  en = { title = "UI KIT", score = "SCORE", pick = "PICK", sound = "SOUND",
         name = "NAME", hp = "HP", keys = "KEYS", last = "EVENT" },
}

local state = {
  score = 0,
  checked = false,
  name = "",
  last = "-",
  pending = {},
}

local function t() return phos.lang.dict(Text) end

local function key(name) return phos.input.key_name(name) end

function init()
  phos.audio.music({
    bpm = 128,
    loop = true,
    patterns = {
      A = { lead = "C4 - E4 - G4 - E4 -", bass = "C2 - - - G1 - - -" },
    },
    order = { "A" },
  })
end

function update()
  -- 事件在产生的那一帧画完就丢弃，所以下一帧第一件事就是消费
  for _, ev in ipairs(state.pending) do
    state.pending = {}
    if ev.kind == "activated" and ev.id == "demo_list" then
      if ev.index == 1 then state.score = state.score + 100 end
      if ev.index == 2 then state.score = state.score + 10 end
      state.last = ("list:%d"):format(ev.index)
      phos.audio.beep(660, 0.05)
    elseif ev.kind == "changed" and ev.id == "demo_sfx" then
      state.checked = ev.checked
      state.last = "sound:" .. tostring(ev.checked)
      phos.audio.beep(ev.checked and 880 or 440, 0.06)
    elseif ev.kind == "submitted" and ev.id == "demo_name" then
      state.last = "name:" .. ev.text
    elseif ev.kind == "cancelled" then
      state.last = "cancel"
    end
  end
end

function draw()
  local S, C = phos.screen, phos.color
  local L = t()
  S.clear()
  -- 世界的画法不变：这里只放一块"游戏画面"底色，界面叠在它之上
  S.fill(0, 0, 61, 45, " ", C.black, C.rgb(8, 14, 10))

  local events = phos.ui.render{
    screen = "kit",
    surface = "content",
    rect = { x = 2, y = 2, w = 56, h = 24 },
    kind = "box",
    title = L.title,
    border = "single",
    padding = { x = 1, y = 0 },
    opaque = true,
    bg = "black",
    gap = 0,
    children = {
      { kind = "text", text = L.pick, dim = true },
      { kind = "list", id = "demo_list", items = { "ALPHA", "BETA", "GAMMA" },
        indent = 2, text_gap = 2 },
      { kind = "divider", fg = "dark_gray" },
      { kind = "stat", text = L.score, value = tostring(state.score), accent = true },
      { kind = "table", columns = { "RANK", "NAME", "SCORE" }, widths = { 4, 8, 6 },
        col_align = { "left", "left", "right" },
        rows = { { "1", "ALPHA", "1200" }, { "2", "BETA", "900" }, { "3", "GAMMA", "10" } } },
      { kind = "checkbox", id = "demo_sfx", text = L.sound, checked = state.checked },
      { kind = "field", id = "demo_name", text = L.name, width = 24, max_chars = 12 },
      { kind = "bar", id = "demo_hp", ratio = 0.4 + state.score / 500, width = 30 },
      { kind = "spacer", height = 1 },
      { kind = "text", text = L.last .. ": " .. state.last, dim = true },
      { kind = "hint", items = {
          key("down"), "move", key("tab"), "next", key("a"), "pick", key("start"), "act",
        } },
    },
  }
  for i = 1, #events do state.pending[#state.pending + 1] = events[i] end

  -- 侧栏：同一套组件、同样的主题，只是不消费输入（同一帧只让上面那次处理按键）
  phos.ui.render{
    screen = "kit_panel",
    surface = "panel",
    input = false,
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 1,
    children = {
      { kind = "text", text = "STATUS", accent = true },
      { kind = "stat", text = L.score, value = tostring(state.score) },
      { kind = "stat", text = L.last, value = state.last, label_w = 6 },
      { kind = "divider", fg = "dark_gray" },
      { kind = "text", text = L.keys, dim = true },
      { kind = "text", text = key("up") .. "/" .. key("down") .. " " .. L.pick },
      { kind = "text", text = key("tab") .. " focus" },
      { kind = "text", text = key("a") .. " confirm" },
    },
  }
end

function debug_state()
  return {
    focus = phos.ui.focus(),
    score = state.score,
    checked = phos.ui.checked("demo_sfx", "kit"),
    name = phos.ui.field_text("demo_name", "kit"),
    last = state.last,
  }
end
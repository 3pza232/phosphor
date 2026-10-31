-- 界面样板：phos.ui.render 的完整用法（组件 / 布局 / 主题 / 焦点 / 事件）
--
-- 要点：
--   * 界面在 draw() 里声明，引擎负责布局、焦点、滚动、勾选与文本输入；
--   * 事件只在本帧有效：这里在下一帧的 update 里消费（存进 pending）；
--   * 同一帧只让"负责输入"的那次 render 处理按键（侧栏那次 input = false）；
--   * 颜色写色板名（"green"）或 {r,g,b}；其余样式都走元素字段（见 docs/api-reference.md）；
--   * table / grid 卡片墙 / scroll / scroll_x / option / margin 的第二块"数据视图"在下方，
--     align 在侧栏演示，细节见各块注释。

local Text = {
  zh = { title = "界面样板", score = "得分", pick = "选一个", sound = "音效",
         name = "昵称", hp = "耐久", keys = "操作", last = "事件",
         quality = "画质", data = "数据视图",
         grid_cap = "网格 3 列 · 纵向滚动 · 横向滚动" },
  en = { title = "UI KIT", score = "SCORE", pick = "PICK", sound = "SOUND",
         name = "NAME", hp = "HP", keys = "KEYS", last = "EVENT",
         quality = "QUALITY", data = "DATA VIEWS",
         grid_cap = "GRID 3 COLS · SCROLL · SCROLL_X" },
}

local state = {
  score = 0,
  checked = false,
  name = "",
  quality = 2,  -- QUALITY 下标；option 的左右键改这个值，文本由卡带格式化
  last = "-",
  pending = {},
}

-- option 只显示 text、不解释取值：名字/格式化都归卡带（引擎保持通用）
local QUALITY = { "LOW", "MID", "HIGH" }

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
      phos.ui.toast("PICK " .. ev.index)  -- 底部瞬时提示：自动消失，不接管输入
      phos.audio.beep(660, 0.05)
    elseif ev.kind == "changed" and ev.id == "demo_sfx" then
      state.checked = ev.checked
      state.last = "sound:" .. tostring(ev.checked)
      phos.audio.beep(ev.checked and 880 or 440, 0.06)
    elseif ev.kind == "submitted" and ev.id == "demo_name" then
      state.last = "name:" .. ev.text
    elseif ev.kind == "changed" and ev.id == "demo_quality" then
      -- 左右是 delta，A 是 confirm+delta=1；这里都按"改一档"处理并夹在 1..#QUALITY
      local delta = ev.delta or 0
      state.quality = math.max(1, math.min(#QUALITY, state.quality + delta))
      state.last = "quality:" .. state.quality
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
      { kind = "table", columns = { "RANK", "NAME", "SCORE" }, widths = { 4, 0, 6 },  -- 固定宽 / 自适应（吃掉余量）/ 固定宽
        col_align = { "left", "left", "right" },
        rows = { { "1", "ALPHA", "1200" }, { "2", "BETA", "900" }, { "3", "GAMMA", "10" } } },
      { kind = "checkbox", id = "demo_sfx", text = L.sound, checked = state.checked },
      { kind = "field", id = "demo_name", text = L.name, width = 24, max_chars = 12 },
      -- option：引擎只显示 text（左右改值、A 确认），取值/格式化归卡带；
      -- 放在 field 之后，键盘的焦点顺序仍是 列表 → 勾选 → 文本域 → 画质
      { kind = "option", id = "demo_quality",
        text = L.quality .. ": " .. QUALITY[state.quality] },
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
      { kind = "stat", text = L.quality, value = QUALITY[state.quality], label_w = 8 },
      { kind = "divider", fg = "dark_gray" },
      { kind = "text", text = L.keys, dim = true },
      { kind = "text", text = key("up") .. "/" .. key("down") .. " " .. L.pick },
      { kind = "text", text = key("tab") .. " focus" },
      { kind = "text", text = key("a") .. " confirm" },
      -- 侧栏是 column：width=12 小于内容宽时，align_h 控制子项的水平落点
      { kind = "text", text = "ALIGN", dim = true },
      { kind = "text", text = "CENTER", width = 12, align_h = "center" },
      { kind = "text", text = "END", width = 12, align_h = "end" },
    },
  }

  -- 数据视图（input = false：只显示，不参与焦点/事件；参数注释见节点旁）
  -- 为什么另起一屏而不是塞进上面的主框：主框是"表单/操作"，这里是"只读数据展示"；
  -- 两者叠在同一区域会让焦点与视觉层级都变浑。rect 放在主框正下方（y=28），
  -- 高度 14 由内容决定：标签 1 + 卡片墙（grid 2 行 + 行距 1）+ 分隔线 1 + 纵向视口 4 + 横向视口 2 + 边框 2。
  local logs = {
    "LOG 01 boot  theme=phosphor  lang=zh",
    "LOG 02 cart  devkit/examples/ui  seed=1",
    "LOG 03 ui    screen=kit  input=true",
    "LOG 04 ui    screen=kit_panel  input=false",
    "LOG 05 grid  3 columns  gap=1  width=auto",
    "LOG 06 scroll height=4  initial offset=4",
    "LOG 07 scroll_x width=36  initial offset=10",
    "LOG 08 primitives padding/margin/bg/fg/border/align",
    "LOG 09 focus list -> checkbox -> field -> option",
    "LOG 10 tail  (the viewport starts near the end)",
  }
  local wide = {
    "COL001 alpha beta gamma delta epsilon zeta eta theta iota kappa lambda mu",
    "COL002 The quick brown fox jumps over the lazy dog 0123456789",
  }
  phos.ui.render{
    screen = "kit_data",
    surface = "content",
    input = false,
    rect = { x = 2, y = 28, w = 56, h = 14 },
    kind = "box",
    title = L.data,
    border = "single",
    padding = { x = 1, y = 0 },
    opaque = true,       -- 只读展示区铺实底，避免透出下面的世界
    bg = "dark_gray",    -- 比主框低一档的底色：层级靠明度而不是靠再加一层边框
    fg = "white",
    gap = 0,             -- 自己用分隔线分节，不需要额外行距
    children = {
      { kind = "text", text = L.grid_cap, dim = true },
      -- grid：按 cols 把可用宽度均分成等宽单元格，逐行排；子项不再各自指定 width
      -- （那是 row 的用法）。margin 只缩自己的落点，不影响父容器分配。
      { kind = "grid", cols = 3, gap = 1, margin = { l = 1 }, children = {
          { kind = "text", text = "CARD 1", accent = true },
          { kind = "text", text = "CARD 2" },
          { kind = "text", text = "CARD 3" },
          { kind = "text", text = "CARD 4" },
          { kind = "text", text = "CARD 5" },
          { kind = "text", text = "CARD 6" },
        } },
      { kind = "divider", fg = "dark_gray" },
      -- scroll：height 是视口行数，scroll 是初始纵向偏移（这里直接看日志尾部）；
      -- 之后视口会跟随焦点，但这个界面 input=false，所以偏移保持
      { kind = "scroll", height = 4, width = 52, scroll = 4, gap = 0, children = {
          { kind = "text", text = logs[1] },
          { kind = "text", text = logs[2] },
          { kind = "text", text = logs[3] },
          { kind = "text", text = logs[4] },
          { kind = "text", text = logs[5] },
          { kind = "text", text = logs[6] },
          { kind = "text", text = logs[7] },
          { kind = "text", text = logs[8] },
          { kind = "text", text = logs[9] },
          { kind = "text", text = logs[10] },
        } },
      -- scroll_x：视口宽 36 小于内容宽 64，初始偏移 10 列；overflow=clip 保持单行
      { kind = "scroll", height = 2, width = 36, scroll_x = 10, gap = 0, children = {
          { kind = "text", width = 64, overflow = "clip", text = wide[1] },
          { kind = "text", width = 64, overflow = "clip", text = wide[2] },
        } },
    },
  }
end

function debug_state()
  return {
    focus = phos.ui.focus(),
    score = state.score,
    checked = phos.ui.checked("demo_sfx", "kit"),
    name = phos.ui.field_text("demo_name", "kit"),
    quality = state.quality,
    last = state.last,
  }
end
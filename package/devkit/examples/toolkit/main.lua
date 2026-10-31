-- 卡带工具层样板：phos.score / phos.lang.shared / phos.text.score|clock|percent
--
-- 这些是"每张卡带都会写一遍"的东西，引擎收走后作者只写玩法：
--   * 排行榜：排序、截断、存档键与坏档容错都由 phos.score 负责；
--   * 共享词表：SCORE/BEST/PAUSED… 不需要每张卡带再抄两列；
--   * 格式化：千分位、mm:ss、百分比只有一份实现（与主机展示一致）。
local points = 0
local hp = 0.4567
local shared = {}
local board = nil

local function fmt()
  return {
    score = phos.text.score(points),
    clock = phos.text.clock(phos.sys.time()),
    percent = phos.text.percent(hp),
    paused = shared.paused or "PAUSED",
  }
end

local function hint()
  return {
    phos.input.key_name("a"), "add score",
    phos.input.key_name("b"), "clear board",
  }
end

function init()
  shared = phos.lang.shared()
  board = phos.score.new{ max = 5, key = "toolkit_scores" }
  -- 给 agent 的观测：字段可以是值，也可以是"查询时求值"的函数。
  -- 引擎在 state.query 时调用，于是观测永远与真实状态一致（不必维护快照）
  phos.observe{
    points = function() return points end,
    best = function() return board:best() end,
    list = function() return board:list() end,
    available = function() return board:available() end,
    formatted = function() return fmt() end,
    shared_score = function() return shared.score or "" end,
  }
end

function update(dt)
  if phos.input.pressed("a") then
    points = points + 1000
    local rank = board:add(points)
    phos.sys.log("score added: rank=" .. tostring(rank))
    phos.audio.beep(760, 0.05)
  elseif phos.input.pressed("b") then
    board:clear()
    points = 0
  end
end

function draw()
  local S, C = phos.screen, phos.color
  local t = fmt()
  S.clear()
  S.print(1, 1, "TOOLKIT DEMO", C.yellow)
  S.print(1, 3, (shared.score or "SCORE") .. ": " .. t.score, C.white)
  S.print(1, 4, (shared.best or "BEST") .. ": " .. tostring(board:best()), C.green)
  S.print(1, 5, "CLOCK: " .. t.clock .. "   HP: " .. t.percent, C.gray)

  -- 侧栏也是同一套组件（引擎负责布局/焦点/主题）
  phos.ui.render{
    screen = "toolkit_panel",
    surface = "panel",
    input = false,
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 1,
    children = {
      { kind = "text", text = shared.best or "BEST", accent = true },
      { kind = "stat", text = "TOP", value = tostring(board:best()) },
      { kind = "divider", fg = "dark_gray" },
      { kind = "text", text = shared.score or "SCORE", dim = true },
      { kind = "text", text = phos.text.score(points) },
      { kind = "spacer", grow = 1 },
      { kind = "hint", items = hint() },
    },
  }
end

-- 观测由 phos.observe 声明（见 init）；不再需要手写 debug_state
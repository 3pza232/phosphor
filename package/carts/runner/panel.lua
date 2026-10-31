-- panel.lua —— 侧栏：分数 / 最高 / 速度 / 时段 / 图例与操作。
--
-- 用声明式组件描述：宽度变化由布局负责，不再手写局部坐标与裁剪。
local Panel = {}

local Text = {
  zh = {
    speed = "速度", phase = "时段", day = "白天", night = "夜里", mark = "里程碑",
    legend = "图例", cactus = "█  仙人掌", bird = "██ 翼龙", keys = "操作",
  },
  en = {
    speed = "SPEED", phase = "PHASE", day = "day", night = "night", mark = "MARK",
    legend = "LEGEND", cactus = "█  cactus", bird = "██ bird", keys = "KEYS",
  },
}
local function L() return phos.lang.dict(Text) end
local function KEY(name) return "[" .. phos.input.key_name(name) .. "]" end

---@param game table 规则对象（只读）
function Panel.draw(game)
  local pw = phos.panel.size()
  if pw == 0 then return end

  local words = phos.lang.shared()
  local t = L()
  local s = game:status()
  local rows = {
    { kind = "text", text = phos.cart.info().name, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = words.score, value = phos.text.score(s.score), label_w = 7 },
    { kind = "stat", text = words.best, value = phos.text.score(s.best), label_w = 7, accent = true },
    { kind = "text", text = t.speed .. "  " .. string.format("%.1f", s.speed) .. " c/s", fg = "cyan" },
    { kind = "bar", ratio = math.max(0, math.min(1, (s.speed - 10) / 14)) },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = t.phase, value = s.night and t.night or t.day, label_w = 7 },
    { kind = "stat", text = t.mark, value = tostring((math.floor(s.score / 100) + 1) * 100), label_w = 7 },
    { kind = "spacer", grow = 1 },
    { kind = "text", text = t.legend, dim = true },
    { kind = "text", text = t.cactus, fg = "green" },
    { kind = "text", text = t.bird, fg = "gray" },
    { kind = "divider", fg = "dark_gray" },
    { kind = "text", text = t.keys, dim = true },
    { kind = "text", text = KEY("up") .. " / " .. KEY("a") .. " jump" },
    { kind = "text", text = "   hold = higher", dim = true },
    { kind = "text", text = KEY("down") .. " duck / fast drop" },
  }

  phos.ui.render{
    screen = "panel",
    surface = "panel",
    input = false,
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 0,
    children = rows,
  }
end

return Panel
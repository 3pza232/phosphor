-- panel.lua —— 右侧栏。只在 manifest.lua 声明了 sidebar 时才会被调用。
--
-- 用声明式组件描述界面：坐标、光标、裁剪、键位提示的排布都由引擎负责。
-- 坐标是**面板局部**的（surface = "panel"）；面板宽度运行时可变（phos.panel.resize），
-- 所以不要缓存宽度——每次 draw 重新声明即可。

local Panel = {}

-- 侧栏自己的文案（与 main.lua 的文案表互不依赖）
local Text = {
  zh = { score = "得分", keys = "操作", act = "动作" },
  en = { score = "SCORE", keys = "KEYS", act = "ACT" },
}

---@param game table  main.lua 传进来的规则对象
---@param cart table  卡带身份（phos.cart.info()）
function Panel.draw(game, cart)
  local pw = phos.panel.size()
  if pw == 0 then return end
  local t = phos.lang.dict(Text)

  local events = phos.ui.render{
    screen = "panel",
    surface = "panel",
    input = false,             -- 侧栏只显示：输入由主画面那一屏处理
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 1,
    children = {
      { kind = "text", text = phos.text.fit(cart.name, pw - 2), accent = true },
      { kind = "divider", fg = "dark_gray" },
      { kind = "stat", text = t.score, value = tostring(game.score), label_w = 8 },
      { kind = "spacer", grow = 1 },
      { kind = "text", text = t.keys, dim = true },
      { kind = "hint", items = { phos.input.key_name("a"), t.act } },
    },
  }
  return events                -- 侧栏没有可交互控件，通常为空表
end

return Panel

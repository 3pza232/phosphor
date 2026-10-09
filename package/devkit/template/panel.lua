-- panel.lua —— 右侧栏。只在 manifest.lua 声明了 sidebar 时才会被调用。
--
-- 两条容易踩的线：
--   * 坐标是**面板局部**的（面板左上角为 (0,0)），宽度用 phos.panel.size() 问；
--     屏幕那一套 80x45 在这里不适用
--   * 面板**定宽**：任何可能超长的文案都过一遍 phos.text.fit(text, pw - 2)。
--     主机在右边是硬切，会留下"[↑/A] 跳：按住更"这种半句话，玩家只能靠猜

local Panel = {}

-- 侧栏自己的文案（与 main.lua 的文案表互不依赖，改这里不会牵动画面）
local Text = {
  zh = { score = "得分", keys = "操作", act = "动作" },
  en = { score = "SCORE", keys = "KEYS", act = "ACT" },
}
local function L() return Text[phos.sys.language()] or Text.zh end

---@param game table  main.lua 传进来的规则对象
---@param cart table  卡带身份（phos.cart.info()）
function Panel.draw(game, cart)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end        -- 没声明侧栏（或被 mod 关掉）：什么都不画

  local t = L()
  P.clear()

  P.print(1, 1, phos.text.fit(cart.name, pw - 2), C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  -- 「填」要显示什么就写这里。分区 / 小地图用：
  --   local box = phos.ui.region(1, 4, pw - 2, 8, { surface = "panel" })
  --   box.print(0, 0, ...)          -- 区域坐标相对区域左上角，越界不画
  P.print(1, 4, t.score, C.gray)
  P.print(1, 5, tostring(game.score), C.white)

  -- 键位提示放最底部，与出厂卡带的位置保持一致
  P.print(1, ph - 2, t.keys, C.gray)
  P.print(1, ph - 1,
          phos.text.fit("[" .. phos.input.key_name("a") .. "] " .. t.act, pw - 2), C.white)
end

return Panel

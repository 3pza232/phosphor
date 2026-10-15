-- hud.lua —— 可玩区上的读数与浮窗辅助（DESIGN §2.1 / §10 / §11）。
--
-- 顶栏、消息日志、键位提示，以及浮窗的不透明底板（`plate`）。
-- 只读状态、只作画。日志文字随 tone 取色板色；顶栏这类"读数"显式给 black 底，
-- 保证压在什么地形上都读得清（世界内的东西一律不写底，见 §12.1）。

local Hud = {}

local Text = {
  zh = { depth = "深度", turn = "回合", seed = "种子", light = "光照" },
  en = { depth = "DEPTH", turn = "TURN", seed = "SEED", light = "LIGHT" },
}

local function L() return phos.lang.dict(Text) end
local function tone_color(C, name) return C[name] or C.white end

-- 顶栏：卡带名 · 深度 · 回合 · 种子 · 光照半径。显式给 black 底（读数不透底）。
function Hud.draw_top(S, C, ctx)
  local t = L()
  local px, py, pw = phos.screen.playfield()
  local world = ctx.world
  S.fill(px, py, pw, 1, " ", C.white, C.black)
  local x = px + 1
  local function seg(text, col)
    S.print(x, py, text, col, C.black)
    x = x + phos.text.width(text)
  end
  seg(ctx.cart.name or "GLOW CRAWL", C.yellow)
  seg("  ·  ", C.dark_gray)
  seg(t.depth .. " " .. tostring(world.depth), C.white)
  seg("  ·  ", C.dark_gray)
  seg(t.turn .. " " .. tostring(world.turn), C.white)
  seg("  ·  ", C.dark_gray)
  seg(t.seed .. " " .. tostring(world.seed), C.gray)
  seg("  ·  ", C.dark_gray)
  seg(t.light .. " " .. tostring(world.radius or 0), C.cyan)
end

-- 分隔线
function Hud.draw_rules(S, C)
  local px, py, pw = phos.screen.playfield()
  S.fill(px, py + 1, pw, 1, "-", C.dark_gray, C.black)
  S.fill(px, py + 38, pw, 1, "-", C.dark_gray, C.black)
end

-- 消息日志：最新 4 条、新在上（§10）
function Hud.draw_log(S, C, ctx)
  local px, py, pw = phos.screen.playfield()
  for i = 1, 4 do
    local entry = ctx.world.log[i]
    if entry then
      local line = phos.text.fit("> " .. entry.text, pw - 2)
      S.print(px + 1, py + 38 + i, line, tone_color(C, entry.tone))
    end
  end
end

-- 浮窗底板：先铺不透明底、再画边框（frame 只画边框不铺底，§api）。
-- 返回区块，供调用方在 (0,0) 局部坐标继续画。
function Hud.plate(x, y, w, h, title)
  local r = phos.ui.region(x, y, w, h)
  r:clear(phos.color.white, phos.color.black)
  r:frame(title or "")
  return r
end

return Hud

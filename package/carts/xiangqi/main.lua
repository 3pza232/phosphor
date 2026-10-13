-- main.lua —— 中国象棋入口：光标选子/落子（输入）+ 棋盘绘制（画面）。规则全在 game.lua。
-- 颜色一律取自主题色板（phos.color.*），不写死色值。
local Game = require("game")
local Panel = require("panel")

local Text = {
  zh = { title = "中国象棋", your = "你执红先行", think = "电脑思考中…", check = "将军！",
         win = "你赢了！", lose = "你输了", drawn = "终局", again = "按 %s 再来一局",
         hint = "[方向] 移动  [%s] 选/落  [%s] 取消  [%s] 重开" },
  en = { title = "CHINESE CHESS", your = "You are RED, move first", think = "thinking...",
         check = "CHECK!", win = "YOU WIN", lose = "YOU LOSE", drawn = "GAME OVER",
         again = "press %s for a new game",
         hint = "[ARROWS] move  [%s] pick/drop  [%s] cancel  [%s] new" },
}

local game
local cart = {}
local cf, cr = 4, 9       -- 光标（默认停在红帅上）

-- 棋盘布局：文件间距 5（棋子两格宽、左右各留出格线），行距 3，河界再加一行。
-- 棋子摆在**两条格线的交点**上（线穿过棋子），不是格子里。
local FILE = function(f) return 2 + 5 * f end
local ROW = function(r) return 2 + 3 * r + (r >= 5 and 1 or 0) end
local XR = function() return FILE(8) + 1 end          -- 棋盘最右（最右列棋子右半）
local Y0 = 1                  -- 上边框

local function rng(a, b)
  if a == nil then return phos.sys.random(0, 9999) / 10000 end
  return phos.sys.random(a, b)
end

local function new_game()
  game = Game.new(rng, phos.sys.time)
  cf, cr = 4, 9
end

function init()
  cart = phos.cart.info()
  new_game()
  phos.audio.music(require("music"))
end

function update(dt)
  if phos.input.pressed("start") then
    new_game()
    phos.audio.beep(440, 0.06)
    return
  end
  if game.over then
    if phos.input.pressed("a") then new_game(); phos.audio.beep(520, 0.06) end
    return
  end

  if phos.input.pressed("left") then cf = math.max(0, cf - 1) end
  if phos.input.pressed("right") then cf = math.min(8, cf + 1) end
  if phos.input.pressed("up") then cr = math.max(0, cr - 1) end
  if phos.input.pressed("down") then cr = math.min(9, cr + 1) end

  if phos.input.pressed("b") then game:cancel(); phos.audio.beep(300, 0.03) end
  if phos.input.pressed("a") and game.turn == game.player_side then
    local r = game:choose(cf, cr)
    if r == "selected" then phos.audio.beep(700, 0.03)
    elseif r == "moved" then phos.audio.beep(620, 0.05) else phos.audio.beep(260, 0.03) end
  end

  local ev = game:update(dt)
  if ev.ai_moved then phos.audio.beep(380, 0.05) end
  if game.over then phos.audio.beep(game.winner == game.player_side and 880 or 200, 0.4) end
end

-- 给一格的**背景**上色（保留字形）：选中 / 可落子 / 光标的提示都用它
local function tint(px, py, f, r, col)
  for dx = 0, 1 do phos.screen.back(px + FILE(f) + dx, py + ROW(r), col) end
end

-- 沿一条斜线撒下对角字符（九宫的两条斜线用 ╲/╱ 近似）
local function slash(S, px, py, x0, y0, x1, y1, ch, col)
  local steps = math.abs(y1 - y0)
  for i = 0, steps do
    local y = y0 + (y1 > y0 and i or -i)
    local x = math.floor(x0 + (x1 - x0) * i / steps + 0.5)
    S.put(px + x, py + y, ch, col)
  end
end

local function draw_board(px, py)
  local C, S = phos.color, phos.screen
  local rlo, rhi = ROW(4) + 1, ROW(5) - 1        -- 河界那几行：竖线只在最外两条

  -- 横线 + 交点（每个排名行）：交点上画 ┼，其余画 ─。棋子稍后会盖住交点
  for r = 0, 9 do
    for x = FILE(0), XR() do
      local cross = ((x - FILE(0)) % 5 == 0)
      S.put(px + x, py + ROW(r), cross and "\u{253C}" or "\u{2500}", C.dark_gray)
    end
  end
  -- 竖线（两排行之间；河界那几行只留最外两条）——按相邻两排之间逐行铺，与行距无关
  for r = 0, 8 do
    for ry = ROW(r) + 1, ROW(r + 1) - 1 do
      if ry >= rlo and ry <= rhi then
        S.put(px + FILE(0), py + ry, "\u{2502}", C.dark_gray)
        S.put(px + FILE(8), py + ry, "\u{2502}", C.dark_gray)
      else
        for f = 0, 8 do S.put(px + FILE(f), py + ry, "\u{2502}", C.dark_gray) end
      end
    end
  end

  -- 九宫：两宫各画士的两条斜线 + 中心 ╳
  for _, base in ipairs({ 0, 7 }) do
    slash(S, px, py, FILE(3), ROW(base), FILE(5), ROW(base + 2), "\u{2572}", C.gray)
    slash(S, px, py, FILE(5), ROW(base), FILE(3), ROW(base + 2), "\u{2571}", C.gray)
    S.put(px + FILE(4), py + ROW(base + 1), "\u{2573}", C.gray)
  end

  -- 兵/卒 与 炮/砲 的起始点标记（传统"炮位/兵位"小叉）：空交点处画 ╬
  local marks = {}
  for _, r in ipairs({ 3, 6 }) do
    for f = 0, 8, 2 do marks[#marks + 1] = { f, r } end
  end
  for _, r in ipairs({ 2, 7 }) do
    marks[#marks + 1] = { 1, r }
    marks[#marks + 1] = { 7, r }
  end
  for _, m in ipairs(marks) do
    if not game:piece(m[1], m[2]) then
      S.put(px + FILE(m[1]), py + ROW(m[2]), "\u{256C}", C.gray)
    end
  end

  -- 楚河汉界
  local ry = py + math.floor((rlo + rhi) / 2)
  S.print(px + FILE(1) + 1, ry, phos.lang.pick({ zh = "楚 河", en = "CHU RIVER" }), C.dark_gray)
  S.print(px + FILE(6) - 1, ry, phos.lang.pick({ zh = "汉 界", en = "HAN BORDER" }), C.dark_gray)

  -- 行列号
  for f = 0, 8 do S.put(px + FILE(f), py + ROW(9) + 2, tostring(f + 1), C.dark_gray) end
  for r = 0, 9 do S.print(px, py + ROW(r), string.format("%2d", r + 1), C.dark_gray) end

  -- 提示底色（先铺，再画棋子）：选中 = 青、可落子 = 绿、光标 = 暗灰
  if game.sel then
    tint(px, py, game.sel.f, game.sel.r, C.cyan)
    for _, m in ipairs(game.sel.moves) do tint(px, py, m.f, m.r, C.green) end
  end
  tint(px, py, cf, cr, C.dark_gray)

  -- 棋子（摆在交点上：占交点格与其右一格）
  for r = 0, 9 do
    for f = 0, 8 do
      local p = game:piece(f, r)
      if p then
        S.put(px + FILE(f), py + ROW(r), game:name_of(p), (p.s == "r") and C.red or C.white)
      end
    end
  end

  -- 光标框
  S.put(px + FILE(cf) - 1, py + ROW(cr), "[", C.yellow)
  S.put(px + FILE(cf) + 2, py + ROW(cr), "]", C.yellow)
end

function draw()
  local C, S = phos.color, phos.screen
  local t = phos.lang.dict(Text)
  local px, py = S.playfield()

  S.clear()   -- 空格 + 色板默认底（随主题）
  draw_board(px, py)

  S.print(px + FILE(2), py, phos.text.fit(t.title, 24), C.orange)

  local sy = py + ROW(9) + 3
  local st = game:status()
  if game.over then
    local res = (st.winner == game.player_side) and t.win or (st.winner and t.lose or t.drawn)
    S.print(px + 2, sy, res, C.yellow)
    S.print(px + 2, sy + 1, string.format(t.again, phos.input.key_name("a")), C.white)
  else
    S.print(px + 2, sy, (st.turn == game.player_side) and t.your or t.think,
            (st.turn == game.player_side) and C.cyan or C.gray)
    if st.in_check then S.print(px + 2, sy + 1, t.check, C.red) end
  end
  S.print(px + 2, sy + 2, string.format(t.hint, phos.input.key_name("a"),
          phos.input.key_name("b"), phos.input.key_name("start")), C.dark_gray)

  Panel.draw(game, cart)
end

function debug_state()
  local st = game:status()
  st.cursor = cf .. "," .. cr
  return st
end

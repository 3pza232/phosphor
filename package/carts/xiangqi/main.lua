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

-- 棋盘布局：文件间距 4（棋子两格宽 + 左右各留白），行距 2，河界两行
local FILE = function(f) return 3 + 4 * f end
local ROW = function(r) return 2 + 2 * r + (r >= 5 and 2 or 0) end
local X0, X1 = 2, 37          -- 棋盘左右边框（贴齐最外列棋子）
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

local function draw_board(px, py)
  local C, S = phos.color, phos.screen
  local y0, y1 = py + Y0, py + ROW(9) + 1
  local rlo, rhi = ROW(4) + 1, ROW(5) - 1     -- 河界两行：竖线断开，留给"楚河汉界"

  -- 外框
  for x = px + X0 + 1, px + X1 - 1 do
    S.put(x, y0, "\u{2500}", C.gray)
    S.put(x, y1, "\u{2500}", C.gray)
  end
  for y = y0 + 1, y1 - 1 do
    S.put(px + X0, y, "\u{2502}", C.gray)
    S.put(px + X1, y, "\u{2502}", C.gray)
  end
  S.put(px + X0, y0, "\u{250C}", C.gray); S.put(px + X1, y0, "\u{2510}", C.gray)
  S.put(px + X0, y1, "\u{2514}", C.gray); S.put(px + X1, y1, "\u{2518}", C.gray)

  -- 竖线：每条文件线（河界处断开）
  for f = 0, 8 do
    for ry = ROW(0), ROW(9) do
      if ry < rlo or ry > rhi then S.put(px + FILE(f), py + ry, "\u{2502}", C.dark_gray) end
    end
  end
  -- 横线：每两行之间一条（河界上下边界照画，中间不画）
  for ry = ROW(0) + 1, ROW(9) - 1, 2 do
    for x = px + FILE(0), px + FILE(8) + 1 do
      S.put(x, py + ry, "\u{2500}", C.dark_gray)
    end
  end
  -- 交点
  for f = 0, 8 do
    for ry = ROW(0) + 1, ROW(9) - 1, 2 do
      if ry < rlo or ry > rhi then S.put(px + FILE(f), py + ry, "\u{253C}", C.dark_gray) end
    end
  end

  -- 九宫斜线（两宫中心一个 ╳）+ 楚河汉界
  S.put(px + FILE(4), py + ROW(1), "\u{2573}", C.gray)
  S.put(px + FILE(4), py + ROW(8), "\u{2573}", C.gray)
  local ry = py + math.floor((rlo + rhi) / 2)   -- 河界中间那一行（上下边界是格线，文字在中间）
  S.print(px + FILE(1) + 1, ry, phos.lang.pick({ zh = "楚 河", en = "CHU RIVER" }), C.dark_gray)
  S.print(px + FILE(6), ry, phos.lang.pick({ zh = "汉 界", en = "HAN BORDER" }), C.dark_gray)

  -- 行列号
  for f = 0, 8 do S.put(px + FILE(f), y1 + 1, tostring(f + 1), C.dark_gray) end
  for r = 0, 9 do S.print(px, py + ROW(r), string.format("%2d", r + 1), C.dark_gray) end

  -- 提示底色（先铺，再画棋子）：选中 = 青、可落子 = 绿、光标 = 暗灰
  if game.sel then
    tint(px, py, game.sel.f, game.sel.r, C.cyan)
    for _, m in ipairs(game.sel.moves) do tint(px, py, m.f, m.r, C.green) end
  end
  tint(px, py, cf, cr, C.dark_gray)

  -- 棋子
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

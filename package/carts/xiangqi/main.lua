-- main.lua —— 中国象棋入口：光标选子/落子（输入）+ 棋盘绘制（画面）。规则全在 game.lua。
local Game = require("game")
local Panel = require("panel")

local Text = {
  zh = { title = "中国象棋", your = "你执红先行", think = "电脑思考中…", check = "将军！",
         win = "你赢了！", lose = "你输了", drawn = "终局", again = "按 %s 再来一局",
         sel = "选中", hint = "[方向] 移动  [%s] 选/落  [%s] 取消  [%s] 重开" },
  en = { title = "CHINESE CHESS", your = "You are RED, move first", think = "thinking...",
         check = "CHECK!", win = "YOU WIN", lose = "YOU LOSE", drawn = "GAME OVER",
         again = "press %s for a new game", sel = "selected",
         hint = "[ARROWS] move  [%s] pick/drop  [%s] cancel  [%s] new" },
}

local game
local cart = {}
local cf, cr = 4, 9       -- 光标（默认停在红帅上）
local flash = 0           -- 短暂提示计时

local FILE = function(f) return 2 + 3 * f end
local ROW = function(r) return 2 + 2 * r + (r >= 5 and 2 or 0) end  -- 河界在 4、5 行之间留 2 行

local function rng(a, b)
  if a == nil then return phos.sys.random(0, 9999) / 10000 end
  return phos.sys.random(a, b)
end

local function new_game()
  game = Game.new(rng)
  cf, cr = 4, 9
  flash = 0
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

local function mark(px, py, f, r)
  phos.screen.back(px + FILE(f), py + ROW(r), phos.color.dark_gray)
  phos.screen.back(px + FILE(f) + 1, py + ROW(r), phos.color.dark_gray)
end

local function draw_board(px, py)
  local C, S = phos.color, phos.screen
  local x0, x1 = px + 1, px + 28
  local y0, y1 = py + 1, py + ROW(9) + 1
  local rlo, rhi = ROW(4) + 1, ROW(5) - 1        -- 河界那两行：竖线断开，留给"楚河汉界"

  -- 外框
  for x = x0 + 1, x1 - 1 do
    S.put(x, y0, "\u{2500}", C.gray)
    S.put(x, y1, "\u{2500}", C.gray)
  end
  for y = y0 + 1, y1 - 1 do
    S.put(x0, y, "\u{2502}", C.gray)
    S.put(x1, y, "\u{2502}", C.gray)
  end
  S.put(x0, y0, "\u{250C}", C.gray); S.put(x1, y0, "\u{2510}", C.gray)
  S.put(x0, y1, "\u{2514}", C.gray); S.put(x1, y1, "\u{2518}", C.gray)

  -- 竖线（每两个文件之间一条，河界处断开）
  for f = 0, 7 do
    local x = px + FILE(f) + 2
    for ry = ROW(0), ROW(9) do
      if ry < rlo or ry > rhi then S.put(x, py + ry, "\u{2502}", C.dark_gray) end
    end
  end
  -- 横线（每两行之间一条；河界只留上下边界 11/13 两条，中间不画）
  for ry = ROW(0) + 1, ROW(9) - 1, 2 do
    for x = px + FILE(0), px + FILE(8) + 1 do
      S.put(x, py + ry, "\u{2500}", C.dark_gray)
    end
  end
  -- 交点（竖线与横线相交处；河界内竖线已断，不画交点）
  for f = 0, 7 do
    for ry = ROW(0) + 1, ROW(9) - 1, 2 do
      if ry < rlo or ry > rhi then S.put(px + FILE(f) + 2, py + ry, "\u{253C}", C.dark_gray) end
    end
  end

  -- 楚河汉界
  local ry = py + math.floor((rlo + rhi) / 2) + 1
  S.print(px + 5, ry, phos.lang.pick({ zh = "楚 河", en = "CHU RIVER" }), C.dark_gray)
  S.print(px + 18, ry, phos.lang.pick({ zh = "汉 界", en = "HAN BORDER" }), C.dark_gray)

  -- 行列号
  for f = 0, 8 do S.put(px + FILE(f), y1 + 1, tostring(f + 1), C.dark_gray) end
  for r = 0, 9 do S.print(px, py + ROW(r), string.format("%2d", r + 1), C.dark_gray) end

  -- 选中与光标提示（先铺底色，再画棋子）
  if game.sel then
    mark(px, py, game.sel.f, game.sel.r)
    for _, m in ipairs(game.sel.moves) do mark(px, py, m.f, m.r) end
  end
  for dx = 0, 1 do S.back(px + FILE(cf) + dx, py + ROW(cr), C.rgb(70, 60, 20)) end

  -- 棋子
  for r = 0, 9 do
    for f = 0, 8 do
      local p = game:piece(f, r)
      if p then
        local col = (p.s == "r") and C.red or C.white
        S.put(px + FILE(f), py + ROW(r), game:name_of(p), col)
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

  S.clear(C.rgb(28, 20, 12), C.rgb(28, 20, 12))
  draw_board(px, py)

  S.print(px + FILE(0), py, phos.text.fit(t.title, 20), C.orange)

  -- 状态行（棋盘下方）
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

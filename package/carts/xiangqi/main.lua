-- main.lua —— 中国象棋入口：选择界面 → 对局。规则全在 game.lua。
-- 颜色一律取自主题色板（phos.color.*），不写死色值。
local Game = require("game")
local Panel = require("panel")

local Text = {
  zh = {
    title = "中国象棋", menu_title = "对局设置", side = "执子", level = "电脑",
    red = "红（先行）", black = "黑", lv = { "简单", "老手", "超算" },
    menu_hint = "↑↓ 选择   ←→ 调整   %s 开始",
    your = "你的回合", theirs = "对方回合", check = "将军！",
    win = "你赢了！", lose = "你输了", drawn = "终局", again = "按 %s 再来一局",
  },
  en = {
    title = "CHINESE CHESS", menu_title = "MATCH SETUP", side = "SIDE", level = "COMPUTER",
    red = "RED (first)", black = "BLACK", lv = { "EASY", "VETERAN", "SUPER" },
    menu_hint = "↑↓ SELECT   ←→ CHANGE   %s START",
    your = "YOUR TURN", theirs = "OPPONENT", check = "CHECK!",
    win = "YOU WIN", lose = "YOU LOSE", drawn = "GAME OVER", again = "press %s for a new game",
  },
}

local screen     -- "menu" / "play"
local menu = { row = 1, side = 1, level = 2 }   -- side: 1 红 / 2 黑；level: 1..3
local game
local cart = {}
local cf, cr = 4, 9     -- 光标（红帅默认位置）

-- 棋盘布局：文件间距 5、行距 3，河界再加一行；棋子摆在**两条格线的交点**上。
local FILE = function(f) return 2 + 5 * f end
local ROW = function(r) return 2 + 3 * r + (r >= 5 and 1 or 0) end
local XR = function() return FILE(8) + 1 end

local function rng(a, b)
  if a == nil then return phos.sys.random(0, 9999) / 10000 end
  return phos.sys.random(a, b)
end

local function begin_match()
  local side = (menu.side == 1) and "r" or "b"
  game = Game.new(rng, phos.sys.time, side, menu.level)
  cf, cr = 4, 9
  screen = "play"
  phos.audio.music(require("music"))   -- 选择界面不放音乐，进对局才放
end

function init()
  cart = phos.cart.info()
  menu.row, menu.side, menu.level = 1, 1, 2
  screen = "menu"
  game = nil
end

-- ── 选择界面 ──────────────────────────────────────────────
local function update_menu()
  if phos.input.pressed("up") then menu.row = math.max(1, menu.row - 1) end
  if phos.input.pressed("down") then menu.row = math.min(2, menu.row + 1) end
  if phos.input.pressed("left") or phos.input.pressed("right") then
    local step = phos.input.pressed("right") and 1 or -1
    if menu.row == 1 then
      menu.side = ((menu.side - 1 + step) % 2) + 1
    else
      menu.level = ((menu.level - 1 + step) % 3) + 1
    end
    phos.audio.beep(620, 0.03)
  end
  if phos.input.pressed("start") then
    phos.audio.beep(760, 0.05)
    begin_match()
  end
end

local function draw_menu()
  local C, S = phos.color, phos.screen
  local t = phos.lang.dict(Text)
  S.clear()

  local bw = 34
  local box = phos.ui.modal(bw, 7, t.menu_title)

  local side_col = { C.red, C.white }
  local rows = {
    { t.side, menu.side == 1 and t.red or t.black, side_col[menu.side] },
    { t.level, t.lv[menu.level], C.cyan },
  }
  for i, row in ipairs(rows) do
    local y = box.y + 2 + i
    S.put(box.x + 3, y, menu.row == i and ">" or " ", C.yellow)
    S.print(box.x + 5, y, phos.text.pad(row[1], 8) .. "< " .. phos.text.pad(row[2], 10) .. " >", row[3])
  end
  -- 提示放在框**外**下方并居中：英文文案较长，塞进框里会顶穿右边界
  phos.ui.center_text(box.y + box.h + 1, string.format(t.menu_hint, phos.input.key_name("start")),
                      C.dark_gray)
end

-- ── 对局 ─────────────────────────────────────────────────
local function update_play(dt)
  if phos.input.pressed("start") then
    screen = "menu"               -- 回到设置界面（重开）
    phos.audio.stop_music()
    return
  end
  if game.over then
    if phos.input.pressed("a") then begin_match() end
    if phos.input.pressed("backspace") then
      if game:undo() then phos.audio.beep(420, 0.05) end
    end
    return
  end

  if phos.input.pressed("left") then cf = math.max(0, cf - 1) end
  if phos.input.pressed("right") then cf = math.min(8, cf + 1) end
  if phos.input.pressed("up") then cr = math.max(0, cr - 1) end
  if phos.input.pressed("down") then cr = math.min(9, cr + 1) end

  if phos.input.pressed("b") then game:cancel(); phos.audio.beep(300, 0.03) end
  if phos.input.pressed("backspace") then
    if game:undo() then phos.audio.beep(420, 0.05) else phos.audio.beep(240, 0.03) end
  end
  if phos.input.pressed("a") and game.turn == game.player_side then
    local r = game:choose(cf, cr)
    if r == "selected" then phos.audio.beep(700, 0.03)
    elseif r == "moved" then phos.audio.beep(620, 0.05) else phos.audio.beep(260, 0.03) end
  end

  local ev = game:update(dt)
  if ev.ai_moved then phos.audio.beep(380, 0.05) end
  if game.over then phos.audio.beep(game.winner == game.player_side and 880 or 200, 0.4) end
end

local function tint(px, py, f, r, col)
  for dx = 0, 1 do phos.screen.back(px + FILE(f) + dx, py + ROW(r), col) end
end

-- 沿斜线撒对角字符；两端（九宫四角）不撒，保持正常交点
local function slash(S, px, py, x0, y0, x1, y1, ch, col)
  local steps = math.abs(y1 - y0)
  for i = 1, steps - 1 do
    local y = py + y0 + i
    local x = px + math.floor(x0 + (x1 - x0) * i / steps + 0.5)
    S.put(x, y, ch, col)
  end
end

local function draw_board()
  local C, S = phos.color, phos.screen
  local px, py = S.playfield()
  local rlo, rhi = ROW(4) + 1, ROW(5) - 1

  -- 横线 + 交点（每个排名行）
  for r = 0, 9 do
    for x = FILE(0), XR() do
      local cross = ((x - FILE(0)) % 5 == 0)
      S.put(px + x, py + ROW(r), cross and "\u{253C}" or "\u{2500}", C.dark_gray)
    end
  end
  -- 竖线（两排行之间；河界那几行只留最外两条）
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

  -- 九宫：士的两条斜线（端点=四角，不覆盖）+ 中心 ╳
  for _, base in ipairs({ 0, 7 }) do
    slash(S, px, py, FILE(3), ROW(base), FILE(5), ROW(base + 2), "\u{2572}", C.gray)
    slash(S, px, py, FILE(5), ROW(base), FILE(3), ROW(base + 2), "\u{2571}", C.gray)
    S.put(px + FILE(4), py + ROW(base + 1), "\u{2573}", C.gray)
  end

  -- 兵/卒 与 炮/砲 起始点标记：空交点处画 ╬
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

  for f = 0, 8 do S.put(px + FILE(f), py + ROW(9) + 2, tostring(f + 1), C.dark_gray) end
  for r = 0, 9 do S.print(px, py + ROW(r), string.format("%2d", r + 1), C.dark_gray) end

  -- 提示底色
  if game.sel then
    tint(px, py, game.sel.f, game.sel.r, C.cyan)
    for _, m in ipairs(game.sel.moves) do tint(px, py, m.f, m.r, C.green) end
  end
  tint(px, py, cf, cr, C.dark_gray)

  -- 棋子（摆在交点上）
  for r = 0, 9 do
    for f = 0, 8 do
      local p = game:piece(f, r)
      if p then
        S.put(px + FILE(f), py + ROW(r), game:name_of(p), (p.s == "r") and C.red or C.white)
      end
    end
  end

  S.put(px + FILE(cf) - 1, py + ROW(cr), "[", C.yellow)
  S.put(px + FILE(cf) + 2, py + ROW(cr), "]", C.yellow)
end

local function draw_play()
  local C, S = phos.color, phos.screen
  local t = phos.lang.dict(Text)
  local px, py = S.playfield()

  S.clear()
  draw_board()
  S.print(px + FILE(2), py, phos.text.fit(t.title, 24), C.orange)

  local sy = py + ROW(9) + 3
  local st = game:status()
  if game.over then
    local res = (st.winner == st.player_side) and t.win or (st.winner and t.lose or t.drawn)
    S.print(px + 2, sy, res, C.yellow)
    S.print(px + 2, sy + 1, string.format(t.again, phos.input.key_name("a")), C.white)
  else
    S.print(px + 2, sy, (st.turn == st.player_side) and t.your or t.theirs,
            (st.turn == st.player_side) and C.cyan or C.gray)
    if st.in_check then S.print(px + 2, sy + 1, t.check, C.red) end
  end
  -- 键位提示放侧栏最下面（见 panel.lua），棋盘下只留状态

  Panel.draw(game, cart)
end

function update(dt)
  if screen == "menu" then update_menu() else update_play(dt) end
end

function draw()
  if screen == "menu" then draw_menu() else draw_play() end
end

function debug_state()
  if screen == "menu" then
    return { screen = "menu", side = menu.side, level = menu.level, row = menu.row }
  end
  local st = game:status()
  st.screen = "play"
  st.cursor = cf .. "," .. cr
  return st
end

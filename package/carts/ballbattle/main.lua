-- main.lua —— 入口：把输入翻成"意图"、把 game 的状态画出来。规则全在 game.lua。
local Game = require("game")
local Panel = require("panel")

local Text = {
  zh = { score = "体格", time = "存活", over = "被吞掉啦", won = "你是最大的球！",
         again = "按 %s 再来一局", pause = "暂停中", hint = "方向键 移动    [%s] 暂停" },
  en = { score = "MASS", time = "TIME", over = "EATEN", won = "YOU ARE THE BIGGEST",
         again = "press %s to play again", pause = "PAUSED", hint = "ARROWS move   [%s] PAUSE" },
}

local game
local cart = {}
local paused = false
local palette   -- 每个球的颜色：玩家青色，电脑暖色

-- 主机种子驱动的随机：Game 会以 rng()（浮点）与 rng(a,b)（整数）两种方式调用
local function rng(a, b)
  if a == nil then return phos.sys.random(0, 9999) / 10000 end
  return phos.sys.random(a, b)
end

local function best_score()
  return tonumber(phos.save.read("best") or "0") or 0
end

local function save_best()
  local sc = game:status().score
  if sc > best_score() then phos.save.write("best", tostring(sc)) end
end

local function new_game()
  local _, _, pw, ph = phos.screen.playfield()
  game = Game.new(pw, ph, rng)
  paused = false
end

function init()
  cart = phos.cart.info()
  palette = { player = phos.color.cyan,
              ai = { phos.color.red, phos.color.orange, phos.color.magenta, phos.color.yellow } }
  new_game()
  phos.audio.music(require("music"))
end

function update(dt)
  if phos.input.pressed("start") then
    paused = not paused
    phos.audio.paused(paused)
  end
  if paused then return end

  if not game.alive then
    if phos.input.pressed("a") then
      save_best()
      new_game()
      phos.audio.beep(520, 0.06)
    end
    return
  end

  -- 输入 → 意图：方向键按住时给方向向量，归一化由 game 做
  local dx = (phos.input.down("right") and 1 or 0) - (phos.input.down("left") and 1 or 0)
  local dy = (phos.input.down("down") and 1 or 0) - (phos.input.down("up") and 1 or 0)
  game:steer(dx, dy)

  local ev = game:update(dt)
  if ev.eat then phos.audio.beep(900, 0.03, { volume = 0.10 }) end
  if ev.kill then phos.audio.beep(680, 0.09, { volume = 0.16, wave = "square" }) end
  if ev.player_died then
    phos.audio.beep(140, 0.5, { sweep = 60, wave = "saw", volume = 0.22 })
    save_best()
  end
end

-- 一个球画成实心圆：逐格判断圆心距，落在半径内就填块
local function draw_blob(px, py, b)
  local col = (b.role == "player") and palette.player or palette.ai[b.ai]
  local rr = b.r + 0.35
  for cy = math.floor(b.y - rr), math.ceil(b.y + rr) do
    for cx = math.floor(b.x - rr), math.ceil(b.x + rr) do
      local dx, dy = cx - b.x, cy - b.y
      if dx * dx + dy * dy <= rr * rr then
        phos.screen.put(px + cx, py + cy, "\u{2588}", col)   -- 全块
      end
    end
  end
end

local function draw_field(px, py, pw, ph, t)
  local C, S = phos.color, phos.screen
  -- 淡淡的点阵底纹，衬出边界
  for y = 1, ph - 2, 4 do
    for x = 1, pw - 2, 4 do S.put(px + x, py + y, "\u{00B7}", C.rgb(30, 40, 60)) end
  end

  for _, f in ipairs(game.food) do
    S.put(px + math.floor(f.x), py + math.floor(f.y), "o", C.green)
  end

  -- 小的先画、大的后画（大球盖在上面）
  for _, b in ipairs(game:ranked()) do draw_blob(px, py, b) end

  -- 玩家标记：在球上方写一个字，免得在一堆球里认不出自己
  local p = game.player
  local label = t.me
  S.print(px + math.floor(p.x) - 1, py + math.floor(p.y - p.r) - 1, label, C.white)
end

function draw()
  local C, S = phos.color, phos.screen
  local t = phos.lang.dict(Text)
  t.me = phos.lang.pick({ zh = "你", en = "YOU" })
  local px, py, pw, ph = S.playfield()

  S.clear(C.rgb(8, 10, 16), C.rgb(8, 10, 16))
  draw_field(px, py, pw, ph, t)

  -- 顶部读数
  local st = game:status()
  S.print(px + 1, py, string.format("%s %d    %s %.1fs", t.score, st.score, t.time, st.time),
          C.white)

  if not game.alive then
    local over = st.won and t.won or t.over
    local box = phos.ui.modal(20, 5, "")
    phos.ui.center_text(box.y + 1, over)
    phos.ui.center_text(box.y + 3, string.format(t.again, phos.input.key_name("a")))
  elseif paused then
    phos.ui.center_text(py + math.floor(ph / 2), t.pause)
  end

  S.print(px + 1, py + ph - 1,
          string.format(t.hint, phos.input.key_name("start")), C.dark_gray)

  Panel.draw(game, cart, best_score)
end

function debug_state()
  local st = game:status()
  st.paused = paused
  return st
end

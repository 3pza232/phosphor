-- main.lua —— 入口：把输入翻成"意图"、用**摄像机**跟随玩家取景。规则全在 game.lua。
-- 颜色一律取自主题色板（phos.color.*），不写死色值——换主题即换配色。
local Game = require("game")
local Panel = require("panel")

local Text = {
  zh = { score = "体格", time = "存活", over = "被吞掉啦", won = "你是最大的球！",
         again = "按 %s 再来一局", pause = "暂停中", me = "你",
         hint = "方向键 移动    [%s] 暂停" },
  en = { score = "MASS", time = "TIME", over = "EATEN", won = "YOU ARE THE BIGGEST",
         again = "press %s to play again", pause = "PAUSED", me = "YOU",
         hint = "ARROWS move   [%s] PAUSE" },
}

local game
local cart = {}
local paused = false
local rng          -- 主机种子驱动
local ai_colors    -- 电脑球配色（从色板取，不含玩家色）
local view_scale = 1   -- 当前视距倍率（1 屏幕格 = 这么多世界单位），由 draw 更新

local function new_game()
  game = Game.new(rng)
  paused = false
end

local best = 0            -- 历史最高分（init 读盘一次，之后常驻内存）

local function best_score() return best end

-- 结算：分数线只增不减（吃的 + 体格峰值）。**当前分一越过历史最高就记下并落盘**，
-- 于是"主动退出"（拔卡 / 关机）与死亡走同一条路——高手不想玩了退出也不会白打。
-- 生命期里只在刷新纪录时才写盘（吃一个食物才涨一次分），不会形成每帧 IO
local function settle()
  local sc = game:status().score
  if sc > best then
    best = sc
    phos.save.write("best", tostring(best))
  end
end

function init()
  local C = phos.color
  rng = function(a, b)
    if a == nil then return phos.sys.random(0, 9999) / 10000 end
    return phos.sys.random(a, b)
  end
  -- 电脑球配色：取色板里除玩家青、黑、白之外的醒目色
  ai_colors = { C.red, C.orange, C.yellow, C.magenta, C.green, C.blue, C.purple }
  cart = phos.cart.info()
  best = tonumber(phos.save.read("best") or "0") or 0
  new_game()
  phos.audio.music(require("music"))
end

function update(dt)
  if phos.input.pressed("start") then
    paused = not paused
    phos.audio.paused(paused)
  end
  if paused then return end

  settle()   -- 主动退出也算结算：不必等到死亡，分数刷新即记下

  if not game.alive then
    if phos.input.pressed("a") then new_game(); phos.audio.beep(520, 0.06) end
    return
  end

  local dx = (phos.input.down("right") and 1 or 0) - (phos.input.down("left") and 1 or 0)
  local dy = (phos.input.down("down") and 1 or 0) - (phos.input.down("up") and 1 or 0)
  game:steer(dx, dy)

  local ev = game:update(dt)
  if ev.eat then phos.audio.beep(900, 0.03, { volume = 0.10 }) end
  if ev.kill then phos.audio.beep(680, 0.09, { volume = 0.16, wave = "square" }) end
  if ev.player_died then
    phos.audio.beep(140, 0.5, { sweep = 60, wave = "saw", volume = 0.22 })
  end
end

local function draw_blob(S, px, py, cam_x, cam_y, scale, pw, ph, b, col)
  local sx0 = math.max(0, math.floor((b.x - b.r - cam_x) / scale))
  local sx1 = math.min(pw - 1, math.ceil((b.x + b.r - cam_x) / scale))
  local sy0 = math.max(0, math.floor((b.y - b.r - cam_y) / scale))
  local sy1 = math.min(ph - 1, math.ceil((b.y + b.r - cam_y) / scale))
  for sy = sy0, sy1 do
    local wy = cam_y + (sy + 0.5) * scale
    for sx = sx0, sx1 do
      local wx = cam_x + (sx + 0.5) * scale
      local dx, dy = wx - b.x, wy - b.y
      if dx * dx + dy * dy <= b.r * b.r then
        S.put(px + sx, py + sy, "\u{2588}", col)   -- 全块
      end
    end
  end
end

function draw()
  local C, S = phos.color, phos.screen
  local t = phos.lang.dict(Text)
  local px, py, pw, ph = S.playfield()
  local p = game.player

  -- 缩放：体型越大看得越远（否则大球糊满整屏）。1 屏幕格 = scale 个世界单位
  local scale = math.min(4, 1 + math.floor(p.r / 8))
  view_scale = scale

  local vw, vh = pw * scale, ph * scale
  local cam_x = math.max(0, math.min(p.x - vw / 2, Game.WORLD_W - vw))
  local cam_y = math.max(0, math.min(p.y - vh / 2, Game.WORLD_H - vh))
  local function to_sx(wx) return math.floor((wx - cam_x) / scale) end
  local function to_sy(wy) return math.floor((wy - cam_y) / scale) end

  S.clear()   -- 空格 + 色板默认底（随主题）

  -- 底纹：随世界走的稀疏点阵（世界坐标 5 的倍数），衬出移动感
  for wy = math.floor(cam_y / 5) * 5, cam_y + vh, 5 do
    local sy = to_sy(wy)
    if sy >= 0 and sy < ph then
      for wx = math.floor(cam_x / 5) * 5, cam_x + vw, 5 do
        local sx = to_sx(wx)
        if sx >= 0 and sx < pw then S.put(px + sx, py + sy, "\u{00B7}", C.dark_gray) end
      end
    end
  end

  for _, f in ipairs(game.food) do
    local sx, sy = to_sx(f.x), to_sy(f.y)
    if sx >= 0 and sx < pw and sy >= 0 and sy < ph then S.put(px + sx, py + sy, "o", C.green) end
  end

  for _, b in ipairs(game:ranked()) do
    local col = (b.role == "player") and C.cyan or ai_colors[(b.hue - 1) % #ai_colors + 1]
    draw_blob(S, px, py, cam_x, cam_y, scale, pw, ph, b, col)
  end

  -- 玩家标记：球上方一个字，免得在一堆球里认不出自己。
  -- 阵亡后玩家球已从 blobs 移除，这个字也必须立刻消失，别在残影上留个"你"
  if game.alive then
    S.print(px + to_sx(p.x) - 1, py + to_sy(p.y - p.r) - 1, t.me, C.white)
  end

  -- 顶部读数：体格 / 存活 / 名次 / 坐标 / 视距
  local st = game:status()
  local rank = 1
  for i, b in ipairs(game:ranked()) do if b == p then rank = i break end end
  S.print(px + 1, py, string.format("%s %d   %s %.1fs   #%d/%d   (%d,%d)   x%d",
          t.score, st.score, t.time, st.time, rank, st.blobs,
          math.floor(p.x), math.floor(p.y), scale), C.white)

  if not game.alive then
    -- 阵亡浮窗：整块铺**实底**（取主题色板里的灰，随主题），连边框那圈一起盖住——
    -- 只填内框的话边框上还压着球，浮窗就成了半透明的，读不清
    local bw, bh = 22, 5
    local sw, sh = S.size()
    local bx, by = math.floor((sw - bw) / 2), math.floor((sh - bh) / 2)
    local r = phos.ui.region(bx, by, bw, bh)
    r:clear(C.white, C.dark_gray)
    r:frame("")
    phos.ui.center_text(by + 1, st.won and t.won or t.over)
    phos.ui.center_text(by + 3, string.format(t.again, phos.input.key_name("a")))
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
  st.view_scale = view_scale
  return st
end

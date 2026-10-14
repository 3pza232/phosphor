-- main.lua —— 入口：把输入翻成"意图"、用**摄像机**跟随玩家取景。规则全在 game.lua。
-- 颜色一律取自主题色板（phos.color.*），不写死色值——换主题即换配色。
local Game = require("game")
local Panel = require("panel")

local Text = {
  zh = { score = "体格", time = "存活", cells = "分身", over = "被吞掉啦", won = "你是最大的球！",
         again = "按 %s 再来一局", me = "你" },
  en = { score = "MASS", time = "TIME", cells = "CELLS", over = "EATEN", won = "YOU ARE THE BIGGEST",
         again = "press %s to play again", me = "YOU" },
}

local game
local cart = {}
local rng          -- 主机种子驱动
local ai_colors    -- 电脑球配色（从色板取，不含玩家色）

-- 相机的平滑状态：视距与环境都要**渐变**，不能跳变
local view_scale        -- 当前视距（1 屏幕格 = 这么多世界单位）
local cam_wx, cam_wy    -- 平滑后的相机中心（世界坐标）
local frame_dt = 1 / 60

local function clamp(v, lo, hi) return v < lo and lo or (v > hi and hi or v) end
local function approach(cur, target, k, dt) return cur + (target - cur) * (1 - math.exp(-k * dt)) end

local function new_game()
  game = Game.new(rng)
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
  -- 新玩法的"手感旋钮"交给 `~` 调试台实时微调（随界面语言）
  local GRP = { zh = "分裂 / 合并", en = "Split / Merge" }
  phos.debug.number({ zh = "分裂最小半径", en = "Split min r" },
    function() return Game.SPLIT_MIN end, function(v) Game.SPLIT_MIN = v end,
    { min = 1, max = 8, step = 0.1, group = GRP })
  phos.debug.number({ zh = "细胞上限", en = "Max cells" },
    function() return Game.MAX_CELLS end, function(v) Game.MAX_CELLS = math.floor(v) end,
    { min = 1, max = 32, step = 1, group = GRP })
  phos.debug.number({ zh = "合并等待(秒)", en = "Merge delay (s)" },
    function() return Game.MERGE_DELAY end, function(v) Game.MERGE_DELAY = v end,
    { min = 0, max = 30, step = 0.5, group = GRP })
  cart = phos.cart.info()
  best = tonumber(phos.save.read("best") or "0") or 0
  view_scale, cam_wx, cam_wy = nil, nil, nil
  new_game()
  phos.audio.music(require("music"))
end

function update(dt)
  frame_dt = dt
  settle()   -- 主动退出也算结算：不必等到死亡，分数刷新即记下

  if not game.alive then
    if phos.input.pressed("a") then new_game(); phos.audio.beep(520, 0.06) end
    return
  end

  local dx = (phos.input.down("right") and 1 or 0) - (phos.input.down("left") and 1 or 0)
  local dy = (phos.input.down("down") and 1 or 0) - (phos.input.down("up") and 1 or 0)
  game:steer(dx, dy)

  if phos.input.pressed("x") then                 -- X：分裂（静止时无效）
    game:split()
    phos.audio.beep(720, 0.05, { wave = "triangle", volume = 0.16 })
  end
  if phos.input.down("z") then                     -- Z：按住吐食
    game:eject(dt)
    phos.audio.beep(360, 0.03, { volume = 0.08 })
  end

  local ev = game:update(dt)
  if ev.eat then phos.audio.beep(900, 0.03, { volume = 0.10 }) end
  if ev.kill then phos.audio.beep(680, 0.09, { volume = 0.16, wave = "square" }) end
  if ev.spike then phos.audio.beep(520, 0.14, { wave = "square", volume = 0.18, sweep = 900 }) end
  if ev.lost then phos.audio.beep(300, 0.12, { wave = "saw", volume = 0.14 }) end
  if ev.player_died then
    phos.audio.beep(140, 0.5, { sweep = 60, wave = "saw", volume = 0.22 })
  end
end

-- 画一颗球：填充 + 一圈描边（edge）。描边让**紧挨在一起的分身也能分出彼此的分界**
local function draw_blob(S, px, py, cam_x, cam_y, scale, pw, ph, b, fill, edge)
  local ir = edge and math.max(b.r * 0.55, b.r - scale) or b.r   -- 描边厚约 1 屏幕格，但不超半径 45%
  local ir2 = ir > 0 and ir * ir or -1
  local sx0 = math.max(0, math.floor((b.x - b.r - cam_x) / scale))
  local sx1 = math.min(pw - 1, math.ceil((b.x + b.r - cam_x) / scale))
  local sy0 = math.max(0, math.floor((b.y - b.r - cam_y) / scale))
  local sy1 = math.min(ph - 1, math.ceil((b.y + b.r - cam_y) / scale))
  for sy = sy0, sy1 do
    local wy = cam_y + (sy + 0.5) * scale
    for sx = sx0, sx1 do
      local wx = cam_x + (sx + 0.5) * scale
      local dx, dy = wx - b.x, wy - b.y
      local d2 = dx * dx + dy * dy
      if d2 <= b.r * b.r then
        local ch = (edge and d2 > ir2) and edge or fill
        S.put(px + sx, py + sy, "\u{2588}", ch)   -- 全块
      end
    end
  end
end

function draw()
  local C, S = phos.color, phos.screen
  local t = phos.lang.dict(Text)
  local px, py, pw, ph = S.playfield()
  local st = game:status()

  -- 相机的视距由**总质量**（等价半径）决定：分裂成两半时总质量不变 → 视角也不变；
  -- 只有真正吃大/变小才拉远/拉近，而且用指数逼近做成**平滑**变化
  local target = clamp(1 + st.size / 8, 1, 4)
  if not view_scale then view_scale, cam_wx, cam_wy = target, st.px, st.py end
  view_scale = approach(view_scale, target, 2.5, frame_dt)
  cam_wx = approach(cam_wx, st.px, 8, frame_dt)
  cam_wy = approach(cam_wy, st.py, 8, frame_dt)
  local scale = view_scale

  local vw, vh = pw * scale, ph * scale
  -- 允许相机越过世界边界一段（margin）：球贴墙时能看见自己探出去的那部分身体
  local margin = vw * 0.35
  local cam_x = clamp(cam_wx - vw / 2, -margin, Game.WORLD_W - vw + margin)
  local cam_y = clamp(cam_wy - vh / 2, -margin, Game.WORLD_H - vh + margin)
  local function to_sx(wx) return math.floor((wx - cam_x) / scale) end
  local function to_sy(wy) return math.floor((wy - cam_y) / scale) end

  S.clear()   -- 空格 + 色板默认底（随主题）

  -- 底纹：随世界走的稀疏点阵（世界坐标 5 的倍数）。**只画在世界里**——
  -- 相机可能越界看到"外面"，那里不该有点
  for wy = math.floor(cam_y / 5) * 5, cam_y + vh, 5 do
    local sy = to_sy(wy)
    if wy >= 0 and wy <= Game.WORLD_H and sy >= 0 and sy < ph then
      for wx = math.floor(cam_x / 5) * 5, cam_x + vw, 5 do
        local sx = to_sx(wx)
        if wx >= 0 and wx <= Game.WORLD_W and sx >= 0 and sx < pw then
          S.put(px + sx, py + sy, "\u{00B7}", C.dark_gray)
        end
      end
    end
  end

  for _, f in ipairs(game.food) do
    local sx, sy = to_sx(f.x), to_sy(f.y)
    if sx >= 0 and sx < pw and sy >= 0 and sy < ph then
      -- 吐出的食物：实心小球（●）；场上的普通食物：空心小圆（o）
      S.put(px + sx, py + sy, f.ej and "\u{25CF}" or "o", C.green)
    end
  end

  -- 刺球：按**自身半径**画成一颗大星（够大才吃得下，吃下强制分裂）
  local SR = Game.SPIKE_R
  for _, s in ipairs(game.spikes) do
    local sx0 = math.max(0, math.floor((s.x - SR - cam_x) / scale))
    local sx1 = math.min(pw - 1, math.ceil((s.x + SR - cam_x) / scale))
    local sy0 = math.max(0, math.floor((s.y - SR - cam_y) / scale))
    local sy1 = math.min(ph - 1, math.ceil((s.y + SR - cam_y) / scale))
    for sy = sy0, sy1 do
      local wy = cam_y + (sy + 0.5) * scale
      for sx = sx0, sx1 do
        local wx = cam_x + (sx + 0.5) * scale
        local dx, dy = wx - s.x, wy - s.y
        if dx * dx + dy * dy <= SR * SR then S.put(px + sx, py + sy, "*", C.orange) end
      end
    end
  end
  -- 吃刺球/吐食的闪烁余韵（动态）
  for _, bu in ipairs(game.bursts) do
    local sx, sy = to_sx(bu.x), to_sy(bu.y)
    if sx >= 0 and sx < pw and sy >= 0 and sy < ph then S.put(px + sx, py + sy, "+", C.yellow) end
  end

  -- 世界边界：贴到墙时沿**世界边缘**画一道粗线，让"墙"清晰可见
  local wall = C.gray
  local ex = to_sx(0)
  if ex >= 0 and ex < pw then for sy = 0, ph - 1 do S.put(px + ex, py + sy, "\u{2503}", wall) end end
  ex = to_sx(Game.WORLD_W)
  if ex >= 0 and ex < pw then for sy = 0, ph - 1 do S.put(px + ex, py + sy, "\u{2503}", wall) end end
  local ey = to_sy(0)
  if ey >= 0 and ey < ph then for sx = 0, pw - 1 do S.put(px + sx, py + ey, "\u{2501}", wall) end end
  ey = to_sy(Game.WORLD_H)
  if ey >= 0 and ey < ph then for sx = 0, pw - 1 do S.put(px + sx, py + ey, "\u{2501}", wall) end end

  -- 球按**从小到大**画：大球后画、压在小球之上；描边让相邻分身看得出分界
  local blobs = game:ranked()
  for i = #blobs, 1, -1 do
    local b = blobs[i]
    local col = (b.role == "player") and C.cyan or ai_colors[(b.hue - 1) % #ai_colors + 1]
    draw_blob(S, px, py, cam_x, cam_y, scale, pw, ph, b, col, C.black)
  end

  -- 玩家标记：标在**最大**的那个细胞上方；全灭后立即消失
  local cells = game:player_cells()
  local big = nil
  for _, c in ipairs(cells) do if not big or c.r > big.r then big = c end end
  if game.alive and big then
    S.print(px + to_sx(big.x) - 1, py + to_sy(big.y - big.r) - 1, t.me, C.white)
  end

  -- 顶部读数：体格（当前体型）/ 存活 / 名次（按"家"）/ 分身数 / 坐标
  local board = game:leaderboard()
  local rank, total = 1, #board
  for i, e in ipairs(board) do if e.owner == "p" then rank = i break end end
  S.print(px + 1, py, string.format("%s %d   %s %.1fs   #%d/%d   %s %d   (%d,%d)",
          t.score, math.floor(st.size * 20), t.time, st.time, rank, total,
          t.cells, st.cells, math.floor(st.px), math.floor(st.py)), C.white)

  if not game.alive then
    -- 阵亡浮窗：整块铺**实底**（取主题色板里的灰，随主题），连边框那圈一起盖住
    local bw, bh = 22, 5
    local sw, sh = S.size()
    local bx, by = math.floor((sw - bw) / 2), math.floor((sh - bh) / 2)
    local r = phos.ui.region(bx, by, bw, bh)
    r:clear(C.white, C.dark_gray)
    r:frame("")
    phos.ui.center_text(by + 1, st.won and t.won or t.over)
    phos.ui.center_text(by + 3, string.format(t.again, phos.input.key_name("a")))
  end

  Panel.draw(game, cart, best_score)
end

function debug_state()
  local st = game:status()
  st.view_scale = view_scale
  return st
end

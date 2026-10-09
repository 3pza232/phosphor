-- main.lua —— 总装配：模式菜单 + 两队虫子 + 瞄准发射 + 相机 + 回合流转 + AI
--
-- 分工（见 DESIGN.md 第 9 节）：玩法判断在各自模块里，这里只做三件事——
-- 把输入翻成"意图"、把模块串起来、把状态画出来。
-- 坐标一律是**子格**（1 字符格 = 2x2 子格），只有绘制前沿才换算成字符格。
--
-- 操作（对局中，按 K 会在画面中央弹出完整键位表）：
--   ←→ 走 / 蓄力时调力度      ↑↓ 调角度（按住可连调，最小 -60°）
--   A  进出蓄力状态（蓄力时走不动，再按一次退出、力度留着）
--   空格 按当前力度发射        X 下一件武器 / Z 上一件
--   B 跳跃                    , . 镜头左右平移（可看到视野外的敌人）

local Terrain = require("terrain")
local Camera = require("camera")
local Physics = require("physics")
local Worms = require("worms")
local Weapons = require("weapons")
local Turn = require("turn")
local AI = require("ai")
local Hud = require("hud")
local Panel = require("panel")
local Music = require("music")

-- 视口尺寸（字符格）。下面的默认值只在 refresh_view 取值之前用一下，
-- 真正生效的值来自 phos.screen.playfield()——**不能写死 80x45**：
-- 声明 22 格侧栏后内容区只有 58 格宽，画到 58 列之后的像素会被主机裁掉，
-- 世界右侧那一截就永远看不见（"最右边的敌人不见了"就是这么来的）
local VIEW_CW, VIEW_CH = 80, 45
local BYTE_ONE = string.byte("1")
-- 一个字符格四个子位的组合 → 象限字形（位：1 左上、2 右上、4 左下、8 右下）
local GLYPH = {
  " ", "▘", "▝", "▀", "▖", "▌", "▞", "▛",
  "▗", "▚", "▐", "▜", "▄", "▙", "▟", "█",
}
local HIT_R2 = Worms.HIT_RADIUS * Worms.HIT_RADIUS
local DEFAULT_POWER = 0.75          -- 开局力度：满力度也不是无敌，七成半正好上手
local ANGLE_MIN, ANGLE_MAX = -60, 180
local PANEL_W = 22                  -- manifest 里声明的侧栏宽度（菜单/键位浮板时临时收起）
local SKY_ROW = 30                  -- 天空背景（云、风痕、星）只画在这条线以上的空处

-- 调色板在 init 里建：卡带加载时 phos 还没装配完，模块顶层碰它不稳
local COL = {}
local SKIES = {}
local function build_palette()
  COL = {
    top = phos.color.rgb(52, 132, 72),      -- 地表：压暗过的绿，比纯绿耐看
    water = phos.color.rgb(26, 66, 130),
    spark = phos.color.rgb(255, 232, 150),
    smoke = phos.color.rgb(96, 96, 104),
    cloud = phos.color.rgb(96, 108, 132),
    star = phos.color.rgb(200, 208, 228),
    -- 「浮层底板」：凡是压在世界上、必须永远读得清的信息（虫标 / 血条 / 力度读数 /
    -- 伤害浮字 / K 浮窗）都垫这一块。底板不透明，所以脚下是土、是水、还是半格斜坡，
    -- 都不会出现"透明空洞"。世界内的东西（尘土、火花、云）保持透明，它们本来就属于地形层
    plate = phos.color.rgb(12, 16, 28),
  }
  -- 日夜更替：每回合换一档天色，四档循环（清晨 / 白天 / 黄昏 / 夜晚）
  SKIES = {
    phos.color.rgb(58, 48, 78),
    phos.color.rgb(32, 58, 100),
    phos.color.rgb(96, 50, 50),
    phos.color.rgb(14, 18, 42),
  }
end

local terrain, camera, worms, turn
local projectiles, floats, fx, fires, beams, clouds, stars
local active = {}                   -- active[team] = 当前操作的虫子
local aim_power, charge_mode, switch_delay, ai_delay, winner
local weapon_index, ai_plan
local cam = { x = 0, y = 0, hold = 0, focus = nil, pan = 0 }
local tp_info = {}                  -- 上一次传送搜索的实况（观察口用，见 fire_teleport）
local laser_dbg = {}                -- 光束每帧的位置与"离最近的敌虫多远"（观察口用）

local function spend_ammo(worm, weapon)
  if not worm.ammo then return end
  local n = worm.ammo[weapon.id]
  if n == nil or n < 0 then return end
  worm.ammo[weapon.id] = math.max(0, n - 1)
end
local flash = 0                      -- 闪烁计时（当前虫子的标记用它，不用主机时间）
local screen = "menu"               -- menu / play
local help_open = false
local pvp = false
local ally_ai = false               -- PVE：我方队友交给 AI
local menu = { row = 1, mode = "pve", mine = 4, theirs = 4, ally_ai = false }
local menu_flash = 0

local function pick_active(team, after)
  active[team] = worms:next_of_team(team, after)
  return active[team]
end

-- 菜单态下这局还没开始（turn/worms 都是 nil），所以这里必须容错：
-- 观察口与"是不是该我操作"都会在开局前问一遍，抛异常会让 agent 什么都看不到
local function current_worm() return turn and active[turn.team] or nil end
local function selected_weapon() return Weapons.LIST[weapon_index] end

-- 谁在操作这只虫：PVP 两边都是人；PVE 右队是 AI，左队默认全是人，
-- 打开"队友交给 AI"之后只有队长（第一个活着的）还归你
local function worm_is_human(w)
  if not w or not worms then return false end
  if pvp then return true end
  if w.team == 2 then return false end
  if not ally_ai then return true end
  return w == worms:of_team(1)[1]
end

local function human_turn() return worm_is_human(current_worm()) end

-- ---------- 特效 ----------

local function add_fx(x, y, r)
  local rad = math.max(2, r or 3)
  fx[#fx + 1] = { kind = "ring", x = x, y = y, r = rad, t = 0.35, life = 0.35 }
  -- 火星：炸开时朝四周飞出，受一点重力，画成亮点
  for _ = 1, 7 do
    local a = math.rad(phos.sys.random(0, 359))
    local sp = phos.sys.random(18, 52) / 10
    fx[#fx + 1] = { kind = "spark", x = x, y = y,
                    vx = math.cos(a) * sp, vy = math.sin(a) * sp - 2.0,
                    t = 0.5, life = 0.5 }
  end
  -- 烟：慢慢上飘、越飘越淡（用亮度变化表示"淡"，因为字只有一格）
  for _ = 1, 5 do
    fx[#fx + 1] = { kind = "smoke", x = x + phos.sys.random(-4, 4), y = y - phos.sys.random(0, 3),
                    vx = phos.sys.random(-10, 10) / 10, vy = -1.6,
                    t = 0.9, life = 0.9 }
  end
end

-- 伤害浮字：受击点上方冒出来。text 只在没有数字时用（落海、燃烧这类）
local function add_float(wx, wy, damage, text, color)
  local cx, cy = camera:cell_of(wx, wy)
  floats[#floats + 1] = { x = cx + 1, y = cy - 1, damage = damage, text = text, color = color, t = 1.2 }
end

-- ---------- 开局与菜单 ----------

-- 视口 = 本卡带真正能画的区域（侧栏已扣掉）。init 与开局各取一次
local function refresh_view()
  local _, _, pw, ph_ = phos.screen.playfield()
  if pw and pw > 8 and ph_ and ph_ > 8 then
    VIEW_CW, VIEW_CH = pw, ph_
  end
end

function init()
  build_palette()
  refresh_view()
  phos.audio.music(Music)          -- 轻缓欢快的循环 BGM（换卡时主机会自动停）
  screen, menu_flash, help_open = "menu", 0, false
  menu.row = 1
  phos.panel.resize(0)             -- 菜单不需要侧栏：留着那条竖线会压住浮窗
end

local function start_match()
  pvp = (menu.mode == "pvp")
  ally_ai = menu.ally_ai
  phos.panel.resize(PANEL_W)
  refresh_view()
  terrain = Terrain.new()
  camera = Camera.new(terrain.W, terrain.H, VIEW_CW * 2, VIEW_CH * 2)
  worms = Worms.new(terrain, { menu.mine, menu.theirs })
  turn = Turn.new()
  projectiles, floats, fx, fires, beams = {}, {}, {}, {}, {}
  aim_power, charge_mode, weapon_index, ai_plan = DEFAULT_POWER, false, 1, nil
  switch_delay, ai_delay, winner = nil, 1.2, nil
  active = {}
  -- 每只虫的默认力度由这里给（worms.lua 不做"手感"决定）
  for _, m in ipairs(worms.list) do m.power = DEFAULT_POWER end
  -- 云与星：云随回合缓慢漂移（速度还带一点风），星是固定的夜空
  clouds = {}
  for _ = 1, 8 do
    -- 云的高度要**相对地表**算：相机会一直盯着地上的虫子，视口顶也就到地表上方
    -- 二三十子格；按"世界绝对高度"撒云的话，云全落在视口上面，等于没有
    local cx0 = phos.sys.random(1, terrain.W)
    local surf = terrain.top[cx0] or 90
    clouds[#clouds + 1] = {
      x = cx0,
      y = math.max(6, surf - phos.sys.random(26, 54)),
      w = phos.sys.random(10, 26),
    }
  end
  stars = {}
  for _ = 1, 40 do
    stars[#stars + 1] = { x = phos.sys.random(0, terrain.W), y = phos.sys.random(1, SKY_ROW * 2 - 6) }
  end
  local w = pick_active(1)
  pick_active(2)
  if w then
    cam = { x = w.x, y = w.y, hold = 0, focus = nil, pan = 0 }
    camera:center(w.x, w.y)
  end
  screen = "play"
end

-- 菜单：模式 / 我方人数 / 敌方人数 / 队友 AI / 开始
local function menu_input()
  local rows = { 1, 2, 3, 4, 5 }
  if menu.mode == "pvp" then rows = { 1, 5 } end
  local function move(dir)
    local at = 1
    for i, r in ipairs(rows) do if r == menu.row then at = i end end
    at = ((at - 1 + dir) % #rows) + 1
    menu.row = rows[at]
    phos.audio.beep(420, 0.04, { wave = "square", volume = 0.14 })
  end
  if phos.input.pressed("up") then move(-1) end
  if phos.input.pressed("down") then move(1) end

  local step = 0
  if phos.input.pressed("left") then step = -1 end
  if phos.input.pressed("right") then step = 1 end
  if step ~= 0 then
    if menu.row == 1 then
      menu.mode = (menu.mode == "pve") and "pvp" or "pve"
      menu.row = 1
    elseif menu.row == 2 then
      menu.mine = math.max(1, math.min(8, menu.mine + step))
    elseif menu.row == 3 then
      menu.theirs = math.max(1, math.min(8, menu.theirs + step))
    elseif menu.row == 4 then
      menu.ally_ai = not menu.ally_ai
    end
    phos.audio.beep(520, 0.04, { wave = "square", volume = 0.14 })
  end

  -- A / ENTER：在"开始游戏"上开局，"队友交给 AI"上开关。
  -- 人数行不给 A 绑定动作：那两行要的是"选到再调"，多一个会误触的快捷键更麻烦
  if phos.input.pressed("a") or phos.input.pressed("start") then
    if menu.row == 5 then start_match()
    elseif menu.row == 4 then menu.ally_ai = not menu.ally_ai end
  end
end

-- ---------- 输入 → 意图 ----------

-- 换武器：跳过打光了的（弹药）与还在冷却的（回合）。一炮一个机会，不能浪费在
-- "选了也打不出去"的武器上；全都没得选时保持当前，让玩家看见原因
local function cycle_weapon(dir, w)
  local n = #Weapons.LIST
  for step = 1, n do
    local i = (weapon_index - 1 + dir * step) % n + 1
    local spec = Weapons.LIST[i]
    if Weapons.has_ammo(w, spec) and turn:ready(spec.id) then
      weapon_index = i
      phos.audio.beep(600, 0.04, { wave = "square", volume = 0.14 })
      return
    end
  end
end

-- 打光了就自动落回普通炮弹（无限），不然玩家会对着空武器反复按发射
local function ensure_weapon(w)
  local spec = selected_weapon()
  if spec and Weapons.has_ammo(w, spec) then return spec end
  weapon_index = 1
  return Weapons.LIST[1]
end

local function player_input(dt)
  local w = current_worm()
  if not w or not w.alive or turn.phase ~= "aim" or turn.shots_left <= 0 or winner then return end

  -- A：进出蓄力状态。蓄力时不走路——左右键专门用来调力度条，
  -- 这样"走到位再瞄"和"微调力度"是两个不会互相打架的动作
  if phos.input.pressed("a") then
    charge_mode = not charge_mode
    phos.audio.beep(charge_mode and 660 or 440, 0.05, { wave = "square", volume = 0.16 })
  end

  if phos.input.down("left") then
    if charge_mode then aim_power = math.max(0.1, aim_power - Physics.CHARGE_RATE * dt)
    else worms:move(w, -1, dt) end
  end
  if phos.input.down("right") then
    if charge_mode then aim_power = math.min(1.0, aim_power + Physics.CHARGE_RATE * dt)
    else worms:move(w, 1, dt) end
  end

  -- 角度：轻点 1°、按住连续走（1° 逐格点太慢）。下限 -60° 表示"朝下打"
  local ad = 0
  if phos.input.pressed("up") then ad = 1 end
  if phos.input.pressed("down") then ad = -1 end
  if phos.input.down("up") and not phos.input.pressed("up") then ad = 45 * dt end
  if phos.input.down("down") and not phos.input.pressed("down") then ad = -45 * dt end
  if ad ~= 0 then w.angle = math.max(ANGLE_MIN, math.min(ANGLE_MAX, w.angle + ad)) end

  if phos.input.pressed("b") then worms:jump(w) end
  if phos.input.pressed("x") then cycle_weapon(1, w) end
  if phos.input.pressed("z") then cycle_weapon(-1, w) end

  -- 空格：按当前力度发射
  if phos.input.pressed("space") then
    if fire(w, ensure_weapon(w)) then charge_mode = false end
  end
  w.power = aim_power
end

-- ---------- 命中判定 ----------

local function probe(x, y)
  -- 左右出界与地面以下都算撞上；**顶部不算** —— 天空是敞开的，
  -- 打太高就让它飞出去再落回来，不该在半空被凭空引爆
  if x < 1 or x > terrain.W or y > terrain.H then return "out" end
  if y < 1 then return nil end
  if terrain:solid(math.floor(x), math.floor(y)) then return "terrain" end
  if y >= terrain.WATER_Y then return "water" end
  for _, w in ipairs(worms.list) do
    if w.alive then
      local dx, dy = w.x - x, w.y - y
      if dx * dx + dy * dy <= HIT_R2 then return "worm", w end
    end
  end
  return nil
end

-- ---------- 开炮 ----------

-- 两条"当场结算"的路（定义在下面）：先声明，fire 才能引用它们
local fire_hitscan, fire_teleport

function fire(shooter, weapon)
  if not Weapons.has_ammo(shooter, weapon) then
    add_float(shooter.x, shooter.y, 0, "没弹药了", phos.color.orange)
    phos.audio.beep(120, 0.05, { wave = "square", volume = 0.16 })
    return false
  end
  if not turn:ready(weapon.id) then
    phos.audio.beep(120, 0.05, { wave = "square", volume = 0.16 })
    return false
  end
  shooter.power = aim_power

  local instant = false
  if weapon.kind == "utility" then
    if not fire_teleport(shooter, weapon) then
      add_float(shooter.x, shooter.y, 0, "无法传送", phos.color.orange)
      return false
    end
    instant = true
  elseif weapon.kind == "hitscan" then
    fire_hitscan(shooter, weapon)
    instant = true
  elseif weapon.kind == "laser" then
    -- 激光是一条**会飞的光束**：初速拉到很高、不受重力、不落不炸，
    -- 一路烧穿地形并伤到碰到的人，直到飞出地图边界（镜头一路跟着它）
    local a = math.rad(shooter.angle)
    local sp = weapon.speed or 900
    local p = Physics.new_projectile(shooter.x + shooter.facing * 3, shooter.y - 6,
                                     math.cos(a) * sp * shooter.facing, -math.sin(a) * sp,
                                     { no_gravity = true })
    p.weapon, p.shooter, p.trail, p.hit = weapon, shooter, {}, {}
    projectiles[#projectiles + 1] = p
  else
    local p = Weapons.fire(weapon, shooter)
    p.trail = {}
    projectiles[#projectiles + 1] = p
  end

  spend_ammo(shooter, weapon)
  turn:begin_shot()
  phos.audio.beep(180, 0.08, { wave = "square", sweep = 90, volume = 0.25 })
  if instant then
    turn:end_shot()
    switch_delay = 0.8
  end
  return true
end

-- 枪：把每一发都真的扫一遍。弹道带一点散布，否则六发全落在同一格，
-- 看起来像一发、也永远推不动人
function fire_hitscan(shooter, weapon)
  for i = 1, (weapon.shots or 1) do
    local deg = shooter.angle
    if i > 1 and (weapon.spread or 0) > 0 then
      deg = deg + phos.sys.random(-weapon.spread, weapon.spread)
    end
    local a = math.rad(deg)
    local dx, dy = math.cos(a) * shooter.facing, -math.sin(a)
    local ox, oy = shooter.x + shooter.facing * 3, shooter.y - 6
    local res = Physics.raycast(ox, oy, dx, dy, weapon.range or 60, probe)
    if res then
      beams[#beams + 1] = { x0 = ox, y0 = oy, x1 = res.x, y1 = res.y, t = 0.12, life = 0.12 }
      if res.kind == "worm" and res.point then
        worms:damage(res.point, weapon.damage)
        add_float(res.point.x, res.point.y, weapon.damage)
        if weapon.push then
          local p = res.point
          p.on_ground, p.fall_from, p.vy = false, p.y, -3
          p.x = p.x + (dx >= 0 and 1 or -1) * weapon.push * 0.4
        end
      elseif res.kind == "terrain" then
        -- 打在墙上：按 dig 挖个小坑，再按半径算**半步溅射**。
        -- 枪的伤害主要来自直击没错，但"擦着地皮打中脚边"完全没反馈，
        -- 用起来就像坏了——霰弹枪尤其明显
        if (weapon.dig or 0) > 0 then
          terrain:blast(math.floor(res.x), math.floor(res.y), weapon.dig)
        end
        local points = {}
        for _, w in ipairs(worms.list) do
          if w.alive then points[#points + 1] = w end
        end
        local hits = Physics.blast(res.x, res.y, weapon.radius or 1,
                                   (weapon.damage or 0) * 0.5, points, nil)
        for _, h in ipairs(hits) do
          worms:damage(h.point, h.damage)
          if h.damage >= 1 then add_float(h.point.x, h.point.y, h.damage) end
        end
        add_fx(res.x, res.y, (weapon.dig or 0) + 2)
      end
    end
  end
end

-- 传送：角度定方向、力度定距离，落点必须站得住。
-- 找不到落点时**要说出来**（浮字"无法传送"）——只"嘟"一声玩家会以为道具坏了
function fire_teleport(shooter, weapon)
  local a = math.rad(shooter.angle)
  local dx, dy = math.cos(a) * shooter.facing, -math.sin(a)
  local dist = 20 + Physics.speed_of(aim_power) * 3
  tp_info = { angle = shooter.angle, facing = shooter.facing, dist = math.floor(dist),
              bounds = "?", tried = 0, tx = 0, ty = 0, gx = -1, gy = -1 }
  for d = dist, 4, -4 do
    local tx, ty = math.floor(shooter.x + dx * d), math.floor(shooter.y + dy * d)
    tp_info.tried = tp_info.tried + 1
    tp_info.tx, tp_info.ty = tx, ty
    if tx > 2 and tx < terrain.W - 2 then
      -- 朝上瞄准时目标点会飞出世界顶部：夹回来再往下找地。
      -- 用 ground_below（向下），不是 find_ground（向上）——方向错了永远落不了地
      ty = math.max(3, math.min(ty, terrain.WATER_Y - 3))
      tp_info.bounds = "ok"
      local gx, gy = terrain:ground_below(tx, ty)
      tp_info.gx, tp_info.gy = gx or -1, gy or -1
      if gx and math.abs(gx - shooter.x) + math.abs(gy - shooter.y) > 3 then
        add_fx(shooter.x, shooter.y, 4)
        shooter.x, shooter.y = gx, gy
        shooter.on_ground, shooter.vy, shooter.fall_from = true, 0, nil
        add_fx(gx, gy, 4)
        return true
      end
    elseif tp_info.bounds == "?" then
      tp_info.bounds = string.format("越界 tx=%d ty=%d", tx, ty)
    end
  end
  return false
end

-- 弹药落地/引信到点：挖地形、按距离伤血、必要时分裂或留下火
local function resolve(p)
  local w = p.weapon or {}
  add_fx(p.x, p.y, w.radius)
  -- 镜头在爆炸处多停一会儿：立刻切回虫子会让人看不清"到底炸成什么样了"
  cam.focus, cam.hold = { p.x, p.y }, 1.3
  if (w.radius or 0) > 0 then
    local events = {}
    worms:apply_blast(p.x, p.y, w.radius, w.damage, events)
    for _, e in ipairs(events) do
      if e.damage and e.damage >= 1 then add_float(e.worm.x, e.worm.y, e.damage) end
    end
  end
  if w.burn then
    fires[#fires + 1] = { x = p.x, y = p.y, radius = w.radius or 3, life = w.burn }
    add_float(p.x, p.y, 0, "燃烧", phos.color.orange)
  end
  if w.splits then
    for _, q in ipairs(Weapons.split(w, p.x, p.y, w.splits - 1)) do
      q.trail = {}
      projectiles[#projectiles + 1] = q
    end
  end
  if phos.audio.available and phos.audio.available() then
    phos.audio.beep(90, 0.18, { wave = "noise", volume = 0.3, release = 0.12 })
  end
end

-- ---------- 回合流转 ----------

local function after_settle()
  if worms:team_wiped(1) then turn:finish(2) winner = 2 return end
  if worms:team_wiped(2) then turn:finish(1) winner = 1 return end
  -- 继承：刚开炮的这只虫把**力度 / 角度 / 朝向 / 选的弹药**全记在身上，
  -- 下次轮到它时原样恢复——每个人记得自己的手感，也省得每轮重新瞄一遍
  local fired = active[turn.team]
  if fired then
    -- 只记"这一炮实际用了多少力度、选的哪件武器"。角度与朝向瞄准时已经写在
    -- w 身上了，再赋一遍是自赋值，什么也不做
    fired.power, fired.weapon = aim_power, weapon_index
  end
  turn:next_team()
  -- 换到该队的**下一只活虫**。起点必须是**新换上的这一队自己**上一次上场的那只：
  -- 拿对面队伍的虫当起点的话永远匹配不到，结果每回合都回到第一只
  pick_active(turn.team, active[turn.team])
  -- 轮到谁就恢复谁上次的力度/朝向/弹药；第一轮用默认值
  local now = current_worm()
  aim_power, charge_mode = (now and now.power) or DEFAULT_POWER, false
  if now then
    weapon_index = now.weapon or weapon_index
  end
  cam.focus, cam.hold, cam.pan = nil, 0, 0
  ai_delay = 1.2
  ai_plan = nil
end

-- AI 这一炮能用的武器。四条纪律：
--   * 手里**还有那种弹药**（AI 与玩家共用同一本弹药账）
--   * 只列**预演算得准**的弹种：普通炮弹/火箭筒/手雷/集束都能被 physics 如实预演；
--     枪/激光是当场直线结算、传送是瞬移，塞进同一套预演只会算出假成绩
--   * 集束只在敌人扎堆时才有价值（5 次小爆炸，敌人分散就是浪费）
--   * 弹药有限，所以 AI 也得挑着用，不能一上来就把超级弹药砸光
local function ai_weapons(w)
  local out = {}
  for _, spec in ipairs(Weapons.LIST) do
    if Weapons.has_ammo(w, spec) then
      if spec.id == "shell" or spec.id == "bazooka" or spec.id == "grenade" then
        out[#out + 1] = spec.id
      elseif spec.id == "cluster" then
        -- 扎堆判断看的是**敌人**那边（AI 自己队伍挤不挤与它无关）
        local foe = (w.team == 1) and 2 or 1
        local mates = worms:of_team(foe)
        for _, e in ipairs(mates) do
          for _, o in ipairs(mates) do
            if e ~= o and math.abs(e.x - o.x) < 14 and math.abs(e.y - o.y) < 8 then
              out[#out + 1] = spec.id
              break
            end
          end
          if out[#out] == spec.id then break end
        end
      end
    end
  end
  return out
end

local function update_ai(dt)
  if turn.phase ~= "aim" or winner then return end
  ai_delay = ai_delay - dt
  if ai_delay > 0 then return end
  local w = current_worm()
  if not w or not w.alive then
    turn:next_team() pick_active(1) ai_delay = 1.2
    return
  end
  -- 先朝向最近的敌人，再让 AI 规划（同一份 physics 粗预演）
  local foe = (turn.team == 1) and 2 or 1
  local best, bestd = nil, 1e9
  for _, e in ipairs(worms:of_team(foe)) do
    local d = math.abs(e.x - w.x)
    if d < bestd then best, bestd = e, d end
  end
  if best then w.facing = (best.x >= w.x) and 1 or -1 end

  -- 规划是**分帧推进**的：一次算完几百组预演会触发主机的 100 毫秒看门狗
  if not ai_plan then
    local allowed = ai_weapons(w)
    ai_plan = AI.plan_begin(w, worms.list, terrain, turn.wind, "normal", allowed)
    if not ai_plan then
      turn:next_team() pick_active(1) ai_delay = 1.2
      return
    end
  end
  if not ai_plan:advance(AI.BATCH) then return end
  local plan = ai_plan:result()
  ai_plan = nil
  if plan then
    w.angle, aim_power = plan.angle, plan.power
    fire(w, plan.weapon)
  else
    turn:next_team() pick_active(1) ai_delay = 1.2
  end
end

-- ---------- 主循环 ----------

local function update_fires(dt)
  for i = #fires, 1, -1 do
    local f = fires[i]
    f.life = f.life - dt
    if f.life <= 0 then
      table.remove(fires, i)
    else
      for _, w in ipairs(worms.list) do
        if w.alive then
          local dx, dy = w.x - f.x, w.y - f.y
          if dx * dx + dy * dy <= f.radius * f.radius then
            worms:damage(w, Physics.BURN_DPS * dt)
          end
        end
      end
    end
  end
end

local function update_particles(dt)
  for i = #fx, 1, -1 do
    local f = fx[i]
    f.t = f.t - dt
    if f.t <= 0 then
      table.remove(fx, i)
    else
      if f.kind == "spark" then
        f.vy = f.vy + 26 * dt
        f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt
      elseif f.kind == "smoke" then
        f.x, f.y = f.x + f.vx * dt, f.y + f.vy * dt
      end
    end
  end
  -- 云随风漂移：风越大飘得越快，风向变了云也换方向
  for _, c in ipairs(clouds or {}) do
    c.x = c.x + (turn.wind * 1.6 + 3) * dt
    if c.x > terrain.W + 30 then c.x = -30 end
    if c.x < -30 then c.x = terrain.W + 30 end
  end
end

-- 镜头：跟弹药 → 爆炸后停留 → 再平滑回到当前虫子；, . 可以左右平移。
-- 平移**不设上限**（只受世界边缘约束），否则视野外的敌人永远看不到
local function update_camera(dt)
  if phos.input.down("comma") then cam.pan = cam.pan - 130 * dt end
  if phos.input.down("period") then cam.pan = cam.pan + 130 * dt end
  if cam.hold > 0 then cam.hold = cam.hold - dt end

  local p = projectiles[1]
  local tx, ty
  if p then
    tx, ty = p.x, p.y
  elseif cam.hold > 0 and cam.focus then
    tx, ty = cam.focus[1], cam.focus[2]
  else
    local w = current_worm()
    if w and w.alive then tx, ty = w.x, w.y end
  end
  if tx then
    local k = 1 - math.exp(-dt * 6)
    cam.x, cam.y = cam.x + (tx - cam.x) * k, cam.y + (ty - cam.y) * k
  end
  camera:center(cam.x + cam.pan, cam.y)
end

function update(dt)
  flash = flash + dt
  if phos.input.pressed("k") then
    help_open = not help_open
    phos.audio.paused(help_open)     -- 看键位表时连音乐一起停
    phos.panel.resize(help_open and 0 or PANEL_W)
  end
  if screen == "menu" then
    menu_flash = menu_flash + dt
    menu_input()
    return
  end
  if winner then
    if phos.input.pressed("start") or phos.input.pressed("a") then
      screen = "menu"
      menu_flash = 0
      phos.panel.resize(0)
    end
    return
  end
  if help_open then return end    -- 键位表打开时整局暂停

  if human_turn() then player_input(dt) else update_ai(dt) end

  for i = #projectiles, 1, -1 do
    local p = projectiles[i]
    if p.weapon.kind == "track" then
      local best, bestd = nil, 1e9
      local my_team = p.shooter and p.shooter.team or 0
      for _, w in ipairs(worms.list) do
        if w.alive and w.team ~= my_team then
          local d = (w.x - p.x) ^ 2 + (w.y - p.y) ^ 2
          if d < bestd then best, bestd = w, d end
        end
      end
      if best then Weapons.steer(p, best, dt) end
    end
    if p.weapon.kind == "laser" then
      -- 光束每帧从上一处烧到当前处（不采样会留下断点），沿途伤到人；
      -- 只在地图边界停下——所以不能再走 probe（那会在撞到地形/人时就断）
      local px, py = p.x, p.y
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      local steps = math.max(1, math.floor((math.abs(p.vx) + math.abs(p.vy)) * dt / 2))
      for s = 1, steps do
        local k = s / steps
        local bx, by = px + (p.x - px) * k, py + (p.y - py) * k
        Physics.blast(bx, by, p.weapon.width or 1, 0, {}, terrain)
        for _, w in ipairs(worms.list) do
          -- 判定是**躯体胶囊**：虫子从脚下往上约 9 子格都算被打到。
          -- 每只虫对同一条光束**只伤一次**——光束每帧都在扫，
          -- 不加这条的话一束光就把人打成筛子
          if w.alive and not p.hit[w]
             and math.abs(w.x - bx) < 2.5 and by >= w.y - 9 and by <= w.y + 1 then
            p.hit[w] = true
            worms:damage(w, p.weapon.damage)
            add_float(w.x, w.y, p.weapon.damage)
          end
        end
      end
      -- 观测用：记下光束位置与最近的敌虫（判定对不对要拿这两个数说话）
      local nf, nd = nil, 1e9
      for _, w in ipairs(worms.list) do
        if w.alive and w.team ~= (p.shooter and p.shooter.team or 0) then
          local d = math.abs(w.x - p.x)
          if d < nd then nf, nd = w, d end
        end
      end
      local nh = 0
      for _ in pairs(p.hit) do nh = nh + 1 end
      laser_dbg = { x = math.floor(p.x), y = math.floor(p.y),
                    fx = nf and math.floor(nf.x) or -1, fy = nf and math.floor(nf.y) or -1,
                    dx = math.floor(nd), hits = nh }
      if p.x < 1 or p.x > terrain.W or p.y < 1 or p.y > terrain.H then
        resolve(p)
        table.remove(projectiles, i)
        if #projectiles == 0 then turn:end_shot() switch_delay = 0.8 end
      end
      local last = p.trail[#p.trail]
      if not last or (p.x - last[1]) ^ 2 + (p.y - last[2]) ^ 2 > 16 then
        p.trail[#p.trail + 1] = { p.x, p.y }
        if #p.trail > 90 then table.remove(p.trail, 1) end
      end
    else
    local result = Physics.step(p, dt, turn.wind, probe)
    local last = p.trail[#p.trail]
    if not last or (p.x - last[1]) ^ 2 + (p.y - last[2]) ^ 2 > 16 then
      p.trail[#p.trail + 1] = { p.x, p.y }
      if #p.trail > 60 then table.remove(p.trail, 1) end
    end
    if result then
      resolve(p)
      table.remove(projectiles, i)
      if #projectiles == 0 then
        turn:end_shot()
        switch_delay = 0.8
      end
    end
    end
  end

  local events = worms:update(dt)
  for _, e in ipairs(events) do
    if e.kind == "drowned" then
      add_float(e.worm.x, e.worm.y, 0, "落海", phos.color.blue)
    elseif e.kind == "landed" then
      add_float(e.worm.x, e.worm.y, e.damage, nil, phos.color.orange)
    end
  end

  update_fires(dt)
  update_particles(dt)

  for i = #floats, 1, -1 do
    floats[i].t = floats[i].t - dt
    if floats[i].t <= 0 then table.remove(floats, i) end
  end
  for i = #beams, 1, -1 do
    beams[i].t = beams[i].t - dt
    if beams[i].t <= 0 then table.remove(beams, i) end
  end

  -- 弹药结算后的换手延迟：必须**与阶段无关**地倒数
  if switch_delay and not winner then
    switch_delay = switch_delay - dt
    if switch_delay <= 0 then
      switch_delay = nil
      after_settle()
    end
  end

  if turn.phase == "aim" and not winner and not switch_delay and #projectiles == 0 then
    local t = turn:tick(dt)
    if t.timeout then after_settle() end
  end

  update_camera(dt)
end

-- ---------- 绘制 ----------

local function in_view(i, j)
  return i >= 0 and i < VIEW_CW and j >= 0 and j < VIEW_CH
end

-- 屏幕格直接画（天空层的云与风痕自己就按格算）
local function put_at_raw(S, i, j, ch, col)
  if in_view(i, j) then S.put(i, j, ch, col) end
end

-- 世界坐标（子格）画一格
local function put_at(S, wx, wy, ch, col)
  local i, j = camera:cell_of(wx, wy)
  if in_view(i, j) then S.put(i, j, ch, col) return true end
  return false
end

-- 天空：天色随回合在四档之间循环，云与星只画在地形之前——
-- 于是它们天然只会出现在山坡上方的空处，不必逐格判断
local function draw_sky(S, C)
  local cx, cy = camera:origin()
  local sky = SKIES[((turn.round - 1) % #SKIES) + 1] or SKIES[2]
  S.clear(nil, sky)
  local night = (((turn.round - 1) % #SKIES) + 1) == #SKIES
  if night then
    for _, s in ipairs(stars or {}) do
      put_at_raw(S, math.floor((s.x - cx) / 2), math.floor((s.y - cy) / 2), "·", COL.star)
    end
  end
  for _, c in ipairs(clouds or {}) do
    local i = math.floor((c.x - cx) / 2)
    local j = math.floor((c.y - cy) / 2)
    if i > -24 and i < VIEW_CW then
      for k = 0, math.floor(c.w / 2) do
        if in_view(i + k, j) then S.put(i + k, j, "~", COL.cloud) end
        if in_view(i + k, j + 1) and (k % 3 ~= 1) then S.put(i + k, j + 1, "~", COL.cloud) end
      end
    end
  end
  -- 风大时给几道走向痕迹：风是真正影响弹道的东西，画面该把它说出来
  if math.abs(turn.wind) >= 4 then
    local dir = (turn.wind > 0) and 1 or -1
    for k = 0, 5 do
      local x = math.floor((flash * 70 * dir + k * 41) % (VIEW_CW - 6)) + 3
      local y = 4 + k * 4
      put_at_raw(S, x, y, dir > 0 and "`" or "'", COL.cloud)
    end
  end
end

local function draw_world(S, C)
  local cx, cy = camera:origin()
  local rows = terrain.rows
  for j = 0, VIEW_CH - 1 do
    local y0 = cy + 2 * j + 1
    local r0, r1 = rows[y0], rows[y0 + 1]
    local water = y0 >= terrain.WATER_Y
    -- 深处逐格变暗：整屏一个颜色太单调，硬造一条分界线又会留下接缝，
    -- 所以按行做**连续**过渡（同一条渐变，看不出台阶）
    local t = math.max(0, math.min(1, (terrain.WATER_Y - y0) / (terrain.WATER_Y - 30)))
    -- 底色压暗过：纯"草绿"在整屏占比这么大时太亮太跳，白字压上去反而看不清
    local col = C.rgb(math.floor(18 + t * 26), math.floor(52 + t * 62), math.floor(32 + t * 34))
    for i = 0, VIEW_CW - 1 do
      local x = cx + 2 * i + 1
      local bits = 0
      if r0 then
        if r0:byte(x) == BYTE_ONE then bits = bits + 1 end
        if r0:byte(x + 1) == BYTE_ONE then bits = bits + 2 end
      end
      if r1 then
        if r1:byte(x) == BYTE_ONE then bits = bits + 4 end
        if r1:byte(x + 1) == BYTE_ONE then bits = bits + 8 end
      end
      if bits > 0 then
        -- bits == 15 表示这一格的四个半格**全是土**：把底色也设成土色。
        -- 只设前景色的话，这格登记的底色仍然是天空色；之后在它上面画只写字形、
        -- 不动背景的字（血条、浮字、力度读数），天空色就被镶进土里，
        -- 看上去像地形被"镂"掉一块。**地形是底图，底图必须把底色也占住**。
        -- 只填满格而不填半格：地表那圈半格要留出天空，否则轮廓会变方
        if bits == 15 then
          S.fill(i, j, 1, 1, " ", col, col)
        else
          S.put(i, j, GLYPH[bits + 1], col)
        end
      elseif water then
        S.put(i, j, "≈", COL.water)
      end
    end
  end
end

local function draw_effects(S, C)
  for _, f in ipairs(fx) do
    local k = 1 - f.t / f.life                 -- 0 生 → 1 灭
    if f.kind == "ring" then
      local r = f.r * (0.35 + 0.85 * k)
      local col = (k > 0.66) and C.red or (k > 0.33 and C.orange or COL.spark)
      for a = 0, 15 do
        local ang = a * math.pi / 8
        put_at(S, f.x + math.cos(ang) * r, f.y + math.sin(ang) * r, "*", col)
      end
    elseif f.kind == "spark" then
      -- 前半程是亮点，后半程变成被掀起来的土块，落回地面色
      put_at(S, f.x, f.y, (k > 0.5) and "*" or "#",
             (k > 0.5) and COL.spark or COL.top)
    else
      put_at(S, f.x, f.y, "·", COL.smoke)
    end
  end
  for _, b in ipairs(beams) do
    local dx, dy = b.x1 - b.x0, b.y1 - b.y0
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0.5 then
      local ux, uy = dx / len, dy / len
      local n = math.floor(len / 2)
      for s = 0, n do
        put_at(S, b.x0 + ux * s * 2, b.y0 + uy * s * 2,
               b.laser and "=" or "-", b.laser and C.cyan or C.white)
      end
    end
  end
  for _, f in ipairs(fires) do
    for d = -f.radius, f.radius, 2 do
      put_at(S, f.x + d, f.y, "~", C.orange)
    end
  end
  for _, p in ipairs(projectiles) do
    for _, pt in ipairs(p.trail) do
      -- 轨迹点用灰白而不是深灰：深灰压在深色地形上像一条黑底带
      put_at(S, pt[1], pt[2], "·", C.gray)
    end
  end
end

-- 角度线：从炮口沿着瞄准方向点一条虚线，长度随力度长。
-- 它**只是一条直线**，不是弹道预测——角度看得清、落点还得自己算（DESIGN 第 7 节）
local function draw_aim(S, C)
  local w = current_worm()
  if not w or not w.alive or winner or not human_turn() then return end
  if turn.phase ~= "aim" then return end
  local a = math.rad(w.angle)
  local ux, uy = math.cos(a) * w.facing, -math.sin(a)
  local ox, oy = w.x + w.facing * 3, w.y - 6
  local col = charge_mode and C.yellow or C.orange
  local len = 12 + aim_power * 96
  local n = math.floor(len / 3)
  for i = 1, n do
    if i % 2 == 1 then
      put_at(S, ox + ux * i * 3, oy + uy * i * 3, "·", col)
    end
  end
  put_at(S, ox + ux * len, oy + uy * len, w.facing > 0 and ">" or "<", col)

  -- 读数贴在虫子旁边并用底色垫住：角度与力度必须是"扫一眼就知道"的东西
  local i, j = camera:cell_of(w.x, w.y - 1)
  local bar_w = 14
  local filled = math.floor(aim_power * bar_w + 0.5)
  local spec = selected_weapon()
  local left = spec and (w.ammo[spec.id] or 0) or 0
  local ammo_txt = (left < 0) and "∞" or tostring(left)
  local label = string.format(" %4d° %3d%%  x%s ", math.floor(w.angle + 0.5),
                              math.floor(aim_power * 100 + 0.5), ammo_txt)
  local bar = " [" .. string.rep("#", filled) .. string.rep(".", bar_w - filled) .. "] "
  local lx = math.max(0, math.min(VIEW_CW - #bar - 1, i - 7))
  local ly = math.min(VIEW_CH - 2, j + 2)
  -- 读数与力度条垫**同一块底板**：它们是浮层，不该被脚下的地形切成碎片
  S.print(lx, ly, label, charge_mode and C.yellow or C.white, COL.plate)
  S.print(lx, ly + 1, bar, charge_mode and C.yellow or C.green, COL.plate)
end

local function draw_actors(S, C)
  for _, w in ipairs(worms.list) do
    if w.alive then
      -- 画在**脚上方那一格**：地形占着脚下那格的下一半，画在原格会看到
      -- '@' 陷在 '#' 里；抬高半格就正好站在地表上
      local i, j = camera:cell_of(w.x, w.y - 1)
      if in_view(i, j) then
        local col
        if w.team == 1 then
          col = (pvp or turn.team == 1) and C.yellow or C.orange
        else
          col = (pvp or turn.team == 2) and C.red or C.purple
        end
        -- 虫标、选标、血条全部垫底板：它们都是"浮层"，画在世界上而不是地形里，
        -- 站在斜坡或水里时也不会把地形顶出缺口
        S.put(i, j, "@", col, COL.plate)
        -- 标记只画在"轮到人"的那只虫上：队友交给 AI 时，标识不该跟着跳过去
        if w == current_worm() and human_turn() then
          local blink = (math.floor(flash * 4) % 2 == 0)
          S.put(i, j - 1, blink and "V" or "^", C.white, COL.plate)
          for d = -1, 1 do
            if in_view(i + d, j + 1) then S.put(i + d, j + 1, "=", C.white, COL.plate) end
          end
        end
        Hud.hp_bar(S, C, i, j - 2, w.hp, COL.plate)
      end
    end
  end
  for _, p in ipairs(projectiles) do
    put_at(S, p.x, p.y, "*", C.white)
  end
end

-- 画一个"只写字形、不动背景"的框：边线斜角用 + 补齐（浮窗 API 的标题会让
-- 右上角缺一段，而且它自带不透明底），所以这里自己画
local function box(S, C, x, y, w, h, title, tone)
  for i = 1, w do
    S.put(x + i - 1, y, "-", tone)
    S.put(x + i - 1, y + h - 1, "-", tone)
  end
  for j = 1, h do
    S.put(x, y + j - 1, "|", tone)
    S.put(x + w - 1, y + j - 1, "|", tone)
  end
  S.put(x, y, "+", tone)
  S.put(x + w - 1, y, "+", tone)
  S.put(x, y + h - 1, "+", tone)
  S.put(x + w - 1, y + h - 1, "+", tone)
  -- 标题是"需要强调"的字样之一：给它一块底色，压在边框上才清楚（同一块浮层底板）
  if title then
    S.print(x + 2, y, " " .. title .. " ", tone, COL.plate)
  end
end

-- 键位浮板：按 K 弹出来，居中在本卡带的可玩区里（不压到侧栏）
local function draw_help(C, S)
  local px, py, pw, ph_ = phos.screen.playfield()
  local w, h = math.min(56, pw - 2), 22
  local x = px + math.floor((pw - w) / 2)
  local y = py + math.floor((ph_ - h) / 2)
  -- 浮窗要**整块不透明**：只在文字处涂底的话，空白处会透出后面的战况，糊成一片
  S.fill(x + 1, y + 1, w - 2, h - 2, " ", nil, COL.plate)
  box(S, C, x, y, w, h, "键位说明（K 关闭）", C.white)
  S.print(x + 2, y + 1, "对局中", C.yellow)
  -- 键名一律用**短标签**（中文两个字最好）：主机把 ASCII 也按全宽渲染，
  -- 写 "ENTER" 就等于占十格，会顶到说明列上
  local lines = {
    { "←→", "走路；蓄力时调力度" },
    { "↑↓", "调角度（可到 -60° 朝下）" },
    { "A", "进出蓄力状态（力度保留）" },
    { "空格", "按当前力度发射" },
    { "X Z", "下一件 / 上一件武器" },
    { "B", "跳跃" },
    { ", .", "镜头左右平移" },
    { "K", "开关这张表（暂停）" },
    { "回车", "结算后回菜单" },
    { "Esc", "返回卡带架" },
  }
  for i, line in ipairs(lines) do
    S.print(x + 3, y + 2 + i, line[1], C.white)
    S.print(x + 13, y + 2 + i, phos.text.fit(line[2], w - 15), C.gray)
  end
end

local function draw_menu()
  local C, S = phos.color, phos.screen
  -- 不刷底色：主机每帧已经把内容区填成**当前主题的底色**（还带显像管效果），
  -- 卡带再自己刷一层就会盖掉主题设置——之前那块蓝就是这么来的
  S.print(2, 1, "WORMS", C.yellow)
  S.print(2, 2, "回合制炮击 · 用有限弹药把对面轰进海里", C.gray)

  local px, py, pw, ph_ = phos.screen.playfield()
  local w, h = math.min(46, pw - 2), 15
  local x = px + math.floor((pw - w) / 2) + 2
  local y = py + math.floor((ph_ - h) / 2) + 1
  box(S, C, x - 1, y - 1, w, h, "选择模式", C.white)
  local mark = function(row) return (menu.row == row) and ">" or " " end
  local hi = function(row) return (menu.row == row) and C.white or C.gray end

  if menu.mode == "pve" then
    S.print(x, y, string.format("%s 模式        < PVE 人机对战 >", mark(1)), hi(1))
    S.print(x, y + 2, string.format("%s 我方人数    < %d >", mark(2), menu.mine), hi(2))
    S.print(x, y + 3, string.format("%s 敌方人数    < %d >", mark(3), menu.theirs), hi(3))
    S.print(x, y + 5, string.format("%s 队友交给 AI < %s >",
                                    mark(4), menu.ally_ai and "是" or "否"), hi(4))
    S.print(x, y + 6, menu.ally_ai and "   你只操作队长，其余队友由电脑指挥"
                                     or "   所有队友都由你自己操作", C.dark_gray)
  else
    S.print(x, y, string.format("%s 模式        < PVP 同机对战 >", mark(1)), hi(1))
    S.print(x, y + 2, "   两人轮流操作同一台机器：一方打完换另一方", C.dark_gray)
    S.print(x, y + 3, "   左队黄、右队红，各 4 人", C.dark_gray)
  end
  S.print(x, y + 9, string.format("%s 开始游戏", mark(5)),
          (menu.row == 5) and C.yellow or C.gray)
  S.print(x + 2, y + 11, "↑↓ 选择   ←→ 调整   A / ENTER 确定", C.dark_gray)
end

function draw()
  local C, S = phos.color, phos.screen
  if screen == "menu" then
    draw_menu()
    return
  end
  draw_sky(S, C)
  draw_world(S, C)
  draw_effects(S, C)
  draw_actors(S, C)
  -- 瞄准线、预测线、力度读数只在"轮到我、还没开炮"时出现：一发射立刻收掉，
  -- 免得玩家盯着上一炮的刻度去瞄下一炮
  if turn.phase == "aim" and human_turn() and not winner then draw_aim(S, C) end

  local w = current_worm()
  local weapon = selected_weapon()
  local left = (weapon and w and w.ammo[weapon.id]) or 0
  Hud.draw(S, C, {
    worm = w, wind = turn.wind, time_text = turn:time_text(), round = turn.round,
    phase = turn.phase, shots_left = turn.shots_left,
    weapon = weapon, plate = COL.plate,
    ammo = left, charge = charge_mode, pvp = pvp, turn_team = turn.team,
    ally_ai = ally_ai, human = human_turn(),
    floats = floats, flight_note = turn.phase == "flying" and "弹药飞行中" or nil,
  })

  if winner then
    local msg = (winner == 1) and "左队胜利   按 ENTER 回菜单" or "右队胜利   按 ENTER 回菜单"
    S.print(VIEW_CW // 2 - #msg // 2, VIEW_CH // 2, msg, C.white, phos.color.black)
  end

  Panel.draw(terrain, camera, worms, turn, Weapons.LIST, weapon, pvp, w, human_turn())
  if help_open then draw_help(C, S) end
end

-- agent / 自测观察口。
-- 注意：菜单态下这局还没开始，projectiles 之类的容器都还是 nil，
-- 所以一律用 `(x or {})` 取值——观察口自己抛异常，agent 就什么都看不到了
function debug_state()
  local w = current_worm()
  local list = (worms and worms.list) or {}
  local spec = selected_weapon()
  local out = {
    screen = screen, pvp = pvp, ally_ai = ally_ai, help = help_open,
    mine = menu.mine, theirs = menu.theirs, menu_row = menu.row,
    team = turn and turn.team or 0, phase = turn and turn.phase or "-",
    wind = turn and turn.wind or 0, round = turn and turn.round or 0,
    shots_left = turn and turn.shots_left or 0, winner = winner,
    alive1 = worms and worms:alive_count(1) or 0, alive2 = worms and worms:alive_count(2) or 0,
    projectiles = #(projectiles or {}), fires = #(fires or {}), beams = #(beams or {}),
    charge = charge_mode, cam_x = math.floor(cam.x), cam_pan = math.floor(cam.pan),
    tp_angle = tp_info.angle or 0, tp_facing = tp_info.facing or 0, tp_dist = tp_info.dist or 0,
    tp_tried = tp_info.tried or 0, tp_bounds = tp_info.bounds or "-",
    tp_tx = tp_info.tx or 0, tp_ty = tp_info.ty or 0,
    tp_gx = tp_info.gx or -1, tp_gy = tp_info.gy or -1,
    lg_x = laser_dbg.x or 0, lg_y = laser_dbg.y or 0,
    lg_fx = laser_dbg.fx or -1, lg_fy = laser_dbg.fy or -1,
    lg_dx = laser_dbg.dx or -1, lg_hits = laser_dbg.hits or 0,
    weapon = spec and spec.id or "",
    ammo = (spec and w and w.ammo and w.ammo[spec.id]) or 0,
    human = human_turn(),
  }
  if w then
    out.worm_x, out.worm_y = math.floor(w.x), math.floor(w.y)
    out.angle, out.power, out.hp = math.floor(w.angle), math.floor(aim_power * 100), math.floor(w.hp)
    out.worm_team = w.team
    for i, m in ipairs(list) do
      if m == w then out.worm_id = i end
    end
  end
  out.hp1, out.hp2 = {}, {}
  for _, m in ipairs(list) do
    local side = (m.team == 1) and out.hp1 or out.hp2
    side[#side + 1] = m.alive and math.floor(m.hp) or -1
  end
  -- 每只虫的坐标：世界宽高 + 各队 x 范围。
  -- "某个单位在地图外/看不见"这类问题，有这两个数就不用猜了
  out.world_w, out.world_h = terrain and terrain.W or 0, terrain and terrain.H or 0
  local x1min, x1max, x2min, x2max = 1e9, -1e9, 1e9, -1e9
  for _, m in ipairs(list) do
    if m.team == 1 then
      x1min, x1max = math.min(x1min, m.x), math.max(x1max, m.x)
    else
      x2min, x2max = math.min(x2min, m.x), math.max(x2max, m.x)
    end
  end
  out.x1 = (x1min > 1e8) and -1 or math.floor(x1min)
  out.x2 = (x1max < -1e8) and -1 or math.floor(x1max)
  out.y1 = (x2min > 1e8) and -1 or math.floor(x2min)
  out.y2 = (x2max < -1e8) and -1 or math.floor(x2max)
  return out
end

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
-- 瞄准线的采样：AIM_STEP_SUB 子格走一步（正好 1 字符格）；
-- 前 AIM_NEAR_SUB 子格算"近身段"，逐格点，让炮口朝向看得准
local AIM_STEP_SUB, AIM_NEAR_SUB = 2, 24

-- 瞄准手感：**点一下走 1 格，按住越走越快**。点按负责精准、长按负责跨度，
-- 两者共用一个键；加速在 RAMP_T 秒内从 RATE 升到 RATE_MAX（线性）
local TAP_POWER = 0.01              -- 力度：点一下 1%
local POWER_RATE, POWER_RATE_MAX = 0.10, 0.80
local TAP_ANGLE = 1                 -- 角度：点一下 1°
local ANGLE_RATE, ANGLE_RATE_MAX = 6, 55
local RAMP_T = 0.9                  -- 从"慢"加到"快"所用时间（秒）

-- 长按加速：t 秒内从 base 线性升到 top。单位随调用处（力度/秒、度/秒、血/秒）
local function accel(t, base, top)
  return base + (top - base) * math.min(1, t / RAMP_T)
end
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
local burst = nil                   -- 点射队列（机枪）：每 burst 秒出一发，全打完才算这一炮结束
local strikes = {}                  -- 天基炮：等待中的落点与正在释放的光柱
local active = {}                   -- active[team] = 当前操作的虫子
local aim_power, charge_mode, switch_delay, ai_delay, winner
local weapon_index, ai_plan
local hold_angle, hold_power = 0, 0    -- 按住时长：驱动"越按越快"的加速度
local ai_decided, ai_walk_t = false, 0 -- AI 本回合是否已决定走位 / 还要走多久（秒）
local ai_reason, ai_run_away = nil, false  -- 走位理由（观察口用）/ 是否在往后撤
local ai_repositioned = false              -- 本回合是否已经为"够不着"换过一次位置
local ai_last = "-"                        -- 上一次 AI 的决策摘要（观察口用）
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
local map_open = false              -- M：地图总览（不暂停）
local pvp = false
local ally_ai = false               -- PVE：我方队友交给 AI
-- 难度档位：顺序即菜单里左右键的顺序，diff 存的是下标
local DIFFS = { "easy", "normal", "hard" }
local DIFF_LABEL = {
  zh = { easy = "简单", normal = "普通", hard = "困难" },
  en = { easy = "EASY", normal = "NORMAL", hard = "HARD" },
}
-- 生命值那一行：上下限与步长。长按的速率是"每秒多少点"，最后统一取整成 10 的倍数
local HP_MIN, HP_MAX, HP_STEP = 10, 800, 10
local HP_RATE, HP_RATE_MAX = 30, 240

local menu = { row = 1, mode = "pve", mine = 4, theirs = 4, ally_ai = false, diff = 2, hp = 100 }
local menu_flash = 0
local hp_hold, hp_frac = 0, 0        -- 菜单里按住 ←→ 的累计时长 / 不足一步的余量

-- 血量只能落在 10 的倍数上：点按、长按加速、上下限夹取全走这一个入口
local function set_menu_hp(v)
  menu.hp = math.max(HP_MIN, math.min(HP_MAX, v - v % HP_STEP))
end

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
  -- 血量上限由菜单决定，必须在造虫子**之前**设好：每只虫的初始血量取自它
  Worms.MAX_HP = menu.hp
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

-- 菜单：模式 / 我方人数 / 敌方人数 / 生命值 / 队友 AI / 难度 / 开始
local function menu_input(dt)
  local rows = { 1, 2, 3, 4, 5, 6, 7 }       -- 7 = 开始游戏；PVP 没有人数、队友与难度
  if menu.mode == "pvp" then rows = { 1, 4, 7 } end
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
      set_menu_hp(menu.hp + step * HP_STEP)
    elseif menu.row == 5 then
      menu.ally_ai = not menu.ally_ai
    elseif menu.row == 6 then
      menu.diff = ((menu.diff - 1 + step) % #DIFFS) + 1
    end
    phos.audio.beep(520, 0.04, { wave = "square", volume = 0.14 })
  end

  -- 生命值那一行：点一下 10 点，**按住**则越快越快（与炮弹蓄力同一套加速曲线）。
  -- 累成整步再加，所以无论按多快，血量永远是 10 的倍数
  if menu.row == 4 then
    local dir = phos.input.down("left") and -1 or (phos.input.down("right") and 1 or 0)
    hp_hold = (dir ~= 0) and (hp_hold + dt) or 0
    if dir ~= 0 and not phos.input.pressed("left") and not phos.input.pressed("right") then
      hp_frac = hp_frac + accel(hp_hold, HP_RATE, HP_RATE_MAX) * dt
      local steps = math.floor(hp_frac / HP_STEP)
      if steps > 0 then
        hp_frac = hp_frac - steps * HP_STEP
        set_menu_hp(menu.hp + dir * steps * HP_STEP)
      end
    end
  else
    hp_hold, hp_frac = 0, 0
  end

  -- A / ENTER：在"开始游戏"上开局，"队友交给 AI"上开关。
  -- 人数、生命值、难度行不给 A 绑定动作：那几行要的是"选到再调"，多一个会误触的快捷键更麻烦
  if phos.input.pressed("a") or phos.input.pressed("start") then
    if menu.row == 7 then start_match()
    elseif menu.row == 5 then menu.ally_ai = not menu.ally_ai end
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

  -- 左右：蓄力态调力度（点按 1%、长按加速），非蓄力态走路
  local left, right = phos.input.down("left"), phos.input.down("right")
  hold_power = (left or right) and (hold_power + dt) or 0
  if charge_mode then
    local rate = accel(hold_power, POWER_RATE, POWER_RATE_MAX)
    if phos.input.pressed("left") then aim_power = math.max(0.1, aim_power - TAP_POWER)
    elseif phos.input.pressed("right") then aim_power = math.min(1.0, aim_power + TAP_POWER)
    elseif left then aim_power = math.max(0.1, aim_power - rate * dt)
    elseif right then aim_power = math.min(1.0, aim_power + rate * dt) end
  else
    if left then worms:move(w, -1, dt) end
    if right then worms:move(w, 1, dt) end
  end

  -- 上下：点按 1°、长按越走越快。下限 -60° 表示"朝下打"
  local up, down = phos.input.down("up"), phos.input.down("down")
  hold_angle = (up or down) and (hold_angle + dt) or 0
  local ad = 0
  if phos.input.pressed("up") then ad = TAP_ANGLE
  elseif phos.input.pressed("down") then ad = -TAP_ANGLE
  elseif up then ad = accel(hold_angle, ANGLE_RATE, ANGLE_RATE_MAX) * dt
  elseif down then ad = -accel(hold_angle, ANGLE_RATE, ANGLE_RATE_MAX) * dt end
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

-- 当场结算的那条路（定义在下面）：先声明，fire 才能引用它
local fire_teleport

-- 第 i 枚（共 n 枚）相对瞄准线的偏角：等分铺在 weapon.spread 的总角度内。
-- 等分而不是随机：覆盖范围必须可预期，否则同样的瞄准每次结果都不同
local function spread_angle(weapon, i, n)
  if n <= 1 then return 0 end
  local s = weapon.spread or 0
  return s * (i - 1) / (n - 1) - s / 2
end

-- 天基炮：等待期（落点标记闪烁）→ 光柱释放 3 秒（每 tick 结算一次伤害）→ 熄灭。
-- 伤害按"位置"算而不是按"人"：光柱有多宽，站在里面的都会被打到，
-- 所以它逼人离开掩体，而不是"追踪某只虫"
local function update_strikes(dt)
  for i = #strikes, 1, -1 do
    local s = strikes[i]
    local spec = s.spec
    if s.t > 0 then
      s.t = s.t - dt
      if s.t <= 0 then
        -- 点亮：镜头交给 update_camera 里的"特效优先"规则，这里只管声音。
        -- 不用倒计时抢镜头——倒计时会在光柱还没烧完时就放镜头走人
        s.age, s.next_tick = 0, 0
        phos.audio.beep(60, 0.5, { wave = "noise", volume = 0.3, release = 0.3 })
      end
    else
      s.age = s.age + dt
      s.next_tick = s.next_tick - dt
      if s.next_tick <= 0 then
        s.next_tick = spec.tick
        local half = (spec.width or 6) / 2
        for _, q in ipairs(worms.list) do
          if q.alive and math.abs(q.x - s.x) <= half and q.y <= s.y + 2 then
            worms:damage(q, spec.damage)
            add_float(q.x, q.y, spec.damage)
          end
        end
        add_fx(s.x, s.y, 3)
        phos.audio.beep(160, 0.08, { wave = "square", sweep = 60, volume = 0.2 })
      end
      if s.age >= spec.life then table.remove(strikes, i) end
    end
  end
end

-- 点射（机枪）：每 burst 秒出膛一发，全部打完才让上层认为"这一炮结束"。
-- 装填发生在 update 里而不是一次性发完：连发要的是节奏，不是同时出膛
local function update_burst(dt)
  if not burst then return end
  burst.t = burst.t - dt
  if burst.t > 0 then return end
  burst.done = burst.done + 1
  local keep = burst.shooter.angle
  burst.shooter.angle = burst.base + spread_angle(burst.weapon, burst.done, burst.total)
  local p = Weapons.fire(burst.weapon, burst.shooter)
  burst.shooter.angle = keep
  p.trail = {}
  projectiles[#projectiles + 1] = p
  burst.t = burst.weapon.burst
  add_fx(p.x, p.y, 1)
  phos.audio.beep(320, 0.03, { wave = "square", sweep = 120, volume = 0.14 })
  if burst.done >= burst.total then burst = nil end
end

-- 这一炮真的打完了吗：炮弹没了、连发队列空了，燃烧与天基炮这些**后续特效**
-- 也都结束了，缺一不可。判定必须**每帧做一次**（见 update 末尾）：
-- 只在"炮弹消失"那一帧判的话，燃烧/天基炮这类"落地之后才开始"的特效
-- 当场就会被判成"还没完"，而此后没有任何地方会回头再判 —— 回合永远停在 flying
local function shot_finished()
  return #projectiles == 0 and not burst and #strikes == 0 and #fires == 0
end

-- 结算换手：唯一入口。延迟 0.8 秒，让爆炸与音效落地再切手
local function settle_shot()
  turn:end_shot()
  switch_delay = 0.8
end

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
  elseif weapon.kind == "spread" then
    -- 散射：把 N 枚**普通炮弹**按等分角打出去（有抛物线、受风，不是瞬时射线）。
    -- 带 burst 的（机枪）这次只出一发，剩下的交给 update_burst 按间隔点射
    local n = weapon.shells or 1
    local now = weapon.burst and 1 or n
    for i = 1, now do
      local keep = shooter.angle
      if n > 1 then shooter.angle = keep + spread_angle(weapon, i, n) end
      local p = Weapons.fire(weapon, shooter)
      shooter.angle = keep
      p.trail = {}
      projectiles[#projectiles + 1] = p
    end
    if weapon.burst and n > 1 then
      burst = { weapon = weapon, shooter = shooter, base = shooter.angle,
                done = 1, total = n, t = weapon.burst }
    end
  elseif weapon.kind == "laser" then
    -- 激光是一条**会飞的光束**：初速拉到很高、不受重力、不落不炸，
    -- 一路烧穿地形并伤到碰到的人，直到飞出地图边界（镜头一路跟着它）
    local a = math.rad(shooter.angle)
    local sp = weapon.speed or 900
    local mx, my = Physics.muzzle_of(shooter)
    local p = Physics.new_projectile(mx, my,
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
  -- 让侧栏与读数跟着**开火单位**显示它选的武器：队友或敌人开炮时，
  -- 玩家也能看清对面在用哪件道具（这是"谁在用道具"的唯一线索）
  for i, spec in ipairs(Weapons.LIST) do
    if spec == weapon then weapon_index = i end
  end
  turn:begin_shot()
  phos.audio.beep(180, 0.08, { wave = "square", sweep = 90, volume = 0.25 })
  if instant then settle_shot() end   -- 传送这类"当场结算"的也走同一个换手入口
  return true
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
  -- 治疗弹不炸、不挖地：它只给**自己队**回血（敌人治敌人、队友治队友）。
  -- 血满时实际治愈量为 0，于是不会冒出一个骗人的 "+25"
  if (w.heal or 0) > 0 then
    local r = w.radius or 3
    for _, q in ipairs(worms.list) do
      if q.alive and q.team == (p.shooter and p.shooter.team or -1) then
        local d = math.sqrt((q.x - p.x) ^ 2 + (q.y - p.y) ^ 2)
        if d <= r then
          local got = worms:heal(q, w.heal * math.max(0.4, 1 - d / r))
          if got >= 1 then
            add_float(q.x, q.y, 0, "+" .. math.floor(got + 0.5), phos.color.green)
          end
        end
      end
    end
  elseif (w.radius or 0) > 0 then
    local events = {}
    -- p.direct 已在撞虫那一刻拿过全额伤害，这里把它排除在距离衰减之外
    worms:apply_blast(p.x, p.y, w.radius, w.damage, events, p.direct)
    for _, e in ipairs(events) do
      if e.damage and e.damage >= 1 then add_float(e.worm.x, e.worm.y, e.damage) end
    end
    -- 记下"这一炸扫到了谁"：AI 下一轮据此判断自己是不是站在危险位置
    for _, q in ipairs(worms.list) do
      if q.alive and math.abs(q.x - p.x) <= (w.radius or 0) * 1.5 then
        q.exposed = turn.round
      end
    end
  end
  -- 地形弹：不伤人不挖地，落点长出一块圆形地形
  if (w.raise or 0) > 0 then
    local grew = terrain:fill_circle(math.floor(p.x), math.floor(p.y), w.raise)
    add_float(p.x, p.y, 0, "地形 +" .. grew, COL.top)
  end
  -- 天基炮：登记一次打击（等待 spec.delay 秒后开始释放，见 update_strikes）
  if w.orbital then
    strikes[#strikes + 1] = { x = p.x, y = p.y, t = w.orbital.delay,
                              age = 0, next_tick = 0, spec = w.orbital }
    add_float(p.x, p.y, 0, "天基炮!", phos.color.cyan)
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
  -- 这只虫**第一次**轮到自己时回到普通炮弹（列表第一件）。
  -- 不能沿用上一个开火者选的武器：那会让还没开过炮的虫子端着别人的弹药开打
  weapon_index = (now and now.weapon) or 1
  cam.focus, cam.hold, cam.pan = nil, 0, 0
  ai_delay = 1.2
  ai_plan = nil
  ai_decided, ai_walk_t = false, 0      -- 新回合重新决定"要不要先走位"
  ai_reason, ai_run_away = nil, false
  ai_repositioned = false
  burst = nil                        -- 换手时旧的连发队列必须清掉
  hold_angle, hold_power = 0, 0         -- 新回合从"慢速微调"开始，不留上一轮的加速度
end

-- AI 这一炮能用的武器。判断依据是"这局势值不值得用这一件"：
--   * 攻击弹有弹药就能用；集束/超级只在敌人**扎堆**时才划算（几次小爆炸打散人就是浪费）
--   * 治疗弹只在**队友血量低于一半**时才拿出来（见 AI.WOUNDED_RATIO）
--   * 追踪弹与传送不列入：它们的飞行方式没法用同一份 physics 预演，
--     硬塞进这套评分只会算出假成绩
local function ai_weapons(w)
  local out = {}
  local foe = (w.team == 1) and 2 or 1
  local foes = worms:of_team(foe)
  local bunched = false
  for _, e in ipairs(foes) do
    for _, o in ipairs(foes) do
      if e ~= o and math.abs(e.x - o.x) < 18 and math.abs(e.y - o.y) < 10 then bunched = true end
    end
  end
  local wounded = false
  for _, m in ipairs(worms:of_team(w.team)) do
    if m.hp <= Worms.MAX_HP * AI.WOUNDED_RATIO then wounded = true end
  end

  for _, spec in ipairs(Weapons.LIST) do
    if Weapons.has_ammo(w, spec) then
      local ok = false
      if spec.id == "heal" then ok = wounded
      elseif spec.id == "cluster" then ok = bunched
      elseif spec.id == "super" then ok = bunched or #foes <= 1
      -- 追踪弹、传送、天基炮、地形弹一律不列入：前两件的飞行方式没法用同一份
      -- physics 预演，后两件的价值在"位置"而不在"伤害"，评分模型量不到
      elseif spec.id ~= "missile" and spec.id ~= "teleport"
             and spec.id ~= "orbital" and spec.id ~= "terrain" then ok = true end
      if ok then out[#out + 1] = spec.id end
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

  -- 走位只在**两种能说出理由**的情况下发生（不是随机挪）：
  --   exposed：上一轮挨过炸，先离开原地（难度越高越肯躲）
  --   blocked：算完了发现最好的落点离敌人还差得远（预测线被地形挡住 / 够不着）
  local cfg = AI.DIFFICULTY[DIFFS[menu.diff]] or AI.DIFFICULTY.normal
  if not ai_decided then
    ai_decided = true
    if w.exposed and w.exposed >= turn.round - 1
       and phos.sys.random(1, 100) <= cfg.dodge then
      ai_walk_t, ai_reason, ai_run_away = cfg.walk_time, "exposed", true
    end
  end
  if ai_walk_t > 0 then
    ai_walk_t = ai_walk_t - dt
    local dir = ai_run_away and -w.facing or w.facing
    local before = w.x
    worms:move(w, dir, dt)
    -- 只有"走不动"才跳：跳是为了翻过挡住路的坡，不是为了好看
    if w.x == before then worms:jump(w) end
    return
  end

  -- 规划是**分帧推进**的：一次算完几百组预演会触发主机的 100 毫秒看门狗
  if not ai_plan then
    ai_plan = AI.plan_begin(w, worms.list, terrain, turn.wind, DIFFS[menu.diff], ai_weapons(w))
    if not ai_plan then
      turn:next_team() pick_active(1) ai_delay = 1.2
      return
    end
  end
  if not ai_plan:advance(AI.BATCH) then return end
  local plan = ai_plan:result()
  ai_plan = nil
  -- 算完了但够不着：先换个位置再重算，而不是硬打一发没意义的
  -- （每回合只换一次：换完再算还是够不着，就认了，否则会无限挪下去）
  if plan and plan.near and plan.near > cfg.good_dist and not ai_repositioned then
    ai_repositioned = true
    ai_walk_t, ai_reason, ai_run_away = cfg.walk_time, "blocked", false
    return
  end
  if plan then
    w.angle, aim_power = plan.angle, plan.power
    ai_last = string.format("%s %d° 力%d 落点差%d", plan.weapon.id,
                            math.floor(plan.angle + 0.5), math.floor(plan.power * 100 + 0.5),
                            math.floor((plan.near or -1) + 0.5))
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

-- 还在跑的特效里最该看的那个：天基炮优先于燃烧。
-- 镜头**从特效推导目标**，不靠"倒计时抢镜头"——倒计时只会在特效演一半时放走镜头
local function effect_focus()
  if strikes[1] then return strikes[1].x, strikes[1].y end
  if fires[1] then return fires[#fires].x, fires[#fires].y end
  return nil
end

-- 镜头优先级：飞行中的弹药 → 还在跑的特效 → 爆炸后的短暂停留 → 当前虫子。
-- , . 可以左右平移，平移**不设上限**（只受世界边缘约束），否则视野外的敌人永远看不到
local function update_camera(dt)
  if phos.input.down("comma") then cam.pan = cam.pan - 130 * dt end
  if phos.input.down("period") then cam.pan = cam.pan + 130 * dt end
  if cam.hold > 0 then cam.hold = cam.hold - dt end

  local p = projectiles[1]
  local tx, ty
  if p then
    tx, ty = p.x, p.y
  else
    tx, ty = effect_focus()
    if not tx and cam.hold > 0 and cam.focus then
      tx, ty = cam.focus[1], cam.focus[2]
    end
    if not tx then
      local w = current_worm()
      if w and w.alive then tx, ty = w.x, w.y end
    end
  end
  if tx then
    local k = 1 - math.exp(-dt * 6)
    cam.x, cam.y = cam.x + (tx - cam.x) * k, cam.y + (ty - cam.y) * k
  end
  camera:center(cam.x + cam.pan, cam.y)
end

function update(dt)
  flash = flash + dt
  update_burst(dt)                 -- 点射（机枪）：先把该出膛的那一发补上
  update_strikes(dt)               -- 天基炮：等待/释放/结算
  -- M：地图总览浮窗。**不暂停**——它只是"看一眼地图"，
  -- 不该打断正在飞的弹药与回合计时
  if phos.input.pressed("m") then
    map_open = not map_open
    phos.audio.beep(map_open and 600 or 380, 0.04, { wave = "square", volume = 0.14 })
  end
  if phos.input.pressed("k") then
    help_open = not help_open
    phos.audio.paused(help_open)     -- 看键位表时连音乐一起停
    phos.panel.resize(help_open and 0 or PANEL_W)
  end
  if screen == "menu" then
    menu_flash = menu_flash + dt
    menu_input(dt)
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
      end
      local last = p.trail[#p.trail]
      if not last or (p.x - last[1]) ^ 2 + (p.y - last[2]) ^ 2 > 16 then
        p.trail[#p.trail + 1] = { p.x, p.y }
        if #p.trail > 90 then table.remove(p.trail, 1) end
      end
    else
    local result, point = Physics.step(p, dt, turn.wind, probe)
    local last = p.trail[#p.trail]
    if not last or (p.x - last[1]) ^ 2 + (p.y - last[2]) ^ 2 > 16 then
      p.trail[#p.trail + 1] = { p.x, p.y }
      if #p.trail > 60 then table.remove(p.trail, 1) end
    end
    if result then
      -- 直接命中（撞到虫身上）：按面板伤害**全额**结算。
      -- 命中判定用的是躯体半径（HIT_RADIUS = 3 子格），弹着点离虫脚最远也有 3，
      -- 只用爆炸的距离衰减去算的话，擦着打中的那发会被削到保底 10%——打中等于没打中
      if result == "worm" and point then
        if (p.weapon.heal or 0) > 0 then
          -- 治疗弹直击：只对**自己队**生效（打在对面身上什么都不发生）
          if point.team == (p.shooter and p.shooter.team or -1) then
            local got = worms:heal(point, p.weapon.heal)
            if got >= 1 then
              add_float(point.x, point.y, 0, "+" .. math.floor(got + 0.5), phos.color.green)
            end
          end
        else
          worms:damage(point, p.weapon.damage or 0)
          add_float(point.x, point.y, p.weapon.damage or 0)
        end
        p.direct = point
      end
      resolve(p)
      table.remove(projectiles, i)
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

  -- 这一炮打完了吗：**每帧判一次**，判据只有 shot_finished() 一处。
  -- 放在这里（而不是炮弹消失那一刻）是因为"落地"与"结束"不是同一件事：
  -- 燃烧、天基炮光柱都是落地之后才开始的
  if turn.phase == "flying" and not switch_delay and not winner and shot_finished() then
    settle_shot()
  end

  -- 弹药结算后的换手延迟：必须**与阶段无关**地倒数
  if switch_delay and not winner then
    switch_delay = switch_delay - dt
    if switch_delay <= 0 then
      switch_delay = nil
      after_settle()
    end
  end

  -- 回合计时只在"轮到我瞄准"时走：开炮期间停下来是刻意的
  if turn.phase == "aim" and not winner and not switch_delay then
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
  -- 天基炮：等待期画闪烁的落点标记（要让人有机会跑开），释放期画贯天光柱
  for _, s in ipairs(strikes) do
    local half = (s.spec.width or 6) / 2
    if s.t > 0 then
      if math.floor(flash * 8) % 2 == 0 then
        for d = -half, half, 1 do
          put_at(S, s.x + d, s.y, (d == 0) and "V" or "-", C.cyan)
        end
      end
    else
      -- 光柱：从世界顶端一路贯到落点；中心实线、两侧虚线，宽度就是判定宽度
      for d = -half, half, 1 do
        local ch = (d == 0) and "|" or ((math.abs(d) == half) and ":" or "|")
        for wy = 1, s.y do
          put_at(S, s.x + d, wy, ch, C.cyan)
        end
      end
      for d = -half - 1, half + 1, 1 do
        put_at(S, s.x + d, s.y, "=", C.white)
      end
    end
  end
  for _, p in ipairs(projectiles) do
    for _, pt in ipairs(p.trail) do
      -- 轨迹点用灰白而不是深灰：深灰压在深色地形上像一条黑底带
      put_at(S, pt[1], pt[2], "·", C.gray)
    end
  end
end

-- 炮口符号：ASCII 表达方向就靠 - | / \ 四个（屏幕 y 向下，所以"往右上"是 /）
local function slope_glyph(ux, uy)
  if math.abs(ux) >= math.abs(uy) * 2 then return "-" end
  if math.abs(uy) >= math.abs(ux) * 2 then return "|" end
  return (ux * uy < 0) and "/" or "\\"
end

-- 瞄准线：从**炮口**沿瞄准方向点一条虚线，近密远疏，长度随力度长。
-- 它**只是一条直线**，不是弹道预测——角度看得清、落点还得自己算（DESIGN 第 7 节）。
-- 两档密度是刻意的：一个字符格 = 2x2 子格，本来就看不细；近身这一段要是也
-- 隔好几格才点一下，"炮口朝哪"就只能靠猜（玩家反馈的"近处把不准"就是这个）。
--   近身 AIM_NEAR_SUB：逐格点 + 白色，微调一度都看得出来
--   远处：隔一格点 + 武器色，只作方向示意，不去把整屏点满
-- 另外只画在**空中**：一格只能放一个字形，点进土里会把地形顶出一个个小洞。
-- （末端的 > < 是"力度标尺"而不是路径，所以照画、不跳过）
local function draw_aim(S, C)
  local w = current_worm()
  if not w or not w.alive or winner or not human_turn() then return end
  if turn.phase ~= "aim" then return end
  local a = math.rad(w.angle)
  local ux, uy = math.cos(a) * w.facing, -math.sin(a)
  local ox, oy = Physics.muzzle_of(w)
  local col = charge_mode and C.yellow or C.orange

  -- 炮口那格先点一个斜率符号：再密的虚线也不如一个 / 或 \ 把朝向说得清楚
  put_at(S, ox, oy, slope_glyph(ux, uy), charge_mode and C.yellow or C.white)

  local len = 12 + aim_power * 96
  for d = AIM_STEP_SUB, len, AIM_STEP_SUB do
    local x, y = ox + ux * d, oy + uy * d
    local near = d <= AIM_NEAR_SUB
    if (near or (d / AIM_STEP_SUB) % 2 == 1) and not terrain:solid(math.floor(x), math.floor(y)) then
      put_at(S, x, y, "·", near and C.white or col)
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
        Hud.hp_bar(S, C, i, j - 2, w.hp / Worms.MAX_HP, COL.plate)
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

-- M 地图总览：整幅地形剖面 + 双方位置 + 空中弹药 + 风向。
-- 侧栏放不下这些（8v8 时光血量就占十几行），所以挪进浮窗；
-- 它**不暂停**：弹药还在飞的时候也能看一眼全局，不用牺牲一个回合
local function draw_map_overlay(S, C)
  local mw = math.min(VIEW_CW - 8, 58)
  local mh = math.min(VIEW_CH - 14, 18)
  local x = math.floor((VIEW_CW - mw) / 2)
  local y = 4                        -- 往下方放一些：上边留给状态行与瞄准读数
  S.fill(x, y, mw, mh + 3, " ", nil, COL.plate)
  box(S, C, x, y, mw, mh + 3, "地图总览", C.white)

  -- 地形剖面：每列向下取一次表面高度，往下画实心；水面单独一色
  local sx, sy = terrain.W / (mw - 2), terrain.H / mh
  local tops = {}
  for i = 0, mw - 3 do
    local wx = math.floor((i + 0.5) * sx) + 1
    tops[i] = 0
    for yy = 1, terrain.WATER_Y - 1 do
      if terrain:solid(wx, yy) then tops[i] = yy break end
    end
  end
  for j = 0, mh - 1 do
    local wy = math.floor((j + 0.5) * sy) + 1
    for i = 0, mw - 3 do
      local solid = (tops[i] > 0 and wy >= tops[i])
      if solid then
        S.put(x + 1 + i, y + 1 + j, "#", COL.top)
      elseif wy >= terrain.WATER_Y then
        S.put(x + 1 + i, y + 1 + j, "~", COL.water)
      end
    end
  end

  -- 虫子：正在操作的那只画成 O（其余 @），一眼知道该看谁
  for _, w in ipairs(worms.list) do
    if w.alive then
      local i = math.max(0, math.min(mw - 3, math.floor(w.x / sx)))
      local j = math.max(0, math.min(mh - 1, math.floor(w.y / sy)))
      local col = (w.team == 1) and C.yellow or C.red
      S.put(x + 1 + i, y + 1 + j, (w == current_worm()) and "O" or "@", col, COL.plate)
    end
  end

  -- 空中弹药也要看得见：地图若只画"人站在哪"，就说不清"炮弹正往哪飞"——
  -- 而 M 之所以不暂停，正是为了在弹药飞行途中也能看一眼全局
  for _, p in ipairs(projectiles) do
    local i = math.max(0, math.min(mw - 3, math.floor(p.x / sx)))
    local j = math.max(0, math.min(mh - 1, math.floor(p.y / sy)))
    S.put(x + 1 + i, y + 1 + j, "*", C.white, COL.plate)
  end

  S.print(x + 2, y + mh + 1, string.format("回合 %d    风 %s    轮到 %s队    空中 %d",
           turn.round, Hud.wind_text(turn.wind), turn.team == 1 and "左" or "右",
           #projectiles), C.white)
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
  local w, h = math.min(46, pw - 2), 17
  local x = px + math.floor((pw - w) / 2) + 2
  local y = py + math.floor((ph_ - h) / 2) + 1
  box(S, C, x - 1, y - 1, w, h, "选择模式", C.white)
  local mark = function(row) return (menu.row == row) and ">" or " " end
  local hi = function(row) return (menu.row == row) and C.white or C.gray end

  if menu.mode == "pve" then
    S.print(x, y, string.format("%s 模式        < PVE 人机对战 >", mark(1)), hi(1))
    S.print(x, y + 1, "   左队归你，右队全归电脑", C.dark_gray)
    S.print(x, y + 2, string.format("%s 我方人数    < %d >", mark(2), menu.mine), hi(2))
    S.print(x, y + 3, string.format("%s 敌方人数    < %d >", mark(3), menu.theirs), hi(3))
  else
    S.print(x, y, string.format("%s 模式        < PVP 同机对战 >", mark(1)), hi(1))
    S.print(x, y + 1, "   两人轮流操作同一台机器", C.dark_gray)
  end
  S.print(x, y + 4, string.format("%s 生命值      < %d >", mark(4), menu.hp), hi(4))
  S.print(x, y + 5, string.format("   每人上限 %d~%d，每次 %d；一局多长就看它",
                                  HP_MIN, HP_MAX, HP_STEP), C.dark_gray)
  if menu.mode == "pve" then
    S.print(x, y + 6, string.format("%s 队友交给 AI < %s >",
                                    mark(5), menu.ally_ai and "是" or "否"), hi(5))
    S.print(x, y + 7, menu.ally_ai and "   你只操作队长，其余队友由电脑指挥"
                                     or "   所有队友都由你自己操作", C.dark_gray)
    local dl = DIFF_LABEL[phos.sys.language()] or DIFF_LABEL.zh
    S.print(x, y + 8, string.format("%s 难度        < %s >",
                                    mark(6), dl[DIFFS[menu.diff]] or DIFFS[menu.diff]), hi(6))
    S.print(x, y + 9, "   越难：敌人与队友越会走位，也打得越准", C.dark_gray)
  end
  S.print(x, y + 11, string.format("%s 开始游戏", mark(7)),
          (menu.row == 7) and C.yellow or C.gray)
  S.print(x + 2, y + 13, "↑↓ 选择   ←→ 调整（按住加速）   A / ENTER 确定", C.dark_gray)
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
  -- 瞄准线、预测线、力度读数只在"轮到我、还没开炮"时出现：一发射立刻收掉，
  -- 免得玩家盯着上一炮的刻度去瞄下一炮。
  -- 它画在**角色之前**：高抛时线会穿过自己的头顶，压在血条与选标下面才不会糊成一团
  if turn.phase == "aim" and human_turn() and not winner then draw_aim(S, C) end
  draw_actors(S, C)

  local w = current_worm()
  local weapon = selected_weapon()
  local left = (weapon and w and w.ammo[weapon.id]) or 0
  Hud.draw(S, C, {
    worm = w, wind = turn.wind, time_text = turn:time_text(), round = turn.round,
    phase = turn.phase, shots_left = turn.shots_left,
    weapon = weapon, plate = COL.plate,
    ammo = left, charge = charge_mode, pvp = pvp, turn_team = turn.team,
    ally_ai = ally_ai, human = human_turn(),
    floats = floats,
    -- 只在**弹药真的在空中**时提示。燃烧 3 秒、光柱 5 秒属于"特效阶段"，
    -- 那时还写"弹药飞行中"，玩家会以为卡住了
    flight_note = (#projectiles > 0 or burst) and "弹药飞行中" or nil,
  })

  if winner then
    local msg = (winner == 1) and "左队胜利   按 ENTER 回菜单" or "右队胜利   按 ENTER 回菜单"
    S.print(VIEW_CW // 2 - #msg // 2, VIEW_CH // 2, msg, C.white, phos.color.black)
  end

  Panel.draw({
    terrain = terrain, camera = camera, worms = worms, turn = turn,
    weapons = Weapons.LIST, current = weapon, pvp = pvp, active = w,
    human = human_turn(), ally_ai = ally_ai, hp_max = Worms.MAX_HP,
    -- 队长：队友交给 AI 时，唯一还归玩家操作的那只
    leader = worms:of_team(1)[1],
  })
  if map_open then draw_map_overlay(S, C) end
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
    mine = menu.mine, theirs = menu.theirs, menu_row = menu.row, hp_max = menu.hp,
    diff = DIFFS[menu.diff] or "normal",
    ai_reason = ai_reason or "-", ai_walking = ai_walk_t > 0,
    ai_repositioned = ai_repositioned, ai_last = ai_last, map_open = map_open,
    burst_left = burst and (burst.total - burst.done) or 0, strikes = #strikes,
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

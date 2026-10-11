-- physics.lua —— 唯一物理真源：重力、风、子格步进、碰撞、爆炸
--
-- 弹药、虫子、AI 预演全部走这里。这样"AI 算得准不准"与"玩家打不打得中"
-- 就是同一套规则 —— 这是这个游戏最重要的一条自律。
-- 本模块不认识"谁是谁"：它只认坐标与调用方给的判定函数。

local Physics = {}

Physics.GRAVITY = 24           -- 子格/秒²（= 12 格/秒²，DOM 里的虫子手感）
Physics.MAX_WIND = 6           -- 风力上限（子格/秒²），每回合随机
-- 满蓄力初速直接决定射程：无风 45° 时射程 ≈ v²/g，94²/24 ≈ 368 子格（近 4 成世界宽），
-- 顺风还能再远一截——"力度条还剩多少"才是真正要算的东西
Physics.MAX_SPEED = 94         -- 满蓄力初速（子格/秒）
Physics.MIN_SPEED = 8          -- 力度 10% 的初速（太小的初速连脚下的坡都翻不过去）

-- 力度的合法区间。输入、AI 规划、发射三处共用，边界只在这里定义一次
Physics.POWER_MIN, Physics.POWER_MAX = 0.1, 1.0

Physics.SUBSTEP = 0.25         -- 步进上限（子格）：逐点判定，避免穿墙
Physics.GRENADE_KEEP = 0.3     -- 手雷落地保留的速度（其余被地面吃掉）
Physics.BURN_DPS = 20          -- 燃料火的伤害速率（每秒）。按秒算而不是按帧算：
                               -- 60 帧下"每帧 2 点"就是每秒 120 点，谁站进去都秒死

function Physics.clamp_power(power)
  return math.max(Physics.POWER_MIN, math.min(Physics.POWER_MAX, power or 0))
end

-- 力度百分比（0.1~1.0）→ 初速
function Physics.speed_of(power)
  return Physics.MIN_SPEED + (Physics.MAX_SPEED - Physics.MIN_SPEED) * Physics.clamp_power(power)
end

-- 角度（度，0 = 朝正右、90 = 朝正上）→ 速度分量。
-- facing 为 +1/−1，决定朝右还是朝左射。
function Physics.velocity(angle_deg, power, facing)
  local a = math.rad(angle_deg)
  local v = Physics.speed_of(power)
  return v * math.cos(a) * facing, -v * math.sin(a)
end

-- 炮口：弹药**出生的位置**，也是瞄准线的起点。贴着身体（见 main 的 draw_actors），
-- 不悬在头顶 —— 出生点比虫标高出半格的话，"炮口到第一个落点"这一段就永远是歪的。
-- 绘制、发射、AI 评分共用它：改了其中一处，就会出现"线画在一个地方、弹从另一个地方飞出来"。
-- 出生点贴着身体，所以命中判定必须**跳过射手本人**（见 step 的第三个参数）
function Physics.muzzle_of(w)
  return w.x + (w.facing or 1) * 1, w.y - 2
end

function Physics.new_projectile(x, y, vx, vy, opts)
  opts = opts or {}
  return {
    x = x, y = y, vx = vx, vy = vy,
    wind = opts.wind or 0,     -- 受风系数：1 = 全额、0 = 不受风
    fuse = opts.fuse,          -- 引信秒数（nil = 撞到才炸）
    bounce_ground = opts.bounce_ground or false,  -- 撞地弹跳而不炸（手雷）
    no_gravity = opts.no_gravity or false,        -- 不受重力（追踪弹自己管方向）
    t = 0, alive = true,
  }
end

-- 推进 dt 秒。hit(x, y) 由调用方提供，返回 nil 或命中类型：
--   "terrain" 撞地 / "worm" 撞虫 / "water" 入海 / "out" 出界
-- 返回命中类型、或 "fuse"（引信到点）、或 nil（仍在飞）；
-- hit 的第二个返回值（撞虫时是那只虫）原样透传，调用方靠它结算"直接命中"。
-- hit 还会收到**弹丸自己**作第三个参数：炮口就在射手身上，命中判定不跳过它的话，
-- 出膛那一帧就"撞到自己"。
-- 手雷（bounce_ground）撞地**不算命中**：弹一下继续飞，结算交给引信。
function Physics.step(p, dt, wind, hit)
  if not p.alive then return nil end
  local speed = math.max(math.abs(p.vx), math.abs(p.vy))
  local steps = math.ceil(speed * dt / Physics.SUBSTEP)
  steps = math.max(1, math.min(64, steps))
  local h = dt / steps
  for _ = 1, steps do
    p.t = p.t + h
    p.vx = p.vx + (wind or 0) * (p.wind or 0) * h
    if not p.no_gravity then p.vy = p.vy + Physics.GRAVITY * h end
    p.x = p.x + p.vx * h
    p.y = p.y + p.vy * h
    local kind, point = hit(p.x, p.y, p)
    if kind == "terrain" and p.bounce_ground then
      Physics.bounce(p)
    elseif kind then
      p.alive = false
      return kind, point
    end
    if p.fuse and p.t >= p.fuse then
      p.alive = false
      return "fuse"
    end
  end
  return nil
end

-- 落地反弹（手雷）：向下的速度被地面吃掉大半，水平也损失一些。
-- 同时把弹丸顶出地面一格——否则下一个子步又判定"撞地"，会连着弹，
-- 看起来像在地上抖；顶出去之后它才会真的再落下来。
function Physics.bounce(p)
  p.y = p.y - 1
  p.vy = -p.vy * Physics.GRENADE_KEEP
  if math.abs(p.vy) < 1.5 then p.vy = 0 end
  p.vx = p.vx * ((p.vy == 0) and 0.5 or 0.75)
  if p.vy == 0 and math.abs(p.vx) < 0.8 then p.vx = 0 end
end

Physics.BLAST_FLOOR = 0.35     -- 距离衰减的保底比例：擦着边的也至少吃这么多
-- 爆炸挖地形比杀伤范围大一圈：炮弹是"掀开地面"，弹片只飞半径内那么远。
-- 两者共用一个半径的话，杀伤够用的炮弹挖不出够看的坑
Physics.BLAST_DIG_SCALE = 1.6

-- 爆炸：挖地形 + 对范围内每个点按距离衰减算伤害与冲量。
-- points 是任意带 x/y 的表（虫子、油桶……），把"谁挨打"留给调用方。
-- 返回 { {point=, damage=, push=}, ... }, 挖掉的格数
function Physics.blast(x, y, radius, damage, points, terrain)
  -- terrain 传 nil = "只算伤害，不动地形"：AI 预演要调用上千次，
  -- 绝不能让它在预演里真把地图挖了
  local dug = 0
  if terrain then
    dug = terrain:blast(math.floor(x), math.floor(y), radius * Physics.BLAST_DIG_SCALE)
  end
  local floor = Physics.BLAST_FLOOR
  local hits = {}
  for _, p in ipairs(points) do
    -- 虫子有身高（p.body_h）：只按脚底那一个点算距离的话，在它胸口炸开的炮弹会被判成
    -- "离得很远"，于是两三个人挤在一起时只有一只吃到伤害、其余全掉到保底。
    -- 把爆炸点夹进 [脚底 - body_h, 脚底] 就是"打在身体的最近那一段上"
    local py = p.y
    local bh = p.body_h or 0
    if bh > 0 then
      py = math.min(math.max(y, p.y - bh), p.y)
    end
    local dx, dy = p.x - x, py - y
    local d = math.sqrt(dx * dx + dy * dy)
    if d <= radius then
      -- 开方后的衰减：内圈仍是满伤，外圈才往下掉。直线衰减配 0.1 保底会让挨着站的
      -- 队友只吃两成伤，与"范围爆炸该炸一片"的直觉不符
      local k = floor + (1 - floor) * math.sqrt(1 - d / radius)
      hits[#hits + 1] = { point = p, damage = damage * k, push = (radius - d) * 0.4 }
    end
  end
  return hits, dug
end

-- 坠落伤害：落差（子格）换算成伤害，上限 50
function Physics.fall_damage(drop_subcells)
  local cells = drop_subcells / 2
  if cells <= 3 then return 0 end
  return math.min(50, (cells - 3) * 5)
end

return Physics

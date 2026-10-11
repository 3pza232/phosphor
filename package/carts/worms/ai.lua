-- ai.lua —— 电脑队：按"怎么瞄 × 命中后怎么变"两件事装配，评分只认世界变化量
--
-- 一件武器由**三段数据**描述（都在 weapons.lua，改武器不必回这里）：
--   plan   = 走哪个瞄准求解器（怎么试）：arc 抛物线角度×力度 / ray 直线只挑角度
--   effect = 命中之后世界怎么变：blast 爆炸 / heal 回血 / mound 长地形并埋人 /
--            strike 天降光柱 / beam 烧穿射线
--   ai     = 电脑用不用它：throw 参战 / self 只对自己用（传送）/ false 明确不用
-- 于是"加一件新武器"= 武器表加一行；只有当它带来**全新的瞄准维度**或**全新的世界变化**
-- 时，才需要在下面的 PLANS / EFFECTS 里各加一个函数。规划器、评分、难度、发射逻辑、
-- 侧栏、候选过滤都不必动。
--
-- 三条硬约束，动手改之前先想清楚它们为什么在：
--   1. 预演必须走**同一份 physics**（连子步都共用），否则 AI 挑中的角度在实弹里不成立；
--      手雷的弹跳也不例外 —— 自己写一套"撞地就停"的近似弹道，算出来的落点是假的
--   2. 主机有"单次调用不得超过 100 毫秒"的看门狗，几百组候选一次算完会被当场掐掉。
--      所以规划器**可分帧推进**：每帧只算一小批，想 0.2~0.4 秒再开炮
--   3. 预演**不许改世界**：Physics.blast 传 nil 地形；地形弹按**理想圆**估（真实那一发
--      每行有 ±1 子格的噪声，预演按无噪声算，位置误差 ≤1 子格）
--
-- 评分思路：每个候选先被预演成一个**世界变化量 delta**（伤了多少、埋了几只、挖了几格…），
-- 再用**同一套权重**相加。评分只认 delta，不认武器种类 —— 加一件武器不必回来补公式。
--
-- 结果里额外带出 `near`（最优落点离最近目标多远，子格）与 `reason`（一句话说明它为什么赢）。

local Physics = require("physics")
local Worms = require("worms")
local Weapons = require("weapons")

local AI = {}
local HIT_R2 = Worms.HIT_RADIUS * Worms.HIT_RADIUS

AI.PREVIEW_DT = 1 / 30      -- 预演的时间步（秒）：真正的物理，只是不画画面
AI.PREVIEW_MAX_T = 14       -- 一枚弹药最多预演这么久
AI.BATCH = 20               -- 每帧最多预演多少组（预算：稳在一帧之内）

-- 赶路时的死胡同检测（判定逻辑在 main.lua 的 update_ai，阈值放这里与性格参数同处）
AI.STUCK_T = 0.9            -- 观察多久还没挪动就判死胡同（秒）
AI.STUCK_MOVE = 3           -- "挪动了"的最小净位移（子格）：0.9 秒常速能走约 9 格，远大于它
AI.STUCK_NEAR = 6           -- 离上次撞墙处这么近，就当作还在同一个死胡同口
-- 激光（ray 计划）的瞄准抖动比例：它是**没有风偏**的直线，同样的角度抖动会被距离
-- 放大成好几格的横向偏移，所以手抖要按比例压小（见 Planner:result）
AI.RAY_AIM_SCALE = 0.25
-- 血量不超过这个比例就算"伤员"，值得用治疗弹。
-- 用"不超过"而不是"低于"：本作的伤害值（8/10/25/30/50）经常正好把血打到 50，
-- 卡在严格小于上会让最需要治疗的那只恰好被跳过
AI.WOUNDED_RATIO = 0.5

-- 权重表：**加武器不必改它**，调难度也只改这张表（外加手抖与扫描密度）。
-- 每项后面写的是"这个数在买什么"，改之前先想清楚买的是什么
AI.WEIGHTS = {
  damage = 3.0,    -- 敌方净掉血（每点）：主项
  hit = 40,        -- 直击：打断走位、把人推下坡，这些价值量不出来但确实存在
  heal = 3.0,      -- 给队友回血（每点）：与伤害同一把尺子
  drown = 90,      -- 把敌人送进水里：等于直接消灭
  trap = 45,       -- 把敌人埋住（地形弹）：它走不动、只能花弹药自救 —— 这就是牵制
  dig = 0.25,      -- 每挖掉一格地形：破掩体是好事，但也可能给对方开出新路，所以权重小
  dig_cap = 40,    -- 挖地形的计分上限：一炮能挖的格数无上限（天基炮连跳、贯穿的激光），
                   -- 不封顶的话"挖土多"会盖过"打到人"，AI 就会挑着对空气开炮
  self = 0.8,      -- 自伤（每点，乘这个系数）
  mate = 5.0,      -- 打到**队友**（每点）：比自伤高得多——自伤是自己付代价，
                   -- 误伤队友等于替对面打掉一条命。权重必须高过 damage，否则
                   -- "炸到 1 个敌人 + 1 个队友"在账面上仍然赚
  mate_flat = 40,  -- 打到队友再加一笔**定额**罚分：让"会打到队友"的炮明显劣于"干净"的炮，
                   -- 但只要战果够大仍可能值（"误伤不是硬禁止"）。单靠按点的 mate 权重时，
                   -- 小伤害武器（激光 22）误伤一个队友还不足以压低整炮，定额罚正好补上
  near = 1.0,      -- 离目标越远越差：没打中时靠它挑"谁离得最近"
  near_cap = 60,   -- 偏离扣分的上限
  blocked = 45,    -- 抛物线被地形挡住（预演走到半路撞地）：这种炮多半炸在自己脚边，
                   -- 光靠"落点远"扣分不够：近处自伤还可能被算成"打到自己人"的收益
  -- 机会成本：**按稀缺度定价**。不用"本回合已评出的最高分"当门限——那种算法依赖评估顺序，
  -- 换个顺序结论就变，加一件武器还可能悄悄改掉别人的定价。
  -- 无限弹（ammo<0）几乎免费；限量弹按 1/剩余发数 计价：剩 1 发就是 30 分，剩 4 发只有 7.5 分
  ammo = 30,
  ammo_free = 2,   -- 无限弹的固定小成本（"打光了也有得打"，不是免费随便打）
}

-- 赶路的两个参数。放在这里而不是 main.lua：**"要多积极地找架打"属于性格**，
-- 与难度档位是同一类东西，将来调难度档时该在一起看
AI.WALK_CHUNK = 1.5   -- 每次赶路先走这么久，再重算一遍（一次走太久会冲过射程）
AI.WALK_LEAVE = 8     -- 回合只剩这么多秒就不再赶路：改为就地消极处理
                      -- （大地图上跑过去要十几秒，走到一半没时间开炮等于白走）

-- 难度：决定"算得多细""手有多稳""什么时候肯换位置"，但**没有一档是必中**——
-- 越难只是把误差压小、扫描做细、走位更积极，最后一击仍要看风向与地形
--   angle/power      瞄准误差（度 / 力度比例）
--   a_step/p_step    粗扫密度；refine 是否再围着最优解精修一遍
--   good_dist        落点离目标多近才算"打得到"（子格）；够不着就先走位
--   dodge            上一轮被炸到之后，这一轮选择换位置的百分比
--   walk_time        真挪起来走多久（秒）
-- angle / power 是**刻意打的误差**：角度加 ±angle 度、力度乘 (1 ± power)。
-- 这两项直接决定命中率，所以三档要拉开；但也不能给大 —— 溅射半径只有 3~5 子格，
-- 误差一大，AI 就整局打不中：算出来的落点再准，也被这抖动推出溅射半径之外。
-- 所以调稳一档：easy 4°/5%、normal 2°/2%、hard 1°/1%
AI.DIFFICULTY = {
  easy = { angle = 4, power = 0.05, a_step = 14, p_step = 0.15, refine = false,
           good_dist = 14, dodge = 25, walk_time = 0.5 },
  normal = { angle = 2, power = 0.02, a_step = 10, p_step = 0.10, refine = true,
             good_dist = 9, dodge = 55, walk_time = 1.0 },
  hard = { angle = 1, power = 0.01, a_step = 8, p_step = 0.08, refine = true,
           good_dist = 6, dodge = 85, walk_time = 1.6 },
}

-- 用真 physics 飞一次，返回落点与"直接命中"的那只虫。
-- 激光不在这里：它走直线，见下面的 beam 效果（少一次仿真，也更准）
local function preview(ctx, shooter, weapon, aim)
  local keep_a, keep_p = shooter.angle, shooter.power
  shooter.angle, shooter.power = aim.angle, aim.power
  local p = Weapons.fire(weapon, shooter)
  shooter.angle, shooter.power = keep_a, keep_p

  local hit_worm = nil
  local function probe(x, y)
    if x < 1 or x > ctx.terrain.W or y > ctx.terrain.H then return "out" end
    if y < 1 then return nil end
    if ctx.terrain:solid(math.floor(x), math.floor(y)) then return "terrain" end
    if y >= ctx.terrain.WATER_Y then return "water" end
    for _, t in ipairs(ctx.enemies) do
      if t.alive then
        local dx, dy = t.x - x, t.y - y
        if dx * dx + dy * dy <= HIT_R2 then hit_worm = t return "worm", t end
      end
    end
    return nil
  end

  local t, kind = 0, nil
  while t < AI.PREVIEW_MAX_T do
    kind = Physics.step(p, AI.PREVIEW_DT, ctx.wind, probe)
    t = t + AI.PREVIEW_DT
    if kind then break end
  end
  -- blocked：这一炮**被地形挡住了**（预演走到半路撞地）。上层据此专门扣分——
  -- 炮口就在自己身上，被挡住的炮往往炸回自己脚边，"落点离目标远"这一项还不够说明问题
  return { x = p.x, y = p.y, hit = hit_worm, blocked = (kind == "terrain") }
end

-- ---------- 瞄准求解器：产出"试哪些瞄法" ----------
-- 每个求解器两件事：jobs 给出候选（aim 表），impact 把候选算成**落点描述**。
-- 落点描述只有两种形状，效果函数按自己需要取：
--   { x, y, hit }        有一次落点（抛物线、垂直光柱）
--   { ray = {ox,oy,dx,dy,len} }  一条射线（激光：沿路都算）
local PLANS = {}

-- 抛物线：角度 × 力度。绝大多数弹药走这条
PLANS.arc = {
  jobs = function(weapon, cfg)
    local out = {}
    for angle = 40, 140, cfg.a_step do
      for power = 0.25, 1.0, cfg.p_step do
        out[#out + 1] = { angle = angle, power = power }
      end
    end
    return out
  end,
  impact = function(ctx, shooter, weapon, aim)
    -- preview 返回的就是落点描述 { x, y, hit }，直接交出去即可。
    -- 写成 local x, y, hit = preview(...) 的话，x 拿到的是整张表，
    -- 下游 Physics.blast 收到表就会报"对表做算术"
    return preview(ctx, shooter, weapon, aim)
  end,
  -- 精修：围着粗扫找到的那一组细看（误差是之后才加的，这里要的是准）
  refine = function(best, cfg)
    return { angle = best.angle, power = best.power }
  end,
}

-- 射线：只有角度有意义（激光不落不炸，力度不影响结果）
PLANS.ray = {
  jobs = function(weapon, cfg)
    local out = {}
    for angle = -40, 80, 4 do
      out[#out + 1] = { angle = angle, power = 1.0 }
    end
    return out
  end,
  impact = function(ctx, shooter, weapon, aim)
    local a = math.rad(aim.angle)
    local ox, oy = Physics.muzzle_of(shooter)
    local dx, dy = math.cos(a) * shooter.facing, -math.sin(a)
    -- 射线也要给出"离目标多远"：它是**点到直线**的距离，不是落点距离。
    -- 不这么做，上层拿到的 near 会是"射手到目标的距离"（几百子格），
    -- 于是"够不着，先换个位置"的判断对激光永远为真，它会站在那儿一直对空气开炮
    local near = 9999
    for _, t in ipairs(ctx.enemies) do
      if t.alive then
        local px, py = t.x - ox, t.y - 3 - oy     -- 瞄身体中段
        local along = px * dx + py * dy
        if along > 0 then
          local cx, cy = ox + dx * along, oy + dy * along
          local d = math.sqrt((ox + px - cx) ^ 2 + (oy + py - cy) ^ 2)
          if d < near then near = d end
        end
      end
    end
    return { x = ox, y = oy, near = near,
             ray = { ox = ox, oy = oy, dx = dx, dy = dy, len = ctx.terrain.W * 2 } }
  end,
  refine = function(best, cfg) return { angle = best.angle, power = 1.0 } end,
}

-- ---------- 效果：把落点翻译成"世界变化量"（全部纯计算，不许改世界） ----------
-- delta 字段就是评分表的输入，加新效果时**顺手加字段**即可，评分不必改：
--   damage / hits / heal / drown / trap / dig
--   own_*  射手**自己**吃到的（自伤 / 自己掉水里 / 自己被埋）
--   mate_* 除射手以外的**自己队**吃到的（误伤队友）—— 两者分开记，因为权重不同
local EFFECTS = {}

local function new_delta()
  return { damage = 0, hits = 0, heal = 0, drown = 0, trap = 0, dig = 0,
           own_damage = 0, own_drown = 0, own_trap = 0,
           mate_damage = 0, mate_drown = 0, mate_trap = 0 }
end

-- 把"自己队吃到的伤害"分流进 own_* 还是 mate_*：射手本人算自伤，其余算误伤队友
local function count_friendly(d, ctx, point, damage, near_water_hit)
  if point == ctx.shooter then
    d.own_damage = d.own_damage + damage
    if near_water_hit then d.own_drown = d.own_drown + 1 end
  else
    d.mate_damage = d.mate_damage + damage
    if near_water_hit then d.mate_drown = d.mate_drown + 1 end
    d.mate_x = point.x  -- 记下会被打到的队友位置：上层靠它决定"往哪边挪来避让"
  end
end

-- 水边判定：脚下离水面这么近就算"一炸就下去"（子格）。纯几何，不改世界
local DROWN_MARGIN = 6
local function near_water(ctx, w)
  return w.y >= ctx.terrain.WATER_Y - DROWN_MARGIN
end

-- 爆炸：挖地形 + 按距离衰减的伤害与冲量。预演不传地形（见文件头第 3 条）
EFFECTS.blast = function(ctx, weapon, impact)
  local d = new_delta()
  local r, dmg = weapon.radius or 0, weapon.damage or 0
  local hits = Physics.blast(impact.x, impact.y, r, dmg, ctx.enemies, nil)
  for _, h in ipairs(hits) do
    d.damage = d.damage + h.damage
    d.hits = d.hits + 1
    if near_water(ctx, h.point) then d.drown = d.drown + 1 end
  end
  if #ctx.mine > 0 then
    for _, h in ipairs(Physics.blast(impact.x, impact.y, r, dmg, ctx.mine, nil)) do
      count_friendly(d, ctx, h.point, h.damage, near_water(ctx, h.point))
    end
  end
  return d
end

-- 治疗弹：打中**自己队**的单位回血（敌人治敌人、队友治队友），打在对面身上什么也不发生。
-- 回血量是定额（与实弹一致），不按距离衰减
EFFECTS.heal = function(ctx, weapon, impact)
  local d = new_delta()
  local r, amount = weapon.radius or 0, weapon.heal or 0
  for _, m in ipairs(ctx.mine) do
    if m.alive then
      local dx, dy = m.x - impact.x, m.y - impact.y
      if dx * dx + dy * dy <= r * r then d.heal = d.heal + amount end
    end
  end
  return d
end

-- 地形弹：落点长出一块圆，把土**灌到虫身上**。
-- 价值不在伤害（它没有伤害），而在"埋住"：被埋的虫子走不动，只能花弹药自救 —— 这就是牵制。
-- 预演按**理想圆**算（真实那一发每行有 ±1 子格噪声），位置误差 ≤1 子格
EFFECTS.mound = function(ctx, weapon, impact)
  local d = new_delta()
  local r = weapon.raise or 0
  local cx, cy = math.floor(impact.x), math.floor(impact.y)
  local filled = {}   -- 记下"这一炮会新长出哪些格"，用来判断谁被埋住
  for y = math.floor(cy - r), math.ceil(cy + r) do
    if y >= 1 and y <= ctx.terrain.H then
      local dy = y - cy
      local half = math.floor(math.sqrt(math.max(0, r * r - dy * dy)))
      if half > 0 then
        for x = math.max(1, cx - half), math.min(ctx.terrain.W, cx + half) do
          if not ctx.terrain:solid(x, y) then
            d.fill = (d.fill or 0) + 1
            filled[x .. "," .. y] = true
          end
        end
      end
    end
  end
  -- 谁被埋住：身体落在新增格里的都算（含自己人 —— 埋到自己人头上要扣分）。
  -- 每只**只计一次**：用局部 trapped 标记，不能拿累计的 d.trap 当判据 ——
  -- 第一只被判埋之后 d.trap 就 > 0，后面的敌人会一个个被误判成"已计过"而提前收手
  for _, e in ipairs(ctx.enemies) do
    local trapped = false
    for y = math.floor(e.y) - 5, math.floor(e.y) do
      for x = math.floor(e.x) - 1, math.floor(e.x) + 1 do
        if filled[x .. "," .. y] then trapped = true break end
      end
      if trapped then break end
    end
    if trapped then d.trap = d.trap + 1 end
  end
  for _, m in ipairs(ctx.mine) do
    if m.alive then
      for y = math.floor(m.y) - 5, math.floor(m.y) do
        if filled[math.floor(m.x) .. "," .. y] then
          if m == ctx.shooter then
            d.own_trap = d.own_trap + 1
          else
            d.mate_trap = d.mate_trap + 1
            d.mate_x = m.x  -- 记下会被埋的队友位置，供上层挪位避让
          end
          break
        end
      end
    end
  end
  return d
end

-- 天降光柱：以落点为中线的**垂直光柱**，宽 width、持续 life、每 tick 结算一次；
-- 它同时挖穿地形（"断掉一条必经之路"就是这么用的）
EFFECTS.strike = function(ctx, weapon, impact)
  local d = new_delta()
  local o = weapon.orbital or {}
  local half = (o.width or 6) / 2
  local ticks = math.floor((o.life or 3) / (o.tick or 0.5))
  for _, e in ipairs(ctx.enemies) do
    if e.alive and math.abs(e.x - impact.x) <= half then
      d.damage = d.damage + math.min(e.hp, (o.damage or 0) * ticks)
      d.hits = d.hits + 1
    end
  end
  for _, m in ipairs(ctx.mine) do
    if m.alive and math.abs(m.x - impact.x) <= half then
      count_friendly(d, ctx, m, math.min(m.hp, (o.damage or 0) * ticks), false)
    end
  end
  -- 挖穿：光柱那一列还有多少实心格（每格 1 分地记，权重很低）
  local x = math.floor(impact.x)
  for y = 1, ctx.terrain.H do
    if ctx.terrain:solid(x, y) then d.dig = d.dig + 1 end
  end
  return d
end

-- 烧穿射线：激光走直线，沿路烧地形、伤到碰到的人，一路飞到地图边界。
-- 它不需要弹道预演（速度 900、不受重力、不受风），所以这里直接按直线算
EFFECTS.beam = function(ctx, weapon, impact)
  local d = new_delta()
  local ray = impact.ray
  local r = weapon.radius or 1
  local step = 1
  local hit_any = {}
  for t = 0, ray.len, step do
    local x, y = ray.ox + ray.dx * t, ray.oy + ray.dy * t
    if x < 1 or x > ctx.terrain.W or y < 1 or y > ctx.terrain.H then break end
    -- 烧穿地形本身**不算价值**：射线会横穿整张地图，按格累加的话
    -- "对空气开一炮"也能靠烧掉的土拿高分，于是 AI 会挑着乱打。
    -- 地形照烧（物理如此），只是不记进收益
    for _, e in ipairs(ctx.enemies) do
      if e.alive and not hit_any[e] then
        local dx, dy = e.x - x, e.y - 3 - y      -- 瞄身体中段
        if dx * dx + dy * dy <= r * r then
          hit_any[e] = true
          d.damage = d.damage + (weapon.damage or 0)
          d.hits = d.hits + 1
          if near_water(ctx, e) then d.drown = d.drown + 1 end
        end
      end
    end
    -- 射线同样会伤到自己队：漏掉这一段的话，AI 会挑着"穿过队友"的角度打激光
    for _, m in ipairs(ctx.mine) do
      if m.alive and not hit_any[m] then
        local dx, dy = m.x - x, m.y - 3 - y
        if dx * dx + dy * dy <= r * r then
          hit_any[m] = true
          count_friendly(d, ctx, m, weapon.damage or 0, near_water(ctx, m))
        end
      end
    end
  end
  return d
end

-- ---------- 评分：delta × 权重 ----------

-- 弹药机会成本：**无状态定价**（稀缺度）。剩得越少越贵，无限弹几乎免费。
-- 只剩一个敌人时全体打折：都到最后了，好弹留着不如用掉
local function ammo_cost(weapon, ctx)
  local w = AI.WEIGHTS
  local n = weapon.ammo or 0
  local cost = (n < 0) and w.ammo_free or (w.ammo / math.max(1, n))
  if #ctx.enemies <= 1 then cost = cost * 0.5 end
  return cost
end

local function nearest(x, y, list)
  local near = 9999
  for _, t in ipairs(list) do
    if t.alive then
      local dx, dy = t.x - x, t.y - y
      local d = math.sqrt(dx * dx + dy * dy)
      if d < near then near = d end
    end
  end
  return near
end

local function score_of(delta, weapon, near, ctx, blocked)
  local w = AI.WEIGHTS
  local mult = weapon.ai_mult or 1   -- 预演只看得到一枚的武器（散射/集束）在数据里声明这个折扣
  local s = delta.damage * mult * w.damage
            + delta.hits * mult * w.hit
            + delta.heal * w.heal
            + delta.drown * w.drown
            + delta.trap * w.trap
            + math.min(delta.dig, w.dig_cap) * w.dig
            - delta.own_damage * mult * w.self
            - delta.own_drown * w.drown
            - delta.own_trap * w.trap
            - delta.mate_damage * mult * w.mate
            - delta.mate_drown * w.drown
            - delta.mate_trap * w.trap
            -- 打到队友再扣一笔定额（与伤害多少无关）：把"会误伤"整体压下去，
            -- 让它只在战果明显更大时才被选中
            - ((delta.mate_damage > 0 or delta.mate_drown > 0 or delta.mate_trap > 0)
               and w.mate_flat or 0)
            - math.min(near, w.near_cap) * w.near
            - (blocked and w.blocked or 0)   -- 抛物线被地形挡住：这一炮等于白打
  return s - ammo_cost(weapon, ctx)
end

-- 一句话说明"它为什么赢"：写进日志与观察口，人读得懂，agent 也能匹配
local function reason_of(weapon, delta, blocked)
  local parts = {}
  if blocked then parts[#parts + 1] = "被挡" end
  if delta.damage > 0 then parts[#parts + 1] = string.format("伤%d", math.floor(delta.damage + 0.5)) end
  if delta.heal > 0 then parts[#parts + 1] = string.format("回%d", math.floor(delta.heal + 0.5)) end
  if delta.trap > 0 then parts[#parts + 1] = string.format("埋%d", delta.trap) end
  if delta.drown > 0 then parts[#parts + 1] = string.format("入水%d", delta.drown) end
  if delta.dig > 0 and #parts == 0 then parts[#parts + 1] = string.format("挖%d", delta.dig) end
  if delta.own_damage > 0 then parts[#parts + 1] = string.format("自伤%d", math.floor(delta.own_damage + 0.5)) end
  if delta.mate_damage > 0 then parts[#parts + 1] = string.format("误伤%d", math.floor(delta.mate_damage + 0.5)) end
  if #parts == 0 then parts[#parts + 1] = "封路" end
  return weapon.id .. " " .. table.concat(parts, " ")
end

-- ---------- 规划器：持有候选队列，可分帧推进 ----------
local Planner = {}
Planner.__index = Planner

-- 开始规划。allowed 是"这只虫子现在能用的武器表"（由上层给：有没有弹药、用不用得上）
function AI.plan_begin(shooter, all_worms, terrain, wind, difficulty, allowed)
  local cfg = AI.DIFFICULTY[difficulty or "normal"]
  -- shooter 也放进 ctx：效果函数要分清"这一炮伤到的是射手本人还是队友"
  local ctx = { terrain = terrain, wind = wind, shooter = shooter,
                enemies = {}, mine = {}, wounded = {} }
  for _, w in ipairs(all_worms) do
    if w.alive then
      if w.team == shooter.team then
        ctx.mine[#ctx.mine + 1] = w
        if w.hp <= Worms.MAX_HP * AI.WOUNDED_RATIO then ctx.wounded[#ctx.wounded + 1] = w end
      else
        ctx.enemies[#ctx.enemies + 1] = w
      end
    end
  end
  if #ctx.enemies == 0 then return nil end

  local jobs = {}
  for _, spec in ipairs(allowed or {}) do
    local weapon = (type(spec) == "table") and spec or Weapons.by_id(spec)
    -- 能不能用，由武器表自己说（ai 字段）：throw 参战、self 只对自己用、false 不用
    if weapon and weapon.ai ~= false and weapon.ai ~= "self" then
      -- 有目标才试：治疗弹的"目标"是伤员，其余是敌人。
      -- 筛选只由武器表与目标表决定；"值不值"（扎堆几只、伤员几个）交给评分说话
      local targets = (weapon.effect == "heal") and ctx.wounded or ctx.enemies
      local plan = PLANS[weapon.plan or "arc"]
      if plan and #targets > 0 then
        for _, aim in ipairs(plan.jobs(weapon, cfg)) do
          jobs[#jobs + 1] = { weapon = weapon, aim = aim }
        end
      end
    end
  end
  if #jobs == 0 then return nil end

  return setmetatable({
    shooter = shooter, ctx = ctx, wind = wind, cfg = cfg,
    jobs = jobs, index = 1, phase = 1, best = nil, top = {}, done = false,
  }, Planner)
end

-- 推进最多 batch 组预演。返回 true 表示已经算完（可以取结果了）
function Planner:advance(batch)
  batch = batch or AI.BATCH
  local spent = 0
  while self.index <= #self.jobs and spent < batch do
    local job = self.jobs[self.index]
    self.index = self.index + 1
    spent = spent + 1
    local weapon, aim = job.weapon, job.aim
    local plan = PLANS[weapon.plan or "arc"]
    local targets = (weapon.effect == "heal") and self.ctx.wounded or self.ctx.enemies

    local impact = plan.impact(self.ctx, self.shooter, weapon, aim)
    local delta = EFFECTS[weapon.effect or "blast"](self.ctx, weapon, impact)
    -- 求解器自己给出"离目标多近"时以它为准：射线没有落点，拿炮口到目标的距离当 near
    -- 会得出几百子格，于是激光的"够不着"判断永远为真（它会站在那儿对空气开炮）
    local near = impact.near
        or nearest(impact.x or self.shooter.x, impact.y or self.shooter.y, targets)
    local blocked = impact.blocked   -- 抛物线被地形挡住（见 preview）
    local score = score_of(delta, weapon, near, self.ctx, blocked)

    local cand = { weapon = weapon, aim = aim, score = score, near = near,
                   blocked = blocked, delta = delta,
                   reason = reason_of(weapon, delta, blocked),
                   -- 误伤标记与被打到的队友位置：上层据此先尝试挪位避让
                   mate = (delta.mate_damage > 0 or delta.mate_drown > 0 or delta.mate_trap > 0),
                   mate_x = delta.mate_x }
    if not self.best or score > self.best.score then self.best = cand end
    -- 留下前几名：观察口能看到"它都考虑过什么"，出问题时不必猜
    self.top[#self.top + 1] = cand
    if #self.top > 12 then table.remove(self.top, 1) end
  end

  if self.index > #self.jobs then
    if self.phase == 1 and self.cfg.refine and self.best then
      -- 精修一遍：围着粗扫找到的那一组细看（射线同样适用）
      local plan = PLANS[self.best.weapon.plan or "arc"]
      if plan.refine then
        local b, cfg = self.best, self.cfg
        local refined = {}
        if b.weapon.plan == "ray" then
          -- 激光是没风偏的直线，粗扫 4° 一格太糙：围着最优解 0.5° 一格细修，
          -- 否则"算准了却差半度"会一路放大成目标旁好几格（力度对它无意义，只修角度）
          for angle = b.aim.angle - cfg.a_step, b.aim.angle + cfg.a_step, 0.5 do
            refined[#refined + 1] = { angle = angle, power = 1.0 }
          end
        else
          for angle = b.aim.angle - cfg.a_step, b.aim.angle + cfg.a_step, 2 do
            for power = math.max(0.15, b.aim.power - cfg.p_step),
                          Physics.clamp_power(b.aim.power + cfg.p_step), 0.02 do
              refined[#refined + 1] = { angle = angle, power = power }
            end
          end
        end
        if #refined > 0 then
          self.jobs = {}
          for _, aim in ipairs(refined) do
            self.jobs[#self.jobs + 1] = { weapon = b.weapon, aim = aim }
          end
          self.index, self.phase = 1, 2
          return false
        end
      end
    end
    self.done = true
  end
  return self.done
end

-- 结果：加瞄准误差。AI 强在"会算"，弱在"手抖"，而不是物理作弊。
-- phos.sys.random 只收整数，所以先把误差换算成"十分之一度 / 千分之一力度"
function Planner:result()
  local b, cfg = self.best, self.cfg
  if not b then return nil end
  -- 激光是没风偏的直线：同样的角度抖动会被距离放大成好几格的横向偏移，
  -- 所以人工手抖按 RAY_AIM_SCALE 压小（这也是"AI 的激光怎么老歪"的来历）
  local spread = (b.weapon.plan == "ray") and AI.RAY_AIM_SCALE or 1.0
  local aj, pj = math.floor(cfg.angle * 10 * spread), math.floor(cfg.power * 1000)
  return {
    weapon = b.weapon,
    angle = b.aim.angle + phos.sys.random(-aj, aj) / 10,
    power = Physics.clamp_power(b.aim.power + phos.sys.random(-pj, pj) / 1000),
    near = b.near,
    -- blocked 必须一起交出去：上层靠它判"这一炮是不是白打（要不要先换个位置）"。
    -- 漏掉这个字段的话，上层读到的永远是 nil，那条判断就成了摆设
    blocked = b.blocked,
    reason = b.reason,
    -- 误伤信息交给上层：它会先尝试挪位避让（见 main.lua 的 update_ai）
    mate = b.mate,
    mate_x = b.mate_x,
  }
end

-- 给观察口用：当前排在前面的几个候选（武器 + 一句话理由），人读得懂
function Planner:top_lines(count)
  local sorted = {}
  for _, c in ipairs(self.top) do sorted[#sorted + 1] = c end
  table.sort(sorted, function(a, b) return a.score > b.score end)
  local out = {}
  for i = 1, math.min(count or 3, #sorted) do out[i] = sorted[i].reason end
  return out
end

return AI

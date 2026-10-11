-- worms.lua —— 虫子：血量与状态机。不读键盘、不绘制、不发声
--
-- 一只虫子由上层用"意图"驱动（move / jump），这里只判定"能不能这么做"，
-- 并推进自己的状态：走路、爬坡、跳跃、坠落、受伤、淹死。
-- 坐标用"脚下中心点"（子格），这样站立判定就是"正下方那几格有没有实心"。

local Physics = require("physics")
local Weapons = require("weapons")

local Worms = {}
Worms.__index = Worms

Worms.MAX_HP = 100
Worms.WALK_SPEED = 10      -- 子格/秒（= 5 格/秒）
-- 空中水平速度：比地面慢（约七成），但**不为零**——起跳后还能左右微调，落点才控得住
Worms.AIR_SPEED = 7        -- 子格/秒
-- 起跳初速（负值 = 向上）。跳跃高度 = v²/2g，14 对应 ≈4 子格（2 格）：
-- 够翻过一块台阶、够离开脚下的爆炸圈，但不足以变成"飞"
Worms.JUMP_VY = -14
Worms.HIT_RADIUS = 3       -- 被弹药命中的判定半径（子格）
-- 身体高度（子格）。半格小人：宽 1 子格、高 2 子格（= 半格宽 × 一格高，
-- 画出来就是 `▌` / `▐` 那一个块）。判定与字形同尺寸 —— 这是"不多出半格"的前提
Worms.BODY_H = 2
-- 一步能迈上去的高度（子格）：地面比脚高这么多以内就迈上去，再高算墙，得跳。
-- 一格 = 2 子格，所以 2 = "一格台阶"。行走、贴地、落点判定全用这一个数
Worms.STEP_SUB = 2
-- 阵亡爆炸：谁倒下都会炸一下（最高 50），波及身边单位 —— 于是"残血扎堆"要付代价。
-- 但**伤害不在这里结算**：只把死讯报给上层（on_death），由它排队统一处理。
-- 在伤害函数里直接炸的话，"爆炸→死人→再爆炸"会一层层递归进去，
-- 而且爆炸还要特效、浮字与声音，那些都属于表现层
Worms.DEATH_RADIUS, Worms.DEATH_DAMAGE = 8, 50

-- 洗牌：出生站位与队内出场顺序都要随机（用主机的 RNG，跟种子一起可复现）
local function shuffle(t)
  for i = #t, 2, -1 do
    local j = phos.sys.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
end

local function make(team, x, y)
  return {
    team = team,
    x = x, y = y,               -- 脚下中心（子格）
    body_h = Worms.BODY_H,      -- 身体高度：爆炸按"身体最近的一段"算距离（Physics.blast）
    vy = 0,
    hp = Worms.MAX_HP,
    alive = true,
    on_ground = true,
    fall_from = nil,
    facing = (team == 1) and 1 or -1,
    angle = 45,                 -- 瞄准角度（度，可以为负 = 朝下打）
    -- power 不在这里定：默认力度属于"操作手感"，由装配层（main.lua 的
    -- DEFAULT_POWER）给，弹药也一样。这里只管虫子的物理状态
    power = nil,
    -- 弹药**按虫各记各的**：同一件武器，这只虫的份额不会被队友用掉
    ammo = Weapons.start_ammo(),
  }
end

-- 部署两队：一队在左三分之一、一队在右三分之一。
-- counts 是 { 我方人数, 敌方人数 }（传一个数字表示两边一样多）。
-- 每个人数都走 terrain:spawn_spot —— 它会**先把脚下压平**再放虫，
-- 所以"随机地形 + 出生即卡死在石头里"这件事不会发生。
--
-- 站位与**队内出场顺序**都洗牌。按序号从左到右排的话，谁站在哪、第几个上场
-- 都是开局就写死的："对面的第一只永远在最左边"这种规律不该存在，
-- 它让第一炮的目标变得可预测，也让每局开局的走位一模一样
function Worms.new(terrain, counts)
  local self = setmetatable({}, Worms)
  self.terrain = terrain
  self.list = {}
  local n = { 4, 4 }
  if type(counts) == "table" then
    n = { counts[1] or 4, counts[2] or 4 }
  elseif type(counts) == "number" then
    n = { counts, counts }
  end
  for team = 1, 2 do
    -- 先把这一队的三分之一切成等距的坑位（保证两两之间留出空地，不会叠在一起），
    -- 再把坑位洗牌：位置随机，但间距仍然均匀
    local span = terrain.W // 3
    local base = (team == 1) and 0 or (terrain.W - span)
    local step = span // (n[team] + 1)
    local slots = {}
    for i = 1, n[team] do
      slots[i] = base + i * step
    end
    shuffle(slots)
    local squad = {}
    for i = 1, n[team] do
      local gx, gy = terrain:spawn_spot(slots[i])
      -- 坑位落在水上时 spawn_spot 不给位置：换几处随机点再试，别把这只虫弄丢
      for _ = 1, 4 do
        if gx then break end
        gx, gy = terrain:spawn_spot(phos.sys.random(base + 4, base + span - 4))
      end
      if gx then squad[#squad + 1] = make(team, gx, gy) end
    end
    -- 出场顺序再洗一次：站位随机与上场顺序是两件独立的事
    shuffle(squad)
    for _, w in ipairs(squad) do self.list[#self.list + 1] = w end
  end
  return self
end

function Worms:of_team(team)
  local out = {}
  for _, w in ipairs(self.list) do
    if w.alive and w.team == team then out[#out + 1] = w end
  end
  return out
end

-- 该队里排在 after 之后的第一只活虫。回合换手用它，**不是每次都抓第一只**：
-- 一条命从头用到尾的话，队友像不存在，玩家也永远看不到别的虫子在哪。
function Worms:next_of_team(team, after)
  local list = self:of_team(team)
  if #list == 0 then return nil end
  if not after then return list[1] end
  local seen = false
  for _, w in ipairs(list) do
    if seen then return w end
    if w == after then seen = true end
  end
  return list[1]        -- 已经是最后一个（或它已阵亡）→ 绕回第一个
end

function Worms:alive_count(team) return #self:of_team(team) end

-- 身体在 (x, y) 这个位置上与实心重叠吗：**一列** × body_h 行。
-- 身体与半格字形同宽（1 子格），所以判定也用一列 —— 多算一列就等于"身体比看到的大半格"，
-- 那正是"离墙还差半格却过不去"和"卡进地块"的来源
function Worms:body_hits(w, x, y)
  local bh = w.body_h or Worms.BODY_H
  local feet = math.floor(y)
  local col = math.floor(x)
  for sy = feet - bh + 1, feet do
    if self.terrain:solid(col, sy) then return true end
  end
  return false
end

-- 脚下那一行有实心就算站得住（半格小人只认自己那一列：边沿掉下去是重力的事）
function Worms:supported(w, x, y)
  return self.terrain:solid(math.floor(x), math.floor(y) + 1)
end

-- 站在 x 处时脚该落的**落脚行**：在脚行上下各一步的窗口里找"本身空、下一行有实心"的行。
-- 两条要点：
--   * 窗口上下各一步，所以不超过一步的台阶能一级级走上去；更陡的墙落在窗口外
--   * **不以"身体是否重叠"为前提**：迈上台阶的那一刻身体正与新地形重叠，
--     先否决就等于"卡在台阶里"。校正 y 本来就是为了解除那次重叠
function Worms:stand_row(w, x)
  local col = math.floor(x)
  local feet = math.floor(w.y)
  return self.terrain:foot_row_in(col, col, feet - Worms.STEP_SUB, feet + Worms.STEP_SUB)
end

-- 走：地面上是常速，**空中也能微调**（略慢）。空中可动是要紧的：起跳后若水平冻结，
-- "走 + 跳"就是两次互不相干的操作，落点只好在起跳那一帧定死——手感差的大半来源在这儿。
-- 进邻格时 **x 与 y 同一帧一起改**：分两帧做的话，中间那一帧身体正卡在台阶里
function Worms:move(w, dir, dt)
  if not w.alive then return false end
  local speed = w.on_ground and Worms.WALK_SPEED or Worms.AIR_SPEED
  local nx = w.x + dir * speed * dt
  if nx < 3 or nx > self.terrain.W - 3 then w.facing = dir return false end
  w.facing = dir

  local gy = self:stand_row(w, nx)
  if gy then
    -- 邻格能站：身体放得下就进，进去的同时把脚落到那一行
    if self:body_hits(w, nx, gy) then return false end
    w.x, w.y = nx, gy
    return true
  end
  -- 邻格在一步之内没有能站的位置：脚行是空的 = 悬崖（走过去，落下交给重力）；
  -- 脚行是土 = 高过一步的墙
  if self:body_hits(w, nx, w.y) then return false end
  w.x = nx
  return true
end

-- 跳：站着、且身体不在土里才跳得动。埋住时跳不动是本条规则的自然结果 ——
-- 那正是"头顶的土得自己炸开"的效果，不需要另记一个状态
function Worms:jump(w)
  if not w.alive or not w.on_ground or self:body_hits(w, w.x, w.y) then
    return false
  end
  -- 上面这一条同时管住"被地形炮灌土"：那一列被土填满时身体与地形重叠，走不动也跳不动

  w.vy = Worms.JUMP_VY
  w.on_ground = false
  w.fall_from = w.y
  return true
end

-- 重力与落地。返回事件表（landed / drowned / hurt），由上层决定音效等副作用
function Worms:update(dt)
  local events = {}
  for _, w in ipairs(self.list) do
    if w.alive then
      if w.on_ground and not self:supported(w, w.x, w.y) then
        w.on_ground = false
        w.fall_from = w.y
      end
      if not w.on_ground then
        -- 头顶：身体最上面那一行有实心就顶住。没有这一步，虫子能跳进上方的土里，
        -- 再"落"在更高的一层
        local col = math.floor(w.x)
        local head = math.floor(w.y) - Worms.BODY_H + 1
        if w.vy < 0 and self.terrain:solid(col, head) then
          w.vy = 0
        end
        w.vy = w.vy + Physics.GRAVITY * dt
        w.y = w.y + w.vy * dt
        -- 落地：脚下有支撑、身体也不再与地形重叠。落在**窗口内的落脚行**上，
        -- 不再对浮点取整 —— 取整会把角色压进土里，而"身体在土里"接着就是走不动跳不动
        if w.vy >= 0 and self:supported(w, w.x, w.y) and not self:body_hits(w, w.x, w.y) then
          local dmg = Physics.fall_damage(w.y - (w.fall_from or w.y))
          w.y = self:stand_row(w, w.x) or math.floor(w.y)
          w.vy, w.on_ground, w.fall_from = 0, true, nil
          if dmg > 0 then
            self:damage(w, dmg)
            events[#events + 1] = { kind = "landed", worm = w, damage = dmg }
          end
        end
      else
        -- 贴地：**脚永远落在所在格的落脚行上**（走下坡的落差也在这里坠下去）
        local gy = self:stand_row(w, w.x)
        if gy then
          w.y = gy
        elseif not self:supported(w, w.x, w.y) then
          w.on_ground, w.fall_from = false, w.y
        end
      end
      -- 只作**读数**（HUD 提示"被埋住，炸开脱身"、观察口一项）：行为一律由身体矩形的
      -- 几何决定，不许再拿它去闸行走或跳跃 —— 那会把一次错位变成永久状态
      w.buried = self:body_hits(w, w.x, w.y)
      if w.y >= self.terrain.WATER_Y then
        self:kill(w)
        events[#events + 1] = { kind = "drowned", worm = w }
      end
    end
  end
  return events
end

-- 死亡裁决的**唯一入口**：标记阵亡，并把死讯报给上层（阵亡爆炸）。
-- 直伤与落海都从这里过，所以"谁死了"只有一个地方说了算
function Worms:kill(w)
  if not w.alive then return end
  w.hp, w.alive = 0, false
  if self.on_death then self.on_death(w) end
end

function Worms:damage(w, amount)
  if not w.alive or amount <= 0 then return end
  w.hp = w.hp - amount
  if w.hp <= 0 then self:kill(w) end
end

-- 回血：上限 Worms.MAX_HP。返回**实际回了多少**，上层据此决定要不要冒浮字
-- （血满时为 0，于是不会有数字）
function Worms:heal(w, amount)
  if not w.alive or amount <= 0 then return 0 end
  local before = w.hp
  w.hp = math.min(Worms.MAX_HP, w.hp + amount)
  return w.hp - before
end

-- 爆炸结算：伤害 + 冲量（把人往外推；推完交给 update 的重力继续算）。
-- skip 是"已经被直接命中、拿过全额伤害"的那只虫：爆炸不该再按距离削它一次，
-- 否则同一发弹药对同一目标会结算两遍
function Worms:apply_blast(x, y, radius, damage, events, skip)
  local points = {}
  for _, w in ipairs(self.list) do
    if w.alive and w ~= skip then points[#points + 1] = w end
  end
  local hits = Physics.blast(x, y, radius, damage, points, self.terrain)
  for _, h in ipairs(hits) do
    local w = h.point
    self:damage(w, h.damage)
    local dx, dy = w.x - x, w.y - y
    local d = math.max(1, math.sqrt(dx * dx + dy * dy))
    w.x = w.x + dx / d * h.push * 0.5
    w.y = w.y + dy / d * h.push * 0.5
    w.on_ground, w.fall_from = false, w.y
    self:push_out(w)
    events[#events + 1] = { kind = "hit", worm = w, damage = h.damage }
  end
  return hits
end

-- 冲量可能把角色推进实心里。这里**按事件**把它推开一次就够：被推进土里是一次事件，
-- 修正它是一次几何结算。每帧都推是另一回事 —— 那会让人贴着墙时永远被挪开，
-- 于是"上台阶"被自己的推墙逻辑判死
function Worms:push_out(w)
  if not self:body_hits(w, w.x, w.y) then return end
  for step = 1, 8 do
    for _, dir in ipairs({ -1, 1 }) do
      local nx = w.x + dir * step * 0.5
      if not self:body_hits(w, nx, w.y) then
        w.x = nx
        return
      end
    end
  end
end

function Worms:team_wiped(team) return self:alive_count(team) == 0 end

return Worms

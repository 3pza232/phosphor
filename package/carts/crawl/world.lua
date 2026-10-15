-- world.lua —— 局面状态机（DESIGN §1/§4/§5/§10）。
--
-- 这里把各系统串起来：能量调度器驱动回合、玩家动作 → 怪物按 speed 行动、
-- 进层/下楼、胜负判定、消息日志。**只持有状态与规则，不绘制、不发声音**——
-- 玩法事件以 `events` 表返回，音效由 main.lua 触发（原则见 §13）。
--
-- 依赖单向：world → { map, fov, ai, combat, monsters, items, rng }。叶子模块互不相识。

local Map = require("map")
local Fov = require("fov")
local AI = require("ai")
local Combat = require("combat")
local Monsters = require("monsters")
local Items = require("items")
local Rng = require("rng")

local World = {}
World.__index = World

-- 可调难度旋钮（DESIGN §20）：挂在 `~` 调试台上实时改。放在模块字段上，
-- 生成/结算路径直接读，不必层层传参。
World.HP_MULT = 1.0     -- 怪物生命倍率
World.ATK_MULT = 1.0    -- 玩家攻击倍率
World.DROP_MULT = 1.0   -- 掉落金币倍率

local Text = {
  zh = {
    hit = "%s击中%s，-%d HP。", hurt = "%s咬中你，-%d HP。", ranged = "%s掷出一团磷火，-%d HP。",
    miss_self = "你挥空了。", miss_mon = "%s扑空了。", kill = "%s倒下了。",
    gold = "你拾起 %d 金币。", pickup = "你拾起 %s。",
    equip = "你换上了 %s（%s +%d）。", better = "你已有的装备更好。",
    levelup = "升级！你达到 %d 级。",
    oil = "你倒空油瓶，灯又亮了。", lightout = "灯灭了。黑暗正在合拢……",
    potion = "你喝下药水，伤口愈合。", ration = "你吃下干粮，恢复了些许。",
    blink = "你闪现到了别处。", shock = "冲击波扫过，%d 只怪物受创。",
    flame = "烈焰吞没了 %s。", mapreveal = "卷轴展开，本层布局尽收眼底。",
    descend = "你走下楼梯，进入第 %d 层。", drain = "怨灵吸走了你的光，-5 灯油。",
    summon = "守望者张开骨骸之门！", enrage = "守望者的磷火暴燃！",
    win = "你握住了磷之心。地牢在身后崩塌。",
    no_stairs = "这里没有楼梯。", inv_full = "背包满了。", deep = "已是最深处，无处可退。",
    blocked = "那边是岩壁。", split = "%s分裂了！", atk = "攻", def = "防",
  },
  en = {
    hit = "%s hits %s, -%d HP.", hurt = "%s bites you, -%d HP.", ranged = "%s hurls a phosphor bolt, -%d HP.",
    miss_self = "You swing and miss.", miss_mon = "%s lunges but misses.", kill = "%s falls.",
    gold = "You pick up %d gold.", pickup = "You pick up %s.",
    equip = "You equip %s (%s +%d).", better = "Your current gear is better.",
    levelup = "Level up! You reach level %d.",
    oil = "You refill the lantern; it burns bright.", lightout = "The light dies. Darkness closes in…",
    potion = "You drink the potion; wounds close.", ration = "You eat the rations.",
    blink = "You blink elsewhere.", shock = "The shockwave hits %d monsters.",
    flame = "Flames consume %s.", mapreveal = "The scroll reveals the floor.",
    descend = "You descend to floor %d.", drain = "The wraith drains your light, -5 fuel.",
    summon = "The Warden opens a gate of bone!", enrage = "The Warden's phosphor flares!",
    win = "You grasp the Phosphor Heart. The dungeon collapses behind you.",
    no_stairs = "There are no stairs here.", inv_full = "Your pack is full.", deep = "Nothing lies deeper.",
    blocked = "Solid rock.", split = "%s splits!", atk = "ATK", def = "DEF",
  },
}
local YOU = { zh = "你", en = "You" }

local function L() return phos.lang.dict(Text) end
local function you() return phos.lang.pick(YOU) end

-- ---------- 构造 ----------

function World.new(opts)
  local w = setmetatable({}, World)
  w.seed = opts.seed
  w.best_score = opts.best_score or 0
  w.best_depth = opts.best_depth or 0
  w.events = {}
  w.log = {}
  w:start_run()
  return w
end

function World:start_run()
  self.p = {
    x = 0, y = 0, hp = 24, max_hp = 24, atk = 5, def = 1,
    level = 1, xp = 0, gold = 0, fuel = 100,
    weapon = nil, armor = nil, inv = {}, energy = 0,
  }
  self.depth = 0
  self.turn = 0
  self.alive = true
  self.won = false
  self.won_reported = false
  self.died_reported = false
  self.log = {}
  self.events = {}
  self.warden = nil
  self.warden_enraged = false
  self:emit("start")
  self:generate_floor(1)
end

-- ---------- 生成一层 ----------

function World:emit(kind, data)
  self.events[#self.events + 1] = { kind = kind, data = data }
end

function World:take_events()
  local e = self.events
  self.events = {}
  return e
end

function World:say(text, tone)
  local entry = { text = text, tone = tone or "white", turn = self.turn }
  table.insert(self.log, 1, entry)
  while #self.log > 64 do table.remove(self.log) end
end

function World:monster_at(x, y)
  for _, m in ipairs(self.monsters or {}) do
    if m.x == x and m.y == y and m.hp > 0 then return m end
  end
  return nil
end

function World:item_at(x, y)
  for i, it in ipairs(self.items or {}) do
    if it.x == x and it.y == y then return it, i end
  end
  return nil
end

function World:gold_at(x, y)
  for _, g in ipairs(self.gold or {}) do
    if g.x == x and g.y == y then return g end
  end
  return nil
end

function World:add_gold(x, y, amount)
  if amount <= 0 then return end
  local g = self:gold_at(x, y)
  if g then g.amount = g.amount + amount
  else self.gold[#self.gold + 1] = { x = x, y = y, amount = amount } end
end

function World:add_item(kind, def, x, y)
  self.items[#self.items + 1] = { kind = kind, def = def, x = x, y = y }
end

function World:generate_floor(depth)
  self.depth = depth
  -- 累计回合不因下楼清零（顶栏 TURN 是整局），因此这里不动 self.turn
  self.map = Map.new(depth, Rng)
  self.monsters = {}
  self.items = {}
  self.gold = {}
  self.warden = nil
  self.warden_enraged = false
  self.p.x, self.p.y = self.map.spawn.x, self.map.spawn.y

  local function occupied(x, y)
    if self:monster_at(x, y) or self:item_at(x, y) or self:gold_at(x, y) then return true end
    if self.map.stairs.x == x and self.map.stairs.y == y then return true end
    if self.p.x == x and self.p.y == y then return true end
    return false
  end

  -- Boss 层：守望者占据 Boss 房中心（先落位，其余怪避开它）
  if depth == 10 and self.map.boss then
    local b = self.map.boss
    local warden = Monsters.make(Monsters.spec("warden"), b.cx, b.cy, World.HP_MULT)
    self.monsters[#self.monsters + 1] = warden
    self.warden = warden
  end

  -- 怪物：数量随深度增长；距起点 > 6 格（避免开局贴脸）
  local count = math.min(18, math.max(5, 5 + math.floor(depth * 1.1)))
  local regular = count - (self.warden and 1 or 0)
  local boss_minions = { { w = 3, id = "golem" }, { w = 7, id = "orc" }, { w = 8, id = "skeleton" } }
  for _ = 1, regular do
    local spec
    if depth == 10 then
      spec = Monsters.spec(Rng.weighted(boss_minions).id)
    else
      spec = Monsters.pick(depth, Rng)
    end
    local x, y = self.map:random_floor(Rng, { from = self.p, min_dist = 6, occupied = occupied })
    if x then
      self.monsters[#self.monsters + 1] = Monsters.make(spec, x, y, World.HP_MULT)
    end
  end

  -- 金币堆：2 + rng(0,3) 处，值 = rng(5,12)×深度（下限 5）
  for _ = 1, 2 + Rng.int(0, 3) do
    local x, y = self.map:random_floor(Rng, { occupied = occupied })
    if x then self:add_gold(x, y, math.max(5, Rng.int(5, 12) * depth)) end
  end

  -- 消耗品：3 + rng(0,2)，保底 1~2 个灯油（§9.3）
  local total = 3 + Rng.int(0, 2)
  local oils = 1 + Rng.int(0, 1)
  for i = 1, total do
    local spec = (i <= oils) and Items.spec("oil") or Items.pick_consumable(Rng)
    local x, y = self.map:random_floor(Rng, { occupied = occupied })
    if x then self:add_item("consumable", spec, x, y) end
  end

  -- 装备：45% 概率 1 件（解锁深度 ≤ depth）
  if Rng.chance(0.45) then
    local spec = Items.pick_equipment(depth, Rng)
    if spec then
      local x, y = self.map:random_floor(Rng, { occupied = occupied })
      if x then self:add_item("equipment", spec, x, y) end
    end
  end

  self:recompute_fov()
end

-- ---------- 视野与感知 ----------

function World:perception()
  local r = Fov.radius(self.p.fuel)
  local base = 8
  if r >= 9 then base = base + 2       -- 灯亮：怪物也看得远（§7.3）
  elseif self.p.fuel == 0 then base = base - 2 end
  return base
end

function World:recompute_fov()
  self.radius = Fov.radius(self.p.fuel)
  self.vis, self.visible_count = Fov.compute(self.map, self.p.x, self.p.y, self.radius)
  self.perception_range = self:perception()
end

function World:visible(x, y)
  return self.vis and self.vis[y] and self.vis[y][x] or false
end

-- ---------- 能量调度器（§4） ----------

function World:advance_tick()
  self.turn = self.turn + 1
  self.p.energy = self.p.energy - 100
  if self.p.fuel > 0 then
    self.p.fuel = self.p.fuel - 1
    if self.p.fuel == 0 then
      self:say(L().lightout, "red")
      self:emit("lightout")
    end
  end

  -- 所有实体获得本 tick 的能量
  self.p.energy = self.p.energy + 100
  for _, m in ipairs(self.monsters) do m.energy = m.energy + m.speed end

  -- 守望者召唤（每 12 个玩家动作一次）
  if self.warden and self.warden.hp > 0 and self.turn % 12 == 0 then
    self:warden_summon(self.warden)
  end

  local ctx = self:ai_ctx()
  -- 取能量最高且 ≥100 的实体；玩家同能量优先（同速怪不会抢拍，§4）
  while self.alive and not self.won do
    local best, bestE
    for _, m in ipairs(self.monsters) do
      if m.energy >= 100 and (not bestE or m.energy > bestE) then best, bestE = m, m.energy end
    end
    if self.p.energy >= 100 and (not bestE or self.p.energy >= bestE) then break end
    if not best then break end
    self:monster_turn(best, ctx)
    best.energy = best.energy - 100
  end

  self:recompute_fov()
end

function World:ai_ctx()
  return {
    w = self.map.w, h = self.map.h,
    player = self.p,
    perception = self.perception_range or 8,
    walkable = function(x, y) return self.map:walkable(x, y) end,
    blocks = function(x, y) return self.map:blocks_sight(x, y) end,
    occ = function(x, y) return self:monster_at(x, y) ~= nil end,
  }
end

function World:monster_turn(m, ctx)
  if m.hp <= 0 then return end
  local intent = AI.decide(m, ctx, Rng)
  if intent.kind == "attack" then
    self:monster_strike(m, false)
  elseif intent.kind == "ranged" then
    self:monster_strike(m, true)
  elseif intent.kind == "move" then
    local nx, ny = m.x + intent.dx, m.y + intent.dy
    -- 怨灵可穿墙（§6/§8.1）：phase 怪把墙当作可走；其余怪仍被墙挡住。
    local passable = m.phase or self.map:walkable(nx, ny)
    local blocked = (not passable) or self:monster_at(nx, ny)
      or (nx == self.p.x and ny == self.p.y)
    if not blocked then m.x, m.y = nx, ny end
  end
end

function World:monster_strike(m, ranged)
  local A = m.atk
  local D = Combat.eff_def(self.p)
  local hit, dmg = Combat.roll(A, D, Rng)
  local t = L()
  if not hit then
    self:say(string.format(t.miss_mon, phos.lang.pick(m.name)), "gray")
    self:emit("miss")
    return
  end
  self.p.hp = self.p.hp - dmg
  if ranged then
    self:say(string.format(t.ranged, phos.lang.pick(m.name), dmg), "red")
    self:emit("ranged")
  else
    self:say(string.format(t.hurt, phos.lang.pick(m.name), dmg), "red")
    self:emit("hurt")
  end
  if m.drain and self.p.fuel > 0 then
    self.p.fuel = math.max(0, self.p.fuel - m.drain)
    self:say(t.drain, "purple")
    self:emit("drain")
  end
  if self.p.hp <= 0 then
    self.p.hp = 0
    self.alive = false
    self:emit("death")
  end
end

function World:warden_summon(w)
  for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
    local x, y = w.x + d[1], w.y + d[2]
    if self.map:walkable(x, y) and not self:monster_at(x, y)
       and not (x == self.p.x and y == self.p.y) then
      self.monsters[#self.monsters + 1] = Monsters.make(Monsters.spec("skeleton"), x, y, World.HP_MULT)
      self:say(L().summon, "yellow")
      self:emit("summon")
      return
    end
  end
end

function World:check_enrage()
  local w = self.warden
  if w and not self.warden_enraged and w.hp > 0 and w.hp < w.max_hp * 0.3 then
    self.warden_enraged = true
    w.atk = math.floor(w.atk * 1.5)
    w.speed = 130
    self:say(L().enrage, "red")
    self:emit("enrage")
  end
end

-- ---------- 玩家动作 ----------

function World:move(dx, dy)
  local nx, ny = self.p.x + dx, self.p.y + dy
  local m = self:monster_at(nx, ny)
  if m then
    self:player_attack(m)
    self:advance_tick()
    return true
  end
  if not self.map:walkable(nx, ny) then
    self:say(L().blocked, "dark_gray")
    return false
  end
  self.p.x, self.p.y = nx, ny
  local g = self:gold_at(nx, ny)
  if g then
    self.p.gold = self.p.gold + g.amount
    self:say(string.format(L().gold, g.amount), "yellow")
    self:emit("coin")
    for i, gg in ipairs(self.gold) do
      if gg == g then table.remove(self.gold, i); break end
    end
  end
  self:advance_tick()
  return true
end

function World:wait()
  self:advance_tick()
  return true
end

function World:player_attack(m)
  local A = math.floor(Combat.eff_atk(self.p) * World.ATK_MULT)
  local D = Combat.eff_def(m)
  local hit, dmg = Combat.roll(A, D, Rng)
  if hit then
    m.hp = m.hp - dmg
    m.awake = true
    self:say(string.format(L().hit, you(), phos.lang.pick(m.name), dmg), "white")
    self:emit("hit")
    if m.boss then self:check_enrage() end
    if m.hp <= 0 then self:kill_monster(m) end
  else
    self:say(L().miss_self, "gray")
    self:emit("miss")
  end
end

function World:kill_monster(m)
  m.hp = 0
  for i, e in ipairs(self.monsters) do
    if e == m then table.remove(self.monsters, i); break end
  end
  local xp, gold = Combat.kill_reward(m, Rng, World.DROP_MULT)
  self.p.xp = self.p.xp + xp
  self:say(string.format(L().kill, phos.lang.pick(m.name)), "white")
  self:emit("kill")
  self:add_gold(m.x, m.y, gold)

  if m.split and not m.is_slimelet and self.depth < 9 then
    local slimes = 0
    for _, e in ipairs(self.monsters) do if e.id == "slime" then slimes = slimes + 1 end end
    if slimes < 6 then
      -- 规格是"生成 2 只小软泥"（§6 / 验收用例 5）：即使四面都有空位也只放 2 只。
      local spawned = 0
      for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
        if spawned >= 2 then break end
        local x, y = m.x + d[1], m.y + d[2]
        if self.map:walkable(x, y) and not self:monster_at(x, y)
           and not (x == self.p.x and y == self.p.y) then
          self.monsters[#self.monsters + 1] = Monsters.make_slimelet(x, y)
          spawned = spawned + 1
        end
      end
      if spawned > 0 then
        self:say(string.format(L().split, phos.lang.pick(m.name)), "magenta")
        self:emit("split")
      end
    end
  end

  if m.boss then
    self.warden = nil
    self:add_item("heart", Items.HEART, m.x, m.y)
    for _ = 1, Rng.int(2, 3) do
      local spec = Items.top_tier(Rng)
      self:add_item("equipment", spec, m.x, m.y)
    end
    self:add_gold(m.x, m.y, Rng.int(150, 300))
  end

  -- 升级（可能连升，逐级写日志，§5.2）。数值结算统一走 combat.gain_levels，
  -- 避免同一张升级表在 world 里再抄一遍。
  local before = self.p.level
  local levels = Combat.gain_levels(self.p)
  for lv = before + 1, self.p.level do
    self:say(string.format(L().levelup, lv), "green")
  end
  if levels > 0 then self:emit("levelup") end
end

-- 拾取脚下物品（免费，不占 tick）。返回是否发生了拾取。
function World:pickup()
  local it = self:item_at(self.p.x, self.p.y)
  if not it then return false end
  local t = L()

  if it.kind == "heart" then
    -- 胜负道具：拾取即通关
    for i, e in ipairs(self.items) do if e == it then table.remove(self.items, i); break end end
    self.won = true
    self:say(t.win, "green")
    self:emit("win")
    return true
  end

  if it.kind == "equipment" then
    local slot = it.def.kind                -- "weapon" / "armor"
    local cur = self.p[slot]
    if not cur or it.def.bonus > cur.bonus then
      self.p[slot] = it.def
      for i, e in ipairs(self.items) do if e == it then table.remove(self.items, i); break end end
      if cur then self:add_item("equipment", cur, self.p.x, self.p.y) end   -- 旧装备掉在脚下
      local lbl = (slot == "weapon") and t.atk or t.def
      self:say(string.format(t.equip, phos.lang.pick(it.def.name), lbl, it.def.bonus), "yellow")
      self:emit("equip")
      return true
    end
    self:say(t.better, "gray")
    return false
  end

  -- 消耗品：背包满则不拾取
  if #self.p.inv >= 8 then
    self:say(t.inv_full, "orange")
    return false
  end
  for i, e in ipairs(self.items) do if e == it then table.remove(self.items, i); break end end
  self.p.inv[#self.p.inv + 1] = it.def
  self:say(string.format(t.pickup, phos.lang.pick(it.def.name)), "yellow")
  self:emit("pickup")
  return true
end

function World:descend()
  if not (self.p.x == self.map.stairs.x and self.p.y == self.map.stairs.y) then
    self:say(L().no_stairs, "gray")
    return false
  end
  if self.depth >= 10 then
    self:say(L().deep, "gray")
    return false
  end
  self:generate_floor(self.depth + 1)
  self:say(string.format(L().descend, self.depth), "cyan")
  self:emit("descend")
  self:advance_tick()
  return true
end

-- 使用背包第 i 格（占 1 tick）。返回是否用掉了。
function World:use_item(i)
  local spec = self.p.inv[i]
  if not spec then return false end
  local t = L()
  local kind = spec.kind
  if kind == "oil" then
    self.p.fuel = math.min(100, self.p.fuel + 50)
    self:say(t.oil, "green")
  elseif kind == "potion" then
    self.p.hp = math.min(self.p.max_hp, self.p.hp + 15)
    self:say(t.potion, "green")
  elseif kind == "ration" then
    self.p.hp = math.min(self.p.max_hp, self.p.hp + 6)
    self.p.fuel = math.min(100, self.p.fuel + 15)
    self:say(t.ration, "green")
  elseif kind == "blink" then
    -- 不落到怪物格上（玩家与怪物不可同格，否则实体重叠、下回合被贴脸）
    local x, y = self.map:random_floor(Rng, {
      occupied = function(cx, cy) return self:monster_at(cx, cy) ~= nil end,
    })
    if x then self.p.x, self.p.y = x, y end
    self:say(t.blink, "cyan")
  elseif kind == "shock" then
    local hit = 0
    local snapshot = {}
    for _, m in ipairs(self.monsters) do snapshot[#snapshot + 1] = m end
    for _, m in ipairs(snapshot) do
      if self:visible(m.x, m.y) then
        hit = hit + 1
        self:hurt_monster(m, 10)
      end
    end
    self:say(string.format(t.shock, hit), "orange")
  elseif kind == "map" then
    self.map:reveal_all()
    self:say(t.mapreveal, "white")
  elseif kind == "flame" then
    local best, bestd
    for _, m in ipairs(self.monsters) do
      if self:visible(m.x, m.y) then
        local d = (m.x - self.p.x) ^ 2 + (m.y - self.p.y) ^ 2
        if not bestd or d < bestd then best, bestd = m, d end
      end
    end
    if best then
      self:hurt_monster(best, 18)
      self:say(string.format(t.flame, phos.lang.pick(best.name)), "red")
    end
  end
  table.remove(self.p.inv, i)
  self:emit("use_" .. kind)
  self:advance_tick()
  return true
end

-- 对怪物造成直接伤害（卷轴类）。结算死亡与经验。
function World:hurt_monster(m, dmg)
  m.hp = m.hp - dmg
  m.awake = true
  if m.boss then self:check_enrage() end
  if m.hp <= 0 then self:kill_monster(m) end
end

-- ---------- 结算 ----------

function World:score()
  return self.p.gold + (self.depth - 1) * 150 + self.p.level * 40 + (self.p.max_hp - 24) * 5
end

-- 当前等级的经验进度（0..1），供侧栏经验条使用
function World:xp_progress()
  local cur = Combat.xp_for(self.p.level)
  local nxt = Combat.xp_for(self.p.level + 1)
  local span = math.max(1, nxt - cur)
  return math.max(0, math.min(1, (self.p.xp - cur) / span))
end

function World:explored_pct()
  local total = self.map.w * self.map.h
  return math.floor(self.map:explored_count() / total * 100)
end

-- agent / 自测观察口（DESIGN §14.2）
function World:debug()
  local monsters = {}
  for _, m in ipairs(self.monsters) do
    monsters[#monsters + 1] = {
      id = m.id, x = m.x, y = m.y, hp = m.hp, max_hp = m.max_hp,
      speed = m.speed, awake = m.awake, boss = m.boss or false,
    }
  end
  local floor_items = {}
  for _, it in ipairs(self.items) do
    floor_items[#floor_items + 1] = { id = it.def.id, x = it.x, y = it.y, kind = it.kind }
  end
  local gold = {}
  for _, g in ipairs(self.gold) do gold[#gold + 1] = { x = g.x, y = g.y, amount = g.amount } end
  local inv = {}
  for i, spec in ipairs(self.p.inv) do inv[i] = { id = spec.id, n = 1 } end
  return {
    depth = self.depth, turn = self.turn, seed = self.seed,
    score = self:score(), alive = self.alive, won = self.won,
    player = {
      x = self.p.x, y = self.p.y, hp = self.p.hp, max_hp = self.p.max_hp,
      atk = Combat.eff_atk(self.p), def = Combat.eff_def(self.p),
      level = self.p.level, xp = self.p.xp, fuel = self.p.fuel,
      light_radius = self.radius or 0, gold = self.p.gold,
      weapon = self.p.weapon and self.p.weapon.id or "none",
      armor = self.p.armor and self.p.armor.id or "none",
      inv = inv,
    },
    stairs = { x = self.map.stairs.x, y = self.map.stairs.y },
    visible_tiles = self.visible_count or 0,
    explored_pct = self:explored_pct(),
    monsters = monsters,
    items = floor_items,
    gold_piles = gold,
    last_msg = self.log[1] and self.log[1].text or "",
    best_score = self.best_score,
    -- 观察辅助：地块网格（每行一串字形）。agent 据此寻路、核对布局，不必逐格读画面。
    map = (function()
      local rows = {}
      for y = 0, self.map.h - 1 do
        local cells = {}
        for x = 0, self.map.w - 1 do cells[#cells + 1] = Map.glyph(self.map.tiles[y][x]) end
        rows[#rows + 1] = table.concat(cells)
      end
      return rows
    end)(),
    -- 观察辅助：玩家四向是否可走（agent 不必从字符画面反推地形）
    exits = {
      up = self.map:walkable(self.p.x, self.p.y - 1),
      down = self.map:walkable(self.p.x, self.p.y + 1),
      left = self.map:walkable(self.p.x - 1, self.p.y),
      right = self.map:walkable(self.p.x + 1, self.p.y),
    },
  }
end

return World

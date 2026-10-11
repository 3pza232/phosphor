-- supply.lua —— 空投补给：每 N 回合从天上落下一箱弹药
--
-- 一个周期只有三步，全在这一个文件里，不散到玩法层：
--   落下（挂着降落伞慢慢飘）→ 落地（伞消失，箱子留在原地）→ 谁走到就归谁
-- 落地后 LIFETIME 回合没人捡，箱子自己消失——不让地图上堆一排没人要的箱子。
--
-- 箱子里是**随机一件限量武器**（普通炮弹是无限兜底弹，空投它没有意义），
-- 捡到的人按 spec.supply 补几发；浮字与音效由上层给（这里只改数据）
--
-- 这里**不绘制**：箱子的样子在 main.lua 的 draw_effects 里画，
-- 与 turn.lua / worms.lua 同一套分工——逻辑模块只维护状态

local Weapons = require("weapons")
-- 读 Worms.STEP_SUB（行走能迈的高度）：可达性判据必须与角色真正走得动的范围同源，
-- 自己另写一个数字就会判"能到"而实际走不到
local Worms = require("worms")

local Supply = {}
Supply.__index = Supply

Supply.INTERVAL = 4 -- 每 4 回合空投一次（第 4、8、12… 回合）
Supply.LIFETIME = 2 -- 落地后 2 回合无人认领就消失
Supply.FALL_SPEED = 12 -- 子格/秒：伞吊着，比自由落体慢得多
Supply.DROP_H = 44 -- 从地表上方这么高开始落（≈3.7 秒落地）
Supply.PICK_RANGE = 4 -- 走到这么近就算捡到（子格）
Supply.AI_RANGE = 46 -- AI 最多为它绕行这么远（子格 = 23 格）

function Supply.new()
  local self = setmetatable({}, Supply)
  self.crate = nil
  return self
end

-- 随机一件**限量**武器：ammo < 0 是无限的兜底弹，空投它没意义
local function roll_weapon()
  local pool = {}
  for _, spec in ipairs(Weapons.LIST) do
    if (spec.ammo or 0) >= 0 then
      pool[#pool + 1] = spec
    end
  end
  if #pool == 0 then
    return nil
  end
  return pool[phos.sys.random(1, #pool)]
end

-- 落点必须是**实地**：箱子掉进海里就白瞎了。抽十几次找不到就这次不投
local function roll_spot(terrain)
  for _ = 1, 12 do
    local x = phos.sys.random(12, terrain.W - 12)
    local top = terrain.top[x]
    if top and top < terrain.WATER_Y - 4 then
      return x, top
    end
  end
  return nil
end

-- 换回合：该空投就空投，该过期就过期
function Supply:advance_round(round, terrain)
  local c = self.crate
  if c then
    if c.landed and round - c.landed_round >= Supply.LIFETIME then
      self.crate = nil
      c = nil
    end
  end
  if c or round % Supply.INTERVAL ~= 0 then
    return
  end
  local x, top = roll_spot(terrain)
  local spec = roll_weapon()
  if not x or not spec then
    return
  end
  self.crate = {
    x = x,
    y = top - Supply.DROP_H,
    vy = 0,
    spec = spec,
    count = spec.supply or 1,
    landed = false,
    landed_round = 0,
  }
end

-- 推进一帧：下落 → 落地 → 谁碰到就归谁。on_pickup(worm, spec, count) 由上层给
function Supply:update(dt, round, terrain, worms, on_pickup)
  local c = self.crate
  if not c then
    return
  end
  if not c.landed then
    -- 伞有阻力：加速度不大，且速度封顶，看着就是"飘下来"而不是"砸下来"
    c.vy = math.min(Supply.FALL_SPEED, c.vy + 26 * dt)
    c.y = c.y + c.vy * dt
    if terrain:solid(math.floor(c.x), math.floor(c.y + 3)) then
      c.y, c.vy = math.floor(c.y), 0
      c.landed, c.landed_round = true, round
    end
    return
  end
  for _, w in ipairs(worms.list) do
    if w.alive and math.abs(w.x - c.x) <= Supply.PICK_RANGE and math.abs(w.y - c.y) <= Supply.PICK_RANGE + 4 then
      local n = (w.ammo and w.ammo[c.spec.id]) or 0
      -- 只补限量弹：-1 是"无限"，加不上去也不该加
      if n >= 0 and w.ammo then
        w.ammo[c.spec.id] = n + c.count
      end
      if on_pickup then
        on_pickup(w, c.spec, c.count)
      end
      self.crate = nil
      return
    end
  end
end

-- AI 专用的"够不够得着"：箱子已经落地、离得不远，且沿途没有翻不过去的大台阶。
-- 拿沿途地表高度做一次便宜的近似，比在 AI 里塞一套寻路划算得多；
-- 判错也只会让它白走几步（走位有回合时限兜底）
function Supply:reachable(w, terrain)
  local c = self.crate
  if not c or not c.landed then
    return false
  end
  local dx = c.x - w.x
  if math.abs(dx) > Supply.AI_RANGE then
    return false
  end
  -- 沿途逐段比**真正的地表**（terrain:foot_row），不读 top：top 是生成时的高度场，
  -- 打出来的洞不会反映在里面，按它判"可达"会让 AI 白跑一趟
  local step = (dx >= 0) and 8 or -8
  local prev
  for x = w.x, c.x, step do
    local col = math.floor(x)
    local gy = terrain:foot_row(col, col, 1)
    if not gy then
      return false
    end
    -- 落差上限与角色行走的台阶高度**同一个数**：比它大的坡 AI 根本走不上去
    if prev and math.abs(gy - prev) > Worms.STEP_SUB then
      return false
    end
    prev = gy
  end
  return true
end

return Supply

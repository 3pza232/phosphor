-- rng.lua —— 确定性随机的唯一入口（DESIGN §15）。
--
-- 为什么必须封成一个模块：主机用 `--seed N` 决定整局的随机序列，而 `math.random`
-- 不受主机种子控制。所以**任何**随机（地图、掉落、战斗判定）都得走 `phos.sys.random`，
-- 测试才能"同种子跑两遍逐位一致"。这里只做封装，不碰任何玩法状态。

local R = {}

function R.int(a, b) return phos.sys.random(a, b) end

-- [0,1)：整数化后再比，避免浮点实现差异影响判定（DESIGN §15）
function R.float() return phos.sys.random(0, 9999) / 10000 end

function R.chance(p) return phos.sys.random(0, 9999) < p * 10000 end

function R.pick(t) return t[phos.sys.random(1, #t)] end

function R.range(a, b) return a + (b - a) * (phos.sys.random(0, 9999) / 10000) end

-- Fisher–Yates：就地打乱（用于"随机方向"这类需要遍历全部候选的场合）
function R.shuffle(t)
  for i = #t, 2, -1 do
    local j = phos.sys.random(1, i)
    t[i], t[j] = t[j], t[i]
  end
  return t
end

-- 加权挑选：t 是 { {w=权重, ...}, ... }；全零权重返回 nil。
-- 先用一次随机数取总权重内的整数，再线性累加命中——比"逐个掷骰"更省随机数、
-- 也与权重无关地稳定（改权重不必重排随机序列）。
function R.weighted(t)
  local total = 0
  for _, it in ipairs(t) do total = total + (it.w or 0) end
  if total <= 0 then return nil end
  local roll = phos.sys.random(1, total)
  local acc = 0
  for _, it in ipairs(t) do
    acc = acc + (it.w or 0)
    if roll <= acc then return it end
  end
  return t[#t]
end

return R

-- scores.lua —— 最高分存档（值必须是字符串）

local Scores = {}

Scores.best_value = 0

function Scores.load()
  Scores.best_value = 0
  if not phos.save.available() then return end
  local raw = phos.save.read("best")
  if raw then Scores.best_value = tonumber(raw) or 0 end
end

function Scores.best() return Scores.best_value end

-- 返回 true 表示刷新了纪录
function Scores.submit(score)
  if score <= Scores.best_value then return false end
  Scores.best_value = score
  if phos.save.available() then phos.save.write("best", tostring(score)) end
  return true
end

return Scores

-- scores.lua —— 历史分数记录（存档驱动，TOP 5）

local MAX = 5

local Scores = {
  list = {},
}

function Scores.load()
  Scores.list = {}
  local raw = phos.save.read("scores")
  if not raw then return end
  for n in string.gmatch(raw, "(%d+)") do
    table.insert(Scores.list, tonumber(n))
  end
end

function Scores.add(score)
  if score <= 0 then return end          -- 0 分不入榜
  if not phos.save.available() then return end

  table.insert(Scores.list, score)
  table.sort(Scores.list, function(a, b) return a > b end)
  while #Scores.list > MAX do table.remove(Scores.list) end

  local parts = {}
  for _, v in ipairs(Scores.list) do table.insert(parts, tostring(v)) end
  phos.save.write("scores", table.concat(parts, ","))
end

function Scores.best()
  return Scores.list[1] or 0
end

return Scores

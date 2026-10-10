-- 图案库：从包内 assets/patterns.txt 读取（演示 phos.assets.rows）
--
-- 文件格式：
--   [名字]        图案开始
--   .##.          一行格子：'#' 存活，'.' 或空格为空
--   ; 注释        ';' 开头的行被忽略

local Patterns = {}

Patterns.list = {}
Patterns.error = nil

local function parse(rows)
  local current = nil
  for _, line in ipairs(rows or {}) do
    local trimmed = string.gsub(line, "\r", "")
    local name = string.match(trimmed, "^%s*%[([^%]]+)%]")
    if name then
      current = { name = string.upper(name), rows = {} }
      table.insert(Patterns.list, current)
    elseif current then
      -- 整行都是 '.' 的格子是合法行（图案里的空白带），必须保留，否则图案被截断
      local body = string.match(trimmed, "^%s*([%.#Oo]+)%s*$")
      if body then
        table.insert(current.rows, (string.gsub(body, "[Oo]", "#")))
      elseif string.match(trimmed, "^%s*$") or string.sub(trimmed, 1, 1) == ";" then
        -- 空行 / 注释：图案尚未结束时忽略
      else
        current = nil  -- 遇到既不是格子也不是注释的行，图案结束
      end
    end
  end
end

function Patterns.load()
  Patterns.list = {}
  local rows = phos.assets.rows("assets/patterns.txt")
  if not rows then
    Patterns.error = "assets/patterns.txt missing"
    -- 兜底：至少给一个滑翔机，保证卡带永远可用
    Patterns.list = { { name = "滑翔机", rows = { ".#.", "..#", "###" } } }
    return Patterns.list
  end
  parse(rows)
  if #Patterns.list == 0 then
    Patterns.error = "no pattern parsed"
    Patterns.list = { { name = "滑翔机", rows = { ".#.", "..#", "###" } } }
  end
  return Patterns.list
end

-- 图案名是**数据**（来自 assets/patterns.txt 的 [名字]）：这里给出各语言的名字，
-- 取值与"缺 en 回落中文"交给引擎（phos.lang.pick）；没收录的名字原样显示
local NAMES = {
  ["滑翔机"] = { zh = "滑翔机", en = "GLIDER" },
  ["闪烁器"] = { zh = "闪烁器", en = "BLINKER" },
  ["蟾蜍"] = { zh = "蟾蜍", en = "TOAD" },
  ["信标"] = { zh = "信标", en = "BEACON" },
  ["脉冲星"] = { zh = "脉冲星", en = "PULSAR" },
  ["轻型飞船"] = { zh = "轻型飞船", en = "LWSS" },
  ["R 五连"] = { zh = "R 五连", en = "R-PENTOMINO" },
  ["橡果"] = { zh = "橡果", en = "ACORN" },
  ["滑翔机枪"] = { zh = "滑翔机枪", en = "GOSPER GUN" },
}

function Patterns.label(pattern)
  local name = (pattern and pattern.name) or "-"
  local rec = NAMES[name]
  return rec and phos.lang.pick(rec) or name
end

function Patterns.get(index)
  if #Patterns.list == 0 then Patterns.load() end
  local i = ((index - 1) % #Patterns.list) + 1
  return Patterns.list[i], i
end

function Patterns.count() return #Patterns.list end

return Patterns

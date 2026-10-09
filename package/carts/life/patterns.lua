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

-- 图案名是**数据**（来自 assets/patterns.txt 的 [名字]）：这里给出英文对照，
-- 界面语言为 en 时显示英文，没收录的名字原样显示
local NAME_EN = {
  ["滑翔机"] = "GLIDER", ["闪烁器"] = "BLINKER", ["蟾蜍"] = "TOAD", ["信标"] = "BEACON",
  ["脉冲星"] = "PULSAR", ["轻型飞船"] = "LWSS", ["R 五连"] = "R-PENTOMINO",
  ["橡果"] = "ACORN", ["滑翔机枪"] = "GOSPER GUN",
}

function Patterns.label(pattern)
  local name = (pattern and pattern.name) or "-"
  if phos.sys.language() == "en" then return NAME_EN[name] or name end
  return name
end

function Patterns.get(index)
  if #Patterns.list == 0 then Patterns.load() end
  local i = ((index - 1) % #Patterns.list) + 1
  return Patterns.list[i], i
end

function Patterns.count() return #Patterns.list end

return Patterns

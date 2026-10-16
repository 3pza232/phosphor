-- BRASSWORK：黄铜工坊仪表机台
-- 黄铜/青铜机身 + 齿轮铰链与铆钉 + 铜绿(verdigris)斑驳 + 一圈刻度/游标 + 黄铜铭牌与小压力/温度表
-- 上沿：铆钉-链节铰链 → 铭牌 → 齿轮齿（朝下，与屏内机芯咬合）
-- 下沿：齿轮齿（朝上，与上沿相对）→ 铜牌 → 三联小表（压力 / 温度 / 油壶）
-- 侧壁：镜像铆钉列（左 "|o" / 右 "o|"，逐行轮换，四边与内容区严格对齐）
local W = 84

-- 把文本右补空格，两侧各留 2 格机身，凑成整行 W 宽（内容区 80 格居中）
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

-- 在 80 格内按列号摆放多段文字（列号从内容区左缘算起）
local function cols(...)
  local out = {}
  local at = 0
  local spec = { ... }
  for i = 1, #spec, 2 do
    local col, s = spec[i], spec[i + 1]
    if col > at then out[#out + 1] = string.rep(" ", col - at) end
    out[#out + 1] = s
    at = col + phos.text.width(s)
  end
  if at < 80 then out[#out + 1] = string.rep(" ", 80 - at) end
  return table.concat(out)
end

return {
  screen = { x = 2, y = 3 },
  palette = "verdigris",
  left  = "|o",        -- 左侧壁：竖梁与铆钉逐行轮换
  right = "o|",        -- 右侧壁：与左侧镜像
  top = {
    string.rep("o=====", 14),                                   -- 铆钉-链节铰链（84 格整）
    plate(cols(0,  "BRASSWORK MOVEMENT CO.",
              26,  "ESCAPEMENT CALIB.",
              50,  "CAT. 1889",
              70,  "[ RUN ]")),
    string.rep("\\/", 42),                                      -- 齿轮齿朝下（与屏内机芯咬合）
  },
  bottom = {
    string.rep("/\\", 42),                                      -- 齿轮齿朝上（与上沿相对）
    plate(cols(0,  "BRASS PLATE  No.7",
              26,  "VERDIGRIS PATINA",
              50,  "DO NOT OIL",
              64,  "KEEP WOUND")),
    -- 三联小表：压力 / 温度 / 油壶，列号 0 / 27 / 54 均匀分栏
    plate(cols(0,  "PRESSURE [|||||||.....] 42",
              27,  "TEMP [=====.......] 72",
              54,  "OIL (o) (o) (o)")),
  },
  colors = {
    frame  = { 152, 112, 48  },   -- 黄铜机身
    accent = { 238, 202, 126 },   -- 抛光黄铜高光
    ui_fg  = { 230, 222, 200 },   -- 暖白
    ui_bg  = { 16,  13,  10  },   -- 深褐
    ui_dim = { 124, 106, 74  },   -- 暗黄铜
    panel  = { 22,  30,  26  },   -- 铜绿蚀刻凹槽（偏青，与暖黄铜机身区分）
  },
  lamps = {
    { x = 0,  y = 6,  color = { 92,  206, 168 }, period = 3.6 },   -- 铜绿呼吸灯
    { x = 83, y = 6,  color = { 240, 198, 98  }, period = 2.3 },   -- 琥珀呼吸灯
  },
}

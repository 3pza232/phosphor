-- INKSTONE：砚台 / 宣纸机台
-- 米白宣纸机身：外一圈回纹（云雷纹）装裱，内一圈云纹贴着纸缘；
-- 上下铭牌克制（左款右标），左下角一方砚（墨池）、右下角一支笔架的剪影。
-- 四边与内容区（80x45）严格对齐，两侧壁为镜像双线（外实内虚）。留白、清雅、克制。
-- 只用 ASCII。
local W = 84

-- 把文本右补空格，两侧各留 2 格机身，凑成整行 W 宽（内容区 80 格居中）
local function plate(text)
  local inner = 80
  if phos.text.width(text) > inner then text = phos.text.truncate(text, inner) end
  return "  " .. text .. string.rep(" ", inner - phos.text.width(text)) .. "  "
end

-- 在 80 格内按列号摆放多段文字（列号从内容区左缘算起）——留白由列号决定
local function cols(...)
  local out, at, spec = {}, 0, { ... }
  for i = 1, #spec, 2 do
    local col, s = spec[i], spec[i + 1]
    if col > at then out[#out + 1] = string.rep(" ", col - at) end
    out[#out + 1] = s
    at = col + phos.text.width(s)
  end
  if at < 80 then out[#out + 1] = string.rep(" ", 80 - at) end
  return table.concat(out)
end

-- 回纹（云雷纹）：._|_ 单元循环，墨色细线，整 84 格
local function meander()
  return string.rep("._|_", 21)
end

-- 云纹：一条细波，两端各一卷云（卷云落在内容区左右缘，与纸对齐）
local function cloud()
  return "  o" .. string.rep("~", 78) .. "o  "
end

return {
  screen = { x = 2, y = 3 },
  palette = "inkwash",
  left  = "||",        -- 侧壁：实线装裱边，与上下的回纹/云纹四边相接
  right = "||",
  top = {
    meander(),                                              -- 外框：回纹（上）
    plate(cols(0,  "INKSTONE  IX-1",
              60, "RICE-PAPER DISPLAY")),                   -- 铭牌：左款右标，中留白
    cloud(),                                                -- 内框：云纹（贴纸缘上）
  },
  bottom = {
    cloud(),                                                -- 内框：云纹（贴纸缘下）
    plate(cols(0,  "\\___/  INK SLAB",
              56, "BRUSH RACK  =|/\\|=")),                  -- 砚台 / 笔架剪影
    meander(),                                              -- 外框：回纹（下）
  },
  colors = {
    frame  = { 156, 142, 116 },   -- 装裱褐（外框）
    accent = { 184, 54,  40  },   -- 朱砂（高亮 / 印章红）
    ui_fg  = { 44,  40,  37  },   -- 墨（主文字，压得住）
    ui_bg  = { 240, 233, 214 },   -- 宣纸（底）
    ui_dim = { 128, 118, 98  },   -- 淡墨（次要文字，仍分明）
    panel  = { 231, 223, 203 },   -- 面板（略深于纸，凹槽层次）
  },
  lamps = {
    { x = 0,  y = 6, color = { 196, 46, 36 }, period = 3.4 },   -- 朱砂呼吸
    { x = 83, y = 6, color = { 66,  96,  92 }, period = 5.2 },   -- 松烟墨青呼吸
  },
}

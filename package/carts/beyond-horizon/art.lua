-- art.lua —— 《视界线外》美术资源总入口。
--
-- 用法（程序组）：
--   local Art = require("art")
--   Art.draw(Art.scenes.awake, 0, 0)                 -- 左上角贴到内容区
--   Art.draw(Art.blocks["scene.bridge"], x, y)       -- 按 id 取块
--   Art.draw_in(region, Art.ui.textbox, 0, 0)        -- 贴进带裁剪的区域
--   local x, y = Art.at(Art.title.wordmark)          -- 按块的建议锚点居中
--
-- 块结构：{ id, rows, colors, w, h, anchor, note }
--   rows   = 字符画行（纯 ASCII；'.' 是透明字符，图样里不用它）
--   colors = 字符 → 语义键（"ice"/"alert"/…，见 util.lua 的 palette）
-- 颜色在**每次绘制时**才解析成 phos.color，主题热切换不会拿着旧色板。
local U = require("art.util")

local Art = {
  schema = 1,             -- 接口版本：程序侧按 id/rows/colors 消费
  util = U,
  palette = U.palette,
  colors = U.colors,
  draw = U.draw,
  draw_in = U.draw_in,
  at = U.anchor_xy,
  place = U.place,
  size = U.size,
}

Art.title = require("art.title")
Art.rooms = require("art.rooms")
Art.scenes = require("art.scenes")
Art.endings = require("art.endings")
Art.cards = require("art.cards")
Art.ui = require("art.ui")
Art.station = require("art.station")   -- 可选：地图/星图底图（非必需）

-- 扁平索引：id → 块。程序只记 id 时用 Art.blocks["scene.bridge"]，不必记层级。
Art.blocks = {}
for _, group in ipairs({ Art.title.blocks, Art.rooms.blocks, Art.scenes.blocks,
                         Art.endings.blocks, Art.cards.blocks, Art.ui.blocks,
                         Art.station.blocks }) do
  for id, block in pairs(group) do Art.blocks[id] = block end
end

function Art.get(id) return Art.blocks[id] end

-- 块的色键表（字符 → 12 色板名）：文档/核对用；绘制请用 Art.colors（会转成 phos.color 值）
function Art.legend(block)
  local out = {}
  for ch, key in pairs(block.colors or {}) do
    out[ch] = U.palette[key] or key
  end
  return out
end

-- 按 id 绘制；找不到时返回 false（不静默画错东西，程序可据此提示/回退）
function Art.draw_id(id, x, y, opts)
  local block = Art.blocks[id]
  if not block then return false end
  U.draw(x, y, block, opts)
  return true
end

return Art
-- panel.lua —— 侧栏：分数 / 最高 / 速度条 / 昼夜 / 图例与操作
--
-- 面板坐标是局部的（左上角 0,0）；键位提示放最底部，与其它卡带一致。
-- 速度条用块字符手绘（组件层的进度条画在内容区，侧栏里得自己铺）。

local Panel = {}

local Text = {
  zh = {
    score = "得分", best = "最高", speed = "速度", phase = "时段",
    day = "白天", night = "夜里", mark = "下一里程碑",
    legend = "图例", cactus = "█  仙人掌", bird = "██ 翼龙",
    keys = "操作", jump = "[↑/A] 跳", jump_hold = "  按住 = 更高", duck = "[↓] 蹲/速降",
  },
  en = {
    score = "SCORE", best = "BEST", speed = "SPEED", phase = "PHASE",
    day = "day", night = "night", mark = "NEXT MARK",
    legend = "LEGEND", cactus = "█  cactus", bird = "██ bird",
    keys = "KEYS", jump = "[↑/A] JUMP", jump_hold = "  hold = higher", duck = "[↓] DUCK",
  },
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

function Panel.draw(game, cart_t)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end

  local t = L()
  local s = game:status()
  P.clear()

  P.print(1, 1, phos.cart.info().name, C.yellow)
  P.print(1, 2, string.rep("·", pw - 2), C.dark_gray)

  P.print(1, 4, t.score, C.gray)
  P.print(1, 5, tostring(s.score), C.white)
  P.print(1, 7, t.best, C.gray)
  P.print(1, 8, tostring(s.best), C.orange)

  -- 速度：数值 + 一条块字符速度条（10~24 格/秒的区间）
  P.print(1, 10, t.speed, C.gray)
  P.print(1, 11, string.format("%.1f", s.speed) .. " c/s", C.cyan)
  local track_w = pw - 4
  local filled = math.max(1, math.min(track_w, math.floor((s.speed - 10) / 14 * track_w)))
  P.fill(1, 12, track_w, 1, "▁", C.dark_gray)
  P.fill(1, 12, filled, 1, "▄", C.cyan)

  P.print(1, 14, t.phase, C.gray)
  P.print(1, 15, s.night and t.night or t.day, s.night and C.blue or C.yellow)
  P.print(1, 17, t.mark, C.gray)
  P.print(1, 18, tostring((math.floor(s.score / 100) + 1) * 100), C.purple)

  -- 图例与操作（最下面留给键位）
  P.print(1, ph - 7, t.legend, C.gray)
  P.print(1, ph - 6, t.cactus, C.green)
  P.print(1, ph - 5, t.bird, C.gray)

  -- 面板是定宽的：这里按列宽自行裁剪并补省略号。机器只会在右边硬切，
  -- 把"[↑/A] 跳：按住更高"切成"跳跃更"那种半句话，玩家只能猜
  local function fit(text, limit)
    if phos.text.width(text) <= limit then return text end
    local cut, i = 0, 1
    while i <= #text do
      local byte = text:byte(i)
      local step = (byte >= 0xF0 and 4) or (byte >= 0xE0 and 3) or (byte >= 0xC0 and 2) or 1
      if phos.text.width(text:sub(1, i + step - 1)) > limit - 1 then break end
      cut, i = i + step - 1, i + step
    end
    return text:sub(1, cut) .. "…"
  end

  P.print(1, ph - 4, t.keys, C.gray)
  local key_lines = { { t.jump, C.white }, { t.jump_hold, C.dark_gray }, { t.duck, C.white } }
  for i, line in ipairs(key_lines) do
    P.print(1, ph - 4 + i, fit(line[1], pw - 2), line[2])
  end
end

return Panel

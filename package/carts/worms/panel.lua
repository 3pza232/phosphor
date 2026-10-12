-- panel.lua —— 右侧栏：两队血量 / 武器两列网格 / 键位与地图提示
--
-- 只读状态。血量用紧凑条 + 数字表示（每格 = 上限的 1/8）：擦伤几点在条子上一格都不动，
-- 会让人以为"打了不扣血"，数字才是唯一不含糊的读数。阵亡的虫保留一行写"阵亡"，
-- 两队各 N 只始终占同样的行数，面板不会跳来跳去。
--
-- 这里**不画小地图**：地图整幅交给 M 键唤出的浮窗（见 main.lua 的 draw_map_overlay），
-- 侧栏只留一行提示。8v8 时血量行会排到十几行，侧栏本来就该把地方让给血量与武器。
--
-- 武器排**两列**（最多 2x10 = 20 件）：一列排不下时就得整块重排，两列留有余量。
-- X 下一件 / Z 上一件，顺序就是武器表的顺序（普通炮弹第一）。
--
-- 传参用**上下文表**而不是一长串位置参数：这里的字段会随玩法增长（难度、队友AI……），
-- 位置参数加到第七八个时，调用点与实现就没法对着读了。

local Panel = {}

local Text = {
  -- 只说队伍（红/蓝），"谁在操作"由记号（* = 人, A = 电脑）负责
  zh = { title = "WORMS", team = "队伍", dead = "阵亡", left = "已退出",
        arms = "武器 (X 下 / Z 上)",
        side = { "红队", "蓝队" }, cpu = "AI",
        map = "M 地图总览", help = "K 键位提示" },
  en = { title = "WORMS", team = "TEAM", dead = "KIA", left = "LEFT",
        arms = "ARMS (X / Z)",
        side = { "RED", "BLUE" }, cpu = "AI",
        map = "M MAP", help = "K HELP" },
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

local HP_CELLS = 8

-- 血量档位配色：**色相**说是哪一队，三档说还剩多少 —— 红队走红系（红→橙→品红），
-- 蓝队走蓝系（蓝→青→白），两队一眼分得开；濒死一档用最扎眼的颜色来报警。
--
-- 表里存的是**颜色名**而不是颜色值：本模块是在卡带加载时就被 require 的，
-- 那时 phos 还没装配完，顶层碰 phos.color 会当场崩（见 main.lua 的调色板注释）
local HP_RAMPS = {
  [1] = { "red", "orange", "magenta" },
  [2] = { "blue", "cyan", "white" },
}
-- 这一档叫什么颜色。取色与自测都走它：观察口读得到"哪只虫在哪一档"，
-- 就不用靠肉眼比色去猜（见 main.lua 的 debug_state）
function Panel.hp_tone_name(team, frac)
  local ramp = HP_RAMPS[team] or HP_RAMPS[2]
  if frac > 0.6 then return ramp[1] end
  if frac > 0.25 then return ramp[2] end
  return ramp[3]
end

local function hp_tone(C, team, frac)
  return C[Panel.hp_tone_name(team, frac)]
end

-- 每只虫在面板上的角色记号：一眼看出"哪只归人操作、哪只归电脑"。
-- 归谁操作由 main 的 worm_is_human 一处判定（ctx.human_of），侧栏只负责画
local function role_mark(w, ctx)
  return (ctx.human_of and ctx.human_of(w)) and "*" or "A"
end

function Panel.draw(ctx)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end
  local t = L()
  local worms, turn = ctx.worms, ctx.turn
  P.clear()

  P.print(1, 1, t.title, C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  -- 两队血量（队伍名：红/蓝按 red_side 映射；整队 AI 时标一下）
  local y = 4
  local rs = ctx.red_side or 1
  for team = 1, 2 do
    local is_red = (team == rs)
    local col = is_red and C.red or C.blue
    -- "谁在操作"这件事由每只虫身上的记号说（见 role_mark），这里只报队伍
    local who = t.side[is_red and 1 or 2]
    if ctx.teams and not ctx.teams[team].human then who = who .. " " .. t.cpu end
    local total = 0
    for _, m in ipairs(worms.list) do if m.team == team then total = total + 1 end end
    P.print(1, y, phos.text.fit(string.format("%s %d  %d/%d %s", t.team, team,
                                              worms:alive_count(team), total, who), pw - 2), col)
    y = y + 1
    for _, w in ipairs(worms.list) do
      if w.team == team then
        local mark = (w == ctx.active) and ">" or " "
        if w.alive then
          -- 一律按**比例**算：血量上限由开局菜单决定（10~800），
          -- 拿绝对值算的话，800 血的一局里条子与配色全都会失真
          local frac = w.hp / (ctx.hp_max or 100)
          local n = math.max(0, math.ceil(frac * HP_CELLS))
          local role = role_mark(w, ctx)
          local tone = hp_tone(C, is_red and 1 or 2, frac)
          -- 数字后面跟名字：知道"这条血是谁的"（联机是玩家昵称，单机是 P1/P2/AI）
          local bar = string.format("[%s%s] %3d %s", string.rep("=", n),
                                    string.rep("-", HP_CELLS - n), math.floor(w.hp + 0.5),
                                    w.name or "")
          -- 记号与血量**分开上色**：记号说"谁在操作"（归电脑管的暗一档），
          -- 条子与数字一律用血量色 —— 整行涂灰会把 AI 队友的血量一起盖掉
          local mark_tone = (role == "A") and C.gray or tone
          P.print(1, y, mark .. role, mark_tone)
          P.print(3, y, phos.text.fit(bar, pw - 4), tone)
        else
          -- 阵亡还是"退出"分开写：联机里掉线/主动退出的虫标"已退出"，一眼看出是走人不是被打死
          local who = w.name and (w.name .. " ") or ""
          local label = w.left and (who .. t.left) or t.dead
          P.print(1, y, phos.text.fit(mark .. " " .. label, pw - 2), C.dark_gray)
        end
        y = y + 1
      end
    end
    y = y + 1
  end

  -- 武器网格：两列，最多 2x10。打光了的暗一档，让玩家一眼看出
  -- "为什么按了发射没反应"；当前选中那件标 '>'。
  -- 显示的是**当前开火单位**选的武器（队友/敌人开火时也跟着变，见 main.lua 的 fire）
  P.print(1, ph - 16, t.arms, C.gray)
  local rows_max = 10
  local colw = math.floor((pw - 2) / 2)
  for i, spec in ipairs(ctx.weapons or {}) do
    local slot = i - 1
    local col, row = math.floor(slot / rows_max), slot % rows_max
    if row < rows_max then
      local name = phos.lang.pick(spec.short or spec.name)
      local n = (ctx.active and ctx.active.ammo and ctx.active.ammo[spec.id]) or 0
      local cnt = (n < 0) and "∞" or tostring(n)
      local sel = (spec == ctx.current)
      -- 余弹**永远留在最后**：名字按剩余宽度裁，宁可裁名字也不吃掉"还剩几发"。
      -- 宽度一格格都要算，因为中文短名是 2 字（4 列）、英文短名可能 5~6 列
      local tail = " " .. cnt
      local text = string.format("%s%s%s", sel and ">" or " ",
                                 phos.text.fit(name, colw - 2 - phos.text.width(tail)), tail)
      local tone = (n == 0) and C.dark_gray or ((sel and C.white) or C.gray)
      P.print(1 + col * colw, ph - 15 + row, phos.text.fit(text, colw - 1), tone)
    end
  end

  -- 两行提示：地图在上、键位在下（地图是"看一眼全局"，比键位表更常用）
  P.print(1, ph - 2, phos.text.fit(t.map, pw - 2), C.dark_gray)
  P.print(1, ph - 1, phos.text.fit(t.help, pw - 2), C.dark_gray)
end

return Panel

-- panel.lua —— 右侧栏：两队血量 / 武器两列网格 / 键位与地图提示
--
-- 只读状态。血量用紧凑条 + 数字表示（每格 = 上限的 1/8）：擦伤几点在条子上一格都不动，
-- 会让人以为"打了不扣血"，数字才是唯一不含糊的读数。阵亡的虫保留一行写"阵亡"，
-- 两队各 N 只始终占同样的行数，面板不会跳来跳去。
--
-- 这里**不画小地图**：地图整幅交给 M 键唤出的浮窗（见 main.lua 的 draw_map_overlay），
-- 侧栏只留一行提示。8v8 时血量行会排到十几行，侧栏本来就该把地方让给血量与武器。
--
-- 武器改成**两列**：将来道具会变多，一列排不下就得整块重排；两列最多放
-- 2x10 = 20 件。X 下一件 / Z 上一件，顺序就是这张表的顺序（普通炮弹第一）。
--
-- 传参用**上下文表**而不是一长串位置参数：这里的字段会随玩法增长（难度、队友AI……），
-- 位置参数加到第七八个时，调用点与实现就没法对着读了。

local Panel = {}

local Text = {
  zh = { title = "WORMS", team = "队伍", dead = "阵亡", arms = "武器 (X 下 / Z 上)",
         you = "你", cpu = "电脑", p2 = "玩家2", side = "己方",
         map = "M 地图总览", help = "K 键位提示" },
  en = { title = "WORMS", team = "TEAM", dead = "KIA", arms = "ARMS (X / Z)",
         you = "YOU", cpu = "CPU", p2 = "P2", side = "OURS",
         map = "M MAP", help = "K HELP" },
}
local function L() return Text[phos.sys.language()] or Text.zh end

local HP_CELLS = 8

-- 每只虫在面板上的角色记号：一眼看出"哪只是我在操作、哪只归电脑"
--   * 玩家亲自操作   A 队友交给 AI   E 敌方（PVE 时是电脑）
local function role_mark(w, ctx, is_ally_ai)
  if ctx.pvp then return "*" end
  if w.team == 2 then return "E" end
  if not is_ally_ai then return "*" end
  return (w == ctx.leader) and "*" or "A"
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

  -- 两队血量（标出这一队是谁在操作：PVP 时右边也是玩家）
  local y = 4
  local is_ally_ai = ctx.ally_ai and not ctx.pvp
  for team = 1, 2 do
    local col = (team == 1) and C.yellow or C.red
    -- "谁在操作"这件事由每只虫身上的记号说（见 role_mark），这里只报阵营
    local who = ctx.pvp and ((team == 1) and t.you or t.p2)
                or ((team == 1) and t.side or t.cpu)
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
          local line = string.format("%s%s[%s%s] %3d", mark, role_mark(w, ctx, is_ally_ai),
                                     string.rep("=", n), string.rep("-", HP_CELLS - n),
                                     math.floor(w.hp + 0.5))
          local tone = (frac > 0.6 and col) or (frac > 0.25 and C.orange) or C.white
          -- 归电脑指挥的那几只暗一档：记号是"谁在操作"，亮度是"我该不该管"
          if is_ally_ai and mark == " " and role_mark(w, ctx, is_ally_ai) == "A" then
            tone = C.gray
          end
          P.print(1, y, phos.text.fit(line, pw - 2), tone)
        else
          P.print(1, y, phos.text.fit(mark .. " " .. t.dead, pw - 2), C.dark_gray)
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
      local name = spec.short and (spec.short[phos.sys.language()] or spec.short.en)
                   or (spec.name[phos.sys.language()] or spec.name.en)
      local n = (ctx.active and ctx.active.ammo and ctx.active.ammo[spec.id]) or 0
      local cnt = (n < 0) and "∞" or tostring(n)
      local sel = (spec == ctx.current)
      local text = string.format("%s%s%s", sel and ">" or " ", name,
                                 (n == 0) and " 空" or "")
      local tone = (n == 0) and C.dark_gray or ((sel and C.white) or C.gray)
      P.print(1 + col * colw, ph - 15 + row,
              phos.text.fit(text .. (" "):rep(2) .. cnt, colw - 1), tone)
    end
  end

  -- 两行提示：地图在上、键位在下（地图是"看一眼全局"，比键位表更常用）
  P.print(1, ph - 2, phos.text.fit(t.map, pw - 2), C.dark_gray)
  P.print(1, ph - 1, phos.text.fit(t.help, pw - 2), C.dark_gray)
end

return Panel

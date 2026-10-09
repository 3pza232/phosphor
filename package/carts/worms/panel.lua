-- panel.lua —— 右侧栏：两队血量 / 小地图 / 武器两列网格 / 键位提示
--
-- 只读状态。血量用紧凑条表示（每格 = 12.5 血），阵亡的虫保留一行显示"阵亡"，
-- 这样两队各 4 只始终占同样的行数，面板不会跳来跳去。
-- 风向、回合在顶部读数行里已经有了（hud.lua），这里不重复画。
--
-- 武器改成**两列**：将来道具会变多，一列排不下就得整块重排；两列最多放
-- 2x10 = 20 件，够用很久。X 下一件 / Z 上一件，顺序就是这张表的顺序（普通炮弹第一）。

local Panel = {}

local Text = {
  zh = { title = "WORMS", team = "队伍", map = "小地图", dead = "阵亡",
         arms = "武器 (X 下 / Z 上)", you = "你", cpu = "电脑", p2 = "玩家2",
         help = "K 键位提示" },
  en = { title = "WORMS", team = "TEAM", map = "MAP", dead = "KIA",
         arms = "ARMS (X / Z)", you = "YOU", cpu = "CPU", p2 = "P2",
         help = "K KEY HELP" },
}
local function L() return Text[phos.sys.language()] or Text.zh end

local HP_CELLS = 8

function Panel.draw(terrain, camera, worms, turn, weapons, current, pvp, active, human)
  local P, C = phos.panel, phos.color
  local pw, ph = P.size()
  if pw == 0 then return end
  local t = L()
  P.clear()

  P.print(1, 1, t.title, C.yellow)
  P.print(1, 2, string.rep("-", pw - 2), C.dark_gray)

  -- 两队血量（标出这一队是谁在操作：PVP 时右边也是玩家）
  local y = 4
  for team = 1, 2 do
    local col = (team == 1) and C.yellow or C.red
    local who = (team == 1) and t.you or (pvp and t.p2 or t.cpu)
    local total = 0
    for _, m in ipairs(worms.list) do if m.team == team then total = total + 1 end end
    P.print(1, y, string.format("%s %d  %d/%d %s", t.team, team,
                                worms:alive_count(team), total, who), col)
    y = y + 1
    for _, w in ipairs(worms.list) do
      if w.team == team then
        local mark = (w == active) and ">" or " "
        if w.alive then
          -- 条 + **数字**：一格 12.5 血，擦伤几点在条子上一格都不动，
          -- 玩家会以为"打了不扣血"——数字才是唯一不含糊的读数
          local n = math.max(0, math.ceil(w.hp / 100 * HP_CELLS))
          P.print(1, y, phos.text.fit(mark .. "[" .. string.rep("=", n) ..
                  string.rep("-", HP_CELLS - n) .. string.format("] %3d", math.floor(w.hp + 0.5)),
                  pw - 2),
                  (w.hp > 60 and col) or (w.hp > 25 and C.orange) or C.white)
        else
          P.print(1, y, phos.text.fit(mark .. " " .. t.dead, pw - 2), C.dark_gray)
        end
        y = y + 1
      end
    end
    y = y + 1
  end

  -- 小地图：每列只画表面，视口位置用 +
  P.print(1, y, t.map, C.gray)
  y = y + 1
  local mw, mh = pw - 4, 8
  local mx, my = 2, y
  local sx, sy = terrain.W / mw, terrain.H / mh
  local tops = {}
  for i = 0, mw - 1 do
    local wx = math.floor((i + 0.5) * sx) + 1
    tops[i] = 0
    for yy = 1, terrain.WATER_Y - 1 do
      if terrain:solid(wx, yy) then tops[i] = yy break end
    end
  end
  for j = 0, mh - 1 do
    local wy = math.floor((j + 0.5) * sy) + 1
    local line = {}
    for i = 0, mw - 1 do
      local solid = (tops[i] > 0 and wy >= tops[i])
      local water = wy >= terrain.WATER_Y
      line[i + 1] = solid and "#" or (water and "~" or "·")
    end
    P.print(mx, my + j, table.concat(line), C.green)
  end
  P.print(mx + math.floor(camera.x / sx), my + math.floor(camera.y / sy), "+", C.white)

  -- 虫子也画上去：小地图是"敌人还在哪一边"的唯一线索（设计文档第 1 节）。
  -- 位置**夹紧到图内**而不是"越界就不画"：边缘的虫子消失比画歪一点更糟
  for _, w in ipairs(worms.list) do
    if w.alive then
      local i = math.max(0, math.min(mw - 1, math.floor(w.x / sx)))
      local j = math.max(0, math.min(mh - 1, math.floor(w.y / sy)))
      P.print(mx + i, my + j, "@", (w.team == 1) and C.yellow or C.red)
    end
  end

  -- 武器网格：两列，最多 2x10。打光了的暗一档，让玩家一眼看出
  -- "为什么按了发射没反应"；当前选中那件标 '>'
  P.print(1, ph - 16, t.arms, C.gray)
  local rows_max = 10
  local colw = math.floor((pw - 2) / 2)
  for i, spec in ipairs(weapons or {}) do
    local slot = i - 1
    local col, row = math.floor(slot / rows_max), slot % rows_max
    if row < rows_max then
      local name = spec.short and (spec.short[phos.sys.language()] or spec.short.en)
                   or (spec.name[phos.sys.language()] or spec.name.en)
      local n = (active and active.ammo and active.ammo[spec.id]) or 0
      local cnt = (n < 0) and "∞" or tostring(n)
      local sel = (spec == current)
      local text = string.format("%s%s%s", sel and ">" or " ", name,
                                 (n == 0) and " 空" or "")
      local tone = (n == 0) and C.dark_gray or ((sel and C.white) or C.gray)
      P.print(1 + col * colw, ph - 15 + row,
              phos.text.fit(text .. (" "):rep(2) .. cnt, colw - 1), tone)
    end
  end

  P.print(1, ph - 1, t.help, C.dark_gray)
end

return Panel

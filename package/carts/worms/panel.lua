-- panel.lua —— 右侧栏：两队血量 / 武器两列网格 / 地图与键位提示。
--
-- 血量用紧凑条 + 数字（每格 = 上限的 1/8）：擦伤几点条子不动，数字才是准确读数。
-- 阵亡的虫保留一行写"阵亡/已退出"，两队各 N 只始终占同样的行数，面板不跳。
-- 武器排两列（最多 2x10），X/Z 切换顺序即武器表顺序。
--
-- 声明式组件：布局/裁剪/对齐交给引擎，颜色一律用色板名（本模块在卡带加载时就被
-- require，那时 phos 还没装配完——顶层碰 phos.color 会当场崩，见 main.lua 注释）。
local Panel = {}

local Text = {
  zh = { title = "WORMS", team = "队伍", dead = "阵亡", left = "已退出",
        arms = "武器 (X 下 / Z 上)", side = { "红队", "蓝队" }, cpu = "AI",
        map = "M 地图总览", help = "K 键位提示" },
  en = { title = "WORMS", team = "TEAM", dead = "KIA", left = "LEFT",
        arms = "ARMS (X / Z)", side = { "RED", "BLUE" }, cpu = "AI",
        map = "M MAP", help = "K HELP" },
}
local function L() return phos.lang.dict(Text) end

local HP_CELLS = 8
local HP_RAMPS = {
  [1] = { "red", "orange", "magenta" },
  [2] = { "blue", "cyan", "white" },
}
function Panel.hp_tone_name(team, frac)
  local ramp = HP_RAMPS[team] or HP_RAMPS[2]
  if frac > 0.6 then return ramp[1] end
  if frac > 0.25 then return ramp[2] end
  return ramp[3]
end

local function role_mark(w, ctx)
  return (ctx.human_of and ctx.human_of(w)) and "*" or "A"
end

function Panel.draw(ctx)
  local pw = phos.panel.size()
  if pw == 0 then return end
  local t = L()
  local worms = ctx.worms

  local rows = {
    { kind = "text", text = t.title, accent = true },
    { kind = "divider", fg = "dark_gray" },
  }
  local rs = ctx.red_side or 1
  for team = 1, 2 do
    local is_red = (team == rs)
    local color = is_red and "red" or "blue"
    local who = t.side[is_red and 1 or 2]
    if ctx.teams and not ctx.teams[team].human then who = who .. " " .. t.cpu end
    local total = 0
    for _, m in ipairs(worms.list) do if m.team == team then total = total + 1 end end
    rows[#rows + 1] = {
      kind = "text",
      text = string.format("%s %d  %d/%d %s", t.team, team, worms:alive_count(team), total, who),
      fg = color,
    }
    for _, w in ipairs(worms.list) do
      if w.team == team then
        local mark = (w == ctx.active) and ">" or " "
        if w.alive then
          local frac = w.hp / (ctx.hp_max or 100)
          local n = math.max(0, math.ceil(frac * HP_CELLS))
          local role = role_mark(w, ctx)
          local tone = Panel.hp_tone_name(is_red and 1 or 2, frac)
          local bar = string.format("[%s%s] %3d %s", string.rep("=", n),
                                    string.rep("-", HP_CELLS - n), math.floor(w.hp + 0.5),
                                    w.name or "")
          rows[#rows + 1] = {
            kind = "row",
            gap = 1,
            children = {
              { kind = "text", text = mark .. role, fg = (role == "A") and "dark_gray" or tone },
              { kind = "text", text = bar, fg = tone },
            },
          }
        else
          local who = w.name and (w.name .. " ") or ""
          local label = w.left and (who .. t.left) or t.dead
          rows[#rows + 1] = { kind = "text", text = mark .. " " .. label, dim = true }
        end
      end
    end
    rows[#rows + 1] = { kind = "spacer", height = 1 }
  end

  rows[#rows + 1] = { kind = "spacer", grow = 2 }
  rows[#rows + 1] = { kind = "text", text = t.arms, dim = true }

  local rows_max = 10
  local colw = math.floor((pw - 2) / 2)
  local weapons = ctx.weapons or {}
  for start = 1, #weapons, 2 do
    local pair = { kind = "row", gap = 1, children = {} }
    for offset = 0, 1 do
      local spec = weapons[start + offset]
      if spec then
        local name = phos.lang.pick(spec.short or spec.name)
        local n = (ctx.active and ctx.active.ammo and ctx.active.ammo[spec.id]) or 0
        local cnt = (n < 0) and "∞" or tostring(n)
        local sel = (spec == ctx.current)
        local tail = " " .. cnt
        local text = string.format("%s%s%s", sel and ">" or " ",
                                   phos.text.fit(name, colw - 2 - phos.text.width(tail)), tail)
        pair.children[#pair.children + 1] = {
          kind = "text", text = text, width = colw,
          fg = (n == 0) and "dark_gray" or (sel and "white" or "gray"),
        }
      end
    end
    rows[#rows + 1] = pair
  end

  rows[#rows + 1] = { kind = "text", text = t.map, dim = true }
  rows[#rows + 1] = { kind = "text", text = t.help, dim = true }

  phos.ui.render{
    screen = "panel",
    surface = "panel",
    input = false,
    kind = "column",
    padding = { x = 1, y = 1 },
    gap = 0,
    children = rows,
  }
end

return Panel

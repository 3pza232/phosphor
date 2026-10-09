-- hud.lua —— 屏幕上的读数：回合 / 风 / 角度 / 力度 / 武器与弹药 / 伤害浮字
--
-- 顶部三行读数 + 受击处的伤害浮字，只读状态、不碰输入。
-- 原则是"操作需要的东西必须在眼前"：角度、力度、当前武器与余弹都要一眼可读；
-- 完整键位表按 K 弹浮板（见 main.lua）——常驻提示看久了就变成噪声，玩家反而不看。

local Hud = {}

local Text = {
  zh = { angle = "角度", power = "力度", wind = "风", turn = "回合",
         weapon = "武器", inf = "∞",
         left = "左队", right = "右队", you = "你", cpu = "电脑", p2 = "玩家2", ally = "队友AI" },
  en = { angle = "ANGLE", power = "POWER", wind = "WIND", turn = "TURN",
         weapon = "WEAPON", inf = "inf",
         left = "TEAM L", right = "TEAM R", you = "YOU", cpu = "CPU", p2 = "P2", ally = "ALLY AI" },
}
local function L() return Text[phos.sys.language()] or Text.zh end

-- 风力：箭头方向 + 强度（正 = 向右吹）
function Hud.wind_text(w)
  if w == 0 then return "— 0" end
  return string.rep(w > 0 and ">" or "<", math.min(3, math.abs(w))) .. " " .. tostring(math.abs(w))
end

function Hud.draw(S, C, ctx)
  local t = L()
  local w = ctx.worm
  -- 先擦掉这三行：地形是先前画的，读数之间有空隙，不擦的话山体会从缝里透出来。
  -- 空格本身不带字形，用它覆盖之后那格就是空的（颜色对空格没有影响）。
  -- 宽度取**本卡带的可玩区**而不是写死 58：侧栏宽度一改，写死的那份就会擦错一截
  local _, _, pw = phos.screen.playfield()
  for row = 0, 2 do
    S.print(0, row, string.rep(" ", pw or 58), C.white)
  end

  -- 第 0 行：回合数、风、轮到谁
  -- 回合数 + **回合倒计时**（默认每回合 60 秒）：没它玩家不知道还剩多少时间出手
  S.print(1, 0, string.format("%s %d   %s 秒", t.turn, ctx.round or 1, ctx.time_text or "--"), C.white)
  S.print(15, 0, t.wind .. " " .. Hud.wind_text(ctx.wind), C.cyan)
  local whose
  if ctx.pvp then
    whose = (ctx.turn_team == 1) and (t.left .. " " .. t.you) or (t.right .. " " .. t.p2)
  else
    whose = (ctx.turn_team == 1) and (t.left .. " " .. t.you) or (t.right .. " " .. t.cpu)
  end
  S.print(20, 0, whose, (ctx.turn_team == 1) and C.yellow or C.red)
  -- 队友交给 AI 时要说清楚"现在不是你在操作"，否则玩家会以为卡住了
  if ctx.ally_ai and ctx.turn_team == 1 and not ctx.human then
    S.print(29, 0, t.ally, C.dark_gray)
  end
  if ctx.phase == "flying" then
    S.print(40, 0, ctx.flight_note or "", C.orange)
  elseif ctx.shots_left == 0 then
    S.print(40, 0, "本回合已开炮", C.dark_gray)
  end

  -- 第 1 行：角度（可以是负的 = 朝下）与力度
  if w and w.alive then
    S.print(1, 1, string.format("%s %4d° %s", t.angle, math.floor(w.angle + 0.5),
                                w.facing > 0 and "→" or "←"), C.yellow)
    local power = w.power or 0
    local filled = math.floor(power * 20)
    S.print(15, 1, string.format("%s %3d%%", t.power, math.floor(power * 100 + 0.5)),
            ctx.charge and C.yellow or C.white)
    S.print(24, 1, "[" .. string.rep("#", filled) .. string.rep(".", 20 - filled) .. "]",
            ctx.charge and C.yellow or (power > 0.85 and C.red or C.green))
  end

  -- 第 2 行：武器与余弹
  if ctx.weapon then
    local name = ctx.weapon.name[phos.sys.language()] or ctx.weapon.name.en
    local n = ctx.ammo or 0
    local ammo_txt = (n < 0) and t.inf or tostring(n)
    S.print(1, 2, phos.text.fit(
      string.format("%s %s   x%s", t.weapon, name, ammo_txt), 40),
      (n == 0) and C.dark_gray or C.white)
  end

  -- 伤害浮字：受击点附近冒出来，1 秒后消失，同样垫浮层底板。
  -- f.text 是"没有数字"的说明（落海、燃烧、没弹药），此时不该硬拼出一个 -0
  for _, f in ipairs(ctx.floats or {}) do
    local text = f.text or string.format("-%d", math.floor((f.damage or 0) + 0.5))
    S.print(f.x, f.y, text, (f.text and (f.color or C.white)) or C.white, ctx.plate)
  end
end

-- 血条：画在虫子头顶，**垫浮层底板**（plate 由调用方给，nil = 透明）。
-- 为什么必须垫：血条是浮在世界上的一层，如果只写字形不动背景，
-- 格子登记的底色仍是天空，站在斜坡或水面上时就会把地形顶出一个天空色的洞。
-- 配色也刻意与地形拉开：地形偏绿，满血再用绿就糊在一起了，
-- 所以满血用**青色**，括号用白色压住两端——无论压在山体还是海里都读得出来
function Hud.hp_bar(S, C, x, y, hp, plate)
  local n = math.max(0, math.ceil(math.max(0, hp) / 100 * 6))
  local fill = (hp > 60 and C.cyan) or (hp > 25 and C.yellow) or C.red
  S.print(x - 3, y, "[", C.white, plate)
  S.print(x - 2, y, string.rep("=", n) .. string.rep("-", 6 - n), fill, plate)
  S.print(x + 4, y, "]", C.white, plate)
end

return Hud

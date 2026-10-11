-- hud.lua —— 屏幕上的读数：回合 / 风 / 角度 / 力度 / 武器与弹药 / 伤害浮字
--
-- 顶部三行读数 + 受击处的伤害浮字，只读状态、不碰输入。
-- 原则是"操作需要的东西必须在眼前"：角度、力度、当前武器与余弹都要一眼可读；
-- 完整键位表按 K 弹浮板（见 main.lua）——常驻提示看久了就变成噪声，玩家反而不看。

local Hud = {}

local Text = {
  -- own / foe 只说**阵营**（己方 / 敌方）："谁在操作"由侧栏的记号负责，
  -- 状态行只回答"轮到哪一方"
  zh = { angle = "角度", power = "力度", wind = "风", turn = "回合", sec = "秒",
        weapon = "武器", inf = "∞", fired = "本回合已开炮", terrain = "地形",
        buried = "被埋住 炸开脱身",
        own = "己方", foe = "敌方", p1 = "玩家1", p2 = "玩家2", ally = "队友AI" },
  en = { angle = "ANGLE", power = "POWER", wind = "WIND", turn = "TURN", sec = "s",
        weapon = "WEAPON", inf = "∞", fired = "FIRED THIS TURN", terrain = "TERRAIN",
        buried = "BURIED - blast out",
        own = "OURS", foe = "ENEMY", p1 = "P1", p2 = "P2", ally = "ALLY AI" },
}
-- 取当前语言那一列：查表规则在引擎里（`phos.lang.dict`，缺 en 回落中文）
local function L() return phos.lang.dict(Text) end

-- 风力：箭头方向 + 强度（正 = 向右吹）
function Hud.wind_text(w)
  if w == 0 then return "— 0" end
  return string.rep(w > 0 and ">" or "<", math.min(3, math.abs(w))) .. " " .. tostring(math.abs(w))
end

-- 一行里按顺序摆几段文字：**下一段的起点由前一段的实际宽度算**。
-- 汉字 2 列、字母 1 列，写死列号只能适配一种语言；量宽度才能中英都排对
local function seg(S, x, y, text, col)
  S:print(x, y, text, col)
  return x + phos.text.width(text)
end

local NOTE_GAP = 3 -- 发射状态文字与"x 弹药数"之间的固定间距（格）

function Hud.draw(S, C, ctx)
  local t = L()
  local w = ctx.worm
  -- 这三行**既不铺底也不擦**：信息栏是透明的一层，字直接压在世界上，笔画之外就是
  -- 天空、山体或飘过的雪 —— 这正是要的效果（天气该从读数背后穿过去）。
  -- 铺一条底色会让它看着像贴上去的色带，还会把雪挡在外面。
  -- 宽度取**本卡带的可玩区**而不是写死 58：侧栏宽度一改，写死的那份就会算错一截
  local _, _, pw = phos.screen.playfield()
  local play_w = pw or 58


  -- 第 0 行：回合数、倒计时、风、轮到谁。段与段之间固定留 2 格
  local cx = seg(S, 1, 0, string.format("%s %d", t.turn, ctx.round or 1), C.white)
  cx = seg(S, cx + 2, 0, tostring(ctx.time_text or "--") .. t.sec, C.white)
  cx = seg(S, cx + 2, 0, t.wind .. " " .. Hud.wind_text(ctx.wind), C.cyan)
  -- 天气与时钟**紧挨着风**：它们说的是同一件事——"现在的环境"。
  -- 风影响弹道、天气决定看得见什么、时钟决定昼夜，摆成一排才好一起读
  if ctx.weather then
    cx = seg(S, cx + 2, 0, ((ctx.clock and (ctx.clock .. " ")) or "") .. ctx.weather,
             ctx.weather_tone or C.gray)
  end
  -- 轮到哪一方：只说阵营，不重复"谁在操作"（那由侧栏的记号负责）
  local whose = (ctx.turn_team == 1) and t.own or t.foe
  if ctx.pvp then
    whose = (ctx.turn_team == 1) and t.p1 or t.p2
  end
  cx = seg(S, cx + 2, 0, whose, (ctx.turn_team == 1) and C.yellow or C.red)
  -- 队友交给 AI 时要说清楚"现在不是你在操作"，否则玩家会以为卡住了
  if ctx.ally_ai and ctx.turn_team == 1 and not ctx.human then
    cx = seg(S, cx + 2, 0, t.ally, C.dark_gray)
  end

  -- "弹药飞行中 / 本回合已开炮"这一类的**发射状态**放第 2 行右端，不跟第 0 行：
  -- 它跟在阵营后面时，中英文一长就顶出屏幕（英文尤其）。武器那一行给它留出宽度，
  -- 底部两行本来讲的就是"这一炮"
  local note, note_col
  if ctx.phase == "flying" then
    note, note_col = ctx.flight_note or "", C.orange
  elseif w and w.buried then
    -- 被地形炮埋住：走不动，只能自己炸开（这就是那件武器的牵制作用），必须说清楚，
    -- 否则玩家只会以为"卡住了"
    note, note_col = t.buried, C.yellow
  elseif ctx.shots_left == 0 then
    note, note_col = t.fired, C.dark_gray
  end
  local weapon_end -- 武器那一行画到第几列（发射状态跟在它后面，见下）

  -- 第 1 行：角度（可以是负的 = 朝下）、力度、力度条
  if w and w.alive then
    local px = seg(S, 1, 1, string.format("%s %d° %s", t.angle, math.floor(w.angle + 0.5),
                                          w.facing > 0 and "→" or "←"), C.yellow)
    local power = w.power or 0
    px = seg(S, px + 2, 1, string.format("%s %d%%", t.power, math.floor(power * 100 + 0.5)),
             ctx.charge and C.yellow or C.white)
    local filled = math.floor(power * 20)
    seg(S, px + 2, 1, "[" .. string.rep("#", filled) .. string.rep(".", 20 - filled) .. "]",
        ctx.charge and C.yellow or (power > 0.85 and C.red or C.green))
  end


  -- 第 2 行：武器、威力、余弹。
  -- "威力"必须写出来：散射弹是"单发×枚数"（霰弹 11×5），治疗弹是"+60"（回血），
  -- 其余按面板伤害。玩家选弹时最需要知道的就是这一件打出去是多少
  if ctx.weapon then
    local spec = ctx.weapon
    local name = phos.lang.pick(spec.name)
    local n = ctx.ammo or 0
    local ammo_txt = (n < 0) and t.inf or tostring(n)
    local power
    if (spec.heal or 0) > 0 then
      power = "+" .. spec.heal
    elseif (spec.shells or 1) > 1 then
      power = string.format("%d×%d", spec.damage or 0, spec.shells)
    elseif (spec.orbital or 0) ~= 0 then
      power = string.format("%d×%d", spec.orbital.damage or 0,
                            math.floor(spec.orbital.life / spec.orbital.tick))
    elseif (spec.raise or 0) > 0 then
      power = t.terrain
    else
      power = tostring(spec.damage or 0)
    end
    local line = phos.text.fit(
      string.format("%s %s %s   x%s", t.weapon, name, power, ammo_txt), play_w - 2)
    S:print(1, 2, line, (n == 0) and C.dark_gray or C.white)
    weapon_end = 1 + phos.text.width(line)
  end
  if note and weapon_end then
    -- 发射状态紧跟弹药数（固定间距）：它说的就是"这一炮"，摆到右边框底下就与武器脱节了。
    -- 一行放不下就整条不画 —— 宁可少一句，也不要压到边框上或中途截断
    local x = weapon_end + NOTE_GAP
    if x + phos.text.width(note) <= play_w then
      S:print(x, 2, note, note_col)
    end
  end

  -- 伤害 / 治疗浮字与效果文字：受击点附近冒出来，1 秒后消失。
  -- **不垫底板**：字是压在世界上的一层，只写字形、不动背景。
  -- 垫了底板会在战况里挖出一块块黑方块，比字本身还抢眼。
  -- f.text 是"没有数字"的说明（落海、燃烧、没弹药），此时不该硬拼出一个 -0
  for _, f in ipairs(ctx.floats or {}) do
    local text = f.text or string.format("-%d", math.floor((f.damage or 0) + 0.5))
    -- 颜色**只由 add_float 一处决定**（伤害红、治疗绿、落海蓝……），这里只负责画。
    -- 在这里按"有没有文字"再挑一次色的话，伤害数字会被画成白色 —— 规矩就分成了两处
    S:print(f.x, f.y, text, f.color or C.white)
  end
end

-- 血条：画在虫子头顶，**不垫底板**（不传底色 = 保留该格原本的底，不会挖出黑洞）。
-- 底板是**整格**粒度的：垫上就比字身宽出一格，压在斜坡或水面上更像"挖了个洞"。
-- 可读性靠配色：地形偏绿，满血用**青色**，括号用白色压住两端 ——
-- 无论压在山体还是海里都读得出来。
-- frac 是当前血量**比例**（0~1）：血量上限由开局菜单决定（10~800），
-- 所以这里一律按比例算格子与配色 —— 拿绝对值算的话，800 血的一局会永远显示满血青色
function Hud.hp_bar(S, C, x, y, frac)
  local f = math.max(0, math.min(1, frac or 0))
  local n = math.ceil(f * 6)
  local fill = (f > 0.6 and C.cyan) or (f > 0.25 and C.yellow) or C.red
  S:print(x - 3, y, "[", C.white)
  S:print(x - 2, y, string.rep("=", n) .. string.rep("-", 6 - n), fill)
  S:print(x + 4, y, "]", C.white)
end

return Hud

"""balance_model.py —— towerdef 难度模型的**可复算参考实现**（DESIGN §5.4）。

设计目标：用「经济 I(w) → 我方火力 P(w) → 敌人强度 Etarget(w)」推出一条**逐波**血/赏金曲线，
不硬编码逐波难度；同一波对所有玩家强度一致（不做局内动态调节）；取**中位数**玩家强度。

链条（waves.lua 加载期用同一套公式推导，本脚本是独立复算）：
  1) FPC   = 所有攻击塔 F/cost 的中位数（F = dps·range；连续塔用 dps；
             AoE 乘 (1+splash)；连锁乘 chain 数）。
  2) I(w)  = 起始金币 + Σ_{i≤w}( 赏金 + 波清奖金 15+2i + INCLUDE·P_MED·max_bonus(i) )；
             赏金 = Σ count·base_bounty·reward_growth(i)；
             max_bonus(i) = WAIT_A + WAIT_B·i 是第 i 波的"满额等待金"（game.lua 提前放波）。
  3) P(w)  = I(w)·FPC·EFF。
  4) Ebase(w) = Σ count·(hp + ARMOR_W·armor + shield)（装甲/护盾折算进有效血）。
  5) Etarget(w) = P(w)·R·S(w)，S(w) = 1 + S_SLOPE·(w-1)。
  6) hp_growth(w) = Etarget(w)/Ebase(w)（逐波算，非手填表）；reward_growth 由经济目标反推。

等待金入账规则（game.lua §6.4）：build 期按"剩余秒/60"给 **比例×满额**；combat 期（波没清完
就招下一波）给 **满额**。模型里用一个**中位实现比例 P_MED**（玩家不总提前招、且常建到一半才招）
估中位玩家实际拿到的比例，再乘 **INCLUDE(≈0.5)** 折入 I(w)——即"等待金只按一半计入怪物强度"，
让它的*短期手感*奖励大于它对*怪物曲线*的长期影响。

**注意**：hp_growth 会随模板组成波动（boss 波基础血高 → 乘子低）。这正是让 E(w)/P(w) 保持
平缓的机制——若强行把 hp_growth 平滑成单调，E/P 会摆动 4~10 倍（见文末 sanity）。所以这里
只导出"逐波推导"的乘子，靠它抵消模板抖动，使**玩家能感到的难度曲线 E(w)/P(w)** 平滑上升。

用法: python balance_model.py
"""
import math

# ── 敌人最小输入表（与 enemies.lua / waves.lua MODEL_ENEMY 三处同步）──
ENEMY = {
    "grunt":  dict(hp=60,   armor=0, bounty=5,   shield=0),
    "runner": dict(hp=40,   armor=0, bounty=6,   shield=0),
    "swarm":  dict(hp=25,   armor=0, bounty=2,   shield=0),
    "armor":  dict(hp=220,  armor=5, bounty=13,  shield=0),
    "shield": dict(hp=140,  armor=0, bounty=15,  shield=40),
    "flyer":  dict(hp=90,   armor=0, bounty=10,  shield=0),
    "boss":   dict(hp=2600, armor=8, bounty=170, shield=0),
}

# ── 20 波模板（与 waves.lua TEMPLATES 同步；只用于聚合 Ebase/赏金）──
TEMPLATES = [
    [("grunt", 6, 1.0)],
    [("grunt", 10, 0.8)],
    [("runner", 8, 0.7)],
    [("grunt", 8, 0.7), ("runner", 6, 0.6)],
    [("armor", 4, 1.5)],
    [("swarm", 20, 0.25)],
    [("flyer", 6, 1.0)],
    [("grunt", 12, 0.7), ("armor", 4, 1.4)],
    [("shield", 5, 1.2)],
    [("boss", 1, 0.0), ("grunt", 8, 0.8)],
    [("runner", 14, 0.5)],
    [("swarm", 30, 0.2), ("flyer", 8, 0.9)],
    [("armor", 8, 1.2)],
    [("shield", 8, 1.0), ("grunt", 10, 0.7)],
    [("boss", 1, 0.0), ("flyer", 10, 0.8), ("runner", 10, 0.6)],
    [("swarm", 40, 0.18), ("armor", 6, 1.3)],
    [("shield", 10, 0.9), ("flyer", 10, 0.8)],
    [("armor", 12, 1.0), ("runner", 16, 0.5)],
    [("grunt", 20, 0.5), ("armor", 10, 1.0), ("shield", 8, 0.9), ("flyer", 10, 0.7)],
    [("boss", 2, 0.0), ("swarm", 40, 0.18), ("armor", 10, 1.0)],
]
TOTAL = len(TEMPLATES)

# ── 攻击塔（与 towers.lua 同步；FPC 就是这张表的中位数，见下）──
TOWERS = {
    "GUN":    dict(cost=50,  dmg=9,  rate=0.35, range=5.0),
    "CANNON": dict(cost=95,  dmg=34, rate=1.25, range=6.0, splash=1.6),
    "FROST":  dict(cost=70,  dmg=5,  rate=0.70, range=5.0),
    "TESLA":  dict(cost=130, dmg=24, rate=1.40, range=5.5, chain=3),
    "FLAME":  dict(cost=115, dps=13,            range=3.0, splash=2.0),
    "LASER":  dict(cost=120, dmg=26, rate=1.0,  range=7.0),
    "HELL":   dict(cost=150, dps=8,             range=5.0),
    "SNIPER": dict(cost=140, dmg=90, rate=2.4,  range=9.0),
    "MORTAR": dict(cost=135, dmg=40, rate=1.6,  range=8.0, splash=2.2),
}

# ── 模型常量（含义 + 取值理由，见 DESIGN §5.4）─────────────────────────
ARMOR_W   = 20.0    # 每点 armor 折算的等效血量：armor=5 → 装甲等效血约 ×1.45
EFF       = 0.50    # 中位数玩家把金币转成"有效火力"的效率（布局/空转/超杀/欠压/雷达地堡）
S_SLOPE   = 0.02    # 每波目标松紧缓坡：后期略紧，不突变
CLEAR_A, CLEAR_B = 15.0, 2.0                # 波清奖金 = A + B·w（game.lua check_end）
BUILD_TIME = 60.0                           # 每波等待秒数（game.lua BUILD_TIME；满额=整段都省掉）
WAIT_A, WAIT_B = 10.0, 2.0                  # 满额等待金 max_bonus(w) = A + B·w（waves.wait_bonus_max）
P_MED     = 0.50    # 中位实现比例：玩家不总提前招，且常建到一半才招 → 中位拿到满额的一半
INCLUDE   = 0.50    # 等待金折入 I(w) 的比例：只按一半计入怪物强度（手感奖励 > 曲线影响）
REWARD_MAX = 1.20   # 赏金乘子全程上限：数量已驱动收入增长 18×，乘子再快就滚雪球
HP_GROWTH_1 = 1.0   # 标定：第 1 波（NORMAL）血乘子 = 1.0（开局面值，平顺）

def dps(d):   return d["dps"] if "dps" in d else d["dmg"] / d["rate"]
def firepower(d):
    f = dps(d) * d["range"]
    if "splash" in d: f *= (1.0 + d["splash"])
    if "chain" in d:  f *= d["chain"]
    return f
def fpc():
    vals = sorted(firepower(d) / d["cost"] for d in TOWERS.values())
    n = len(vals); m = n // 2
    return vals[m] if n % 2 else 0.5 * (vals[m - 1] + vals[m])
FPC = fpc()

def base_hp(kind):
    e = ENEMY[kind]
    return e["hp"] + ARMOR_W * e["armor"] + e["shield"]
def Ebase(w):    return sum(c * base_hp(t) for t, c, _ in TEMPLATES[w - 1])
def base_bounty(w): return sum(c * ENEMY[t]["bounty"] for t, c, _ in TEMPLATES[w - 1])

def S(w):          return 1.0 + S_SLOPE * (w - 1)
def clear_bonus(w):return CLEAR_A + CLEAR_B * w
def max_bonus(w):  return WAIT_A + WAIT_B * w
def wait_est(w):   return INCLUDE * P_MED * max_bonus(w)   # 折入 I 的中位等待金

RG_SLOPE = (REWARD_MAX - 1.0) / (TOTAL - 1)      # reward_growth 由"乘子上限"反推
def reward_growth(w): return 1.0 + RG_SLOPE * (w - 1)

def income(w, include_wait=True):
    s = 0.0
    for i in range(1, w + 1):
        s += base_bounty(i) * reward_growth(i) + clear_bonus(i)
        if include_wait:
            s += wait_est(i)
    return s
def P(w, credits0): return (credits0 + income(w)) * FPC * EFF

# R：整体松紧，标定 hp_growth(1)=HP_GROWTH_1（用 NORMAL 的起始金币）
NORMAL_CREDITS = 130
R = HP_GROWTH_1 * Ebase(1) / P(1, NORMAL_CREDITS)
def hp_growth(w): return P(w, NORMAL_CREDITS) * R * S(w) / Ebase(w)

DIFF = {
    # credits / core / hp 乘数 / speed 乘数
    "EASY":   dict(credits=170, core=25, hp=0.80, speed=0.90),
    "NORMAL": dict(credits=130, core=20, hp=1.00, speed=1.00),
    "HARD":   dict(credits=120, core=15, hp=1.15, speed=1.05),
}

# 无尽：强度按模型在第 15→20 波的平均每波增幅线性外推（对齐第 20 波，去掉单波噪声）
def Etarget(w): return P(w, NORMAL_CREDITS) * R * S(w)
EL_RATE = (Etarget(TOTAL) / Etarget(TOTAL - 5)) ** (1.0 / 5) - 1.0
def hp_growth_endless(w): return hp_growth(TOTAL) * (1.0 + EL_RATE * (w - TOTAL))

# ── 报告 ─────────────────────────────────────────────────────────────
def row(name, d, tag):
    print("\n── %s %s ──" % (name, tag))
    print(" w |  I(w)含 | I(w)不含 |   P(w)  |  Ebase  | Etarget |hp_gro |  E/P  ")
    print("-" * 84)
    for w in range(1, TOTAL + 1):
        Iw = d["credits"] + income(w, True)
        Inw = d["credits"] + income(w, False)
        Pw = Iw * FPC * EFF
        Eb = Ebase(w)
        Et = Pw * R * S(w) * d["hp"]
        g = hp_growth(w)
        Ep = Eb * g * d["hp"] / Pw
        print("%2d | %6.0f | %7.0f | %7.0f | %7.0f | %7.0f | %5.2f | %5.2f" % (
            w, Iw, Inw, Pw, Eb, Et, g, Ep))
    ep = [Ebase(w) * hp_growth(w) * d["hp"] / (d["credits"] + income(w)) / (FPC * EFF)
          for w in range(1, TOTAL + 1)]
    print("   E/P 范围 %.2f..%.2f（末/首 %.2f）" % (min(ep), max(ep), ep[-1] / ep[0]))

def _entry(text, key):
    """从 Lua 源码里粗取 `key = { ... }` 的表体（花括号配平）。仅用于同步自检。"""
    import re
    m = re.search(r"\b" + re.escape(key) + r"\s*=\s*\{", text)
    if not m:
        return None
    i = text.index("{", m.start())
    depth = 0
    for j in range(i, len(text)):
        if text[j] == "{":
            depth += 1
        elif text[j] == "}":
            depth -= 1
            if depth == 0:
                return text[i:j + 1]
    return None


def _nums(seg, *keys):
    import re
    out = {}
    for k in keys:
        m = re.search(r"\b" + k + r"\s*=\s*([0-9]+(?:\.[0-9]+)?)", seg)
        out[k] = float(m.group(1)) if m else 0.0
    return out


def check_sync():
    """三处同步自检：enemies.lua / waves.lua 的 MODEL_ENEMY / 本文件的 ENEMY ——
    以及 towers.lua 推出的 FPC 与 waves.lua 里写死的 FPC。失败只告警，不阻断。"""
    import os, re
    here = os.path.dirname(os.path.abspath(__file__))
    root = os.path.join(here, "..")
    problems = []
    try:
        enemies = open(os.path.join(root, "enemies.lua"), encoding="utf-8").read()
        waves = open(os.path.join(root, "waves.lua"), encoding="utf-8").read()
        towers = open(os.path.join(root, "towers.lua"), encoding="utf-8").read()
        game = open(os.path.join(root, "game.lua"), encoding="utf-8").read()
    except OSError as e:
        print("同步自检：读源文件失败（跳过）：%s" % e)
        return
    for t, ref in ENEMY.items():
        for src, txt in (("enemies.lua", enemies), ("waves.lua", waves)):
            seg = _entry(txt, t)
            got = _nums(seg, "hp", "armor", "bounty", "shield") if seg else {}
            for k in ("hp", "armor", "bounty", "shield"):
                if got.get(k, None) != float(ref[k]):
                    problems.append("%s.%s.%s=%s ≠ model %s" % (src, t, k, got.get(k), ref[k]))
    # FPC：从 towers.lua 攻击塔重算，和 waves.lua 里写死的常量比
    try:
        vals = []
        for name, d in TOWERS.items():
            seg = _entry(towers, name) or ""
            g = _nums(seg, "cost", "dmg", "rate", "range", "splash", "chain")
            cont = re.search(r"\bdps\s*=\s*true", seg) is not None
            dps = g["dmg"] if cont else (g["dmg"] / g["rate"] if g["rate"] > 0 else 0.0)
            f = dps * g["range"] * ((1 + g["splash"]) if g["splash"] else 1) * (g["chain"] or 1)
            vals.append(f / g["cost"])
        vals.sort()
        n = len(vals)
        mm = re.search(r"FPC = ([0-9.]+)", waves)
        fpc_lua = float(mm.group(1)) if mm else 0.0
        fpc_calc = vals[n // 2] if n % 2 else 0.5 * (vals[n // 2 - 1] + vals[n // 2])
        if abs(fpc_calc - fpc_lua) > 1e-3:
            problems.append("FPC: towers.lua 推出 %.4f ≠ waves.lua %.4f" % (fpc_calc, fpc_lua))
    except Exception as e:
        problems.append("FPC 自检异常：%r" % e)
    # 等待金经济常量：waves.lua（WAIT_A/B、P_MED、INCLUDE）与 game.lua（BUILD_TIME）
    try:
        def one(pat, txt):
            m = re.search(pat, txt)
            return float(m.group(1)) if m else None
        m = re.search(r"WAIT_A,\s*WAIT_B\s*=\s*([0-9.]+),\s*([0-9.]+)", waves)
        wa, wb = (float(m.group(1)), float(m.group(2))) if m else (None, None)
        pmed = one(r"P_MED\s*=\s*([0-9.]+)", waves)
        inc = one(r"INCLUDE\s*=\s*([0-9.]+)", waves)
        btime = one(r"Game\.BUILD_TIME\s*=\s*([0-9.]+)", game)
        for label, got, ref in (("WAIT_A", wa, WAIT_A), ("WAIT_B", wb, WAIT_B),
                                ("P_MED", pmed, P_MED), ("INCLUDE", inc, INCLUDE),
                                ("BUILD_TIME(game.lua)", btime, BUILD_TIME)):
            if got is None or abs(got - ref) > 1e-6:
                problems.append("%s: 源=%s ≠ model %s" % (label, got, ref))
    except Exception as e:
        problems.append("等待金常量自检异常：%r" % e)
    if problems:
        print("同步自检：发现 %d 处不一致（改 enemies/towers 要同步 waves.MODEL_ENEMY/FPC + 本文件）:" % len(problems))
        for p in problems:
            print("  ! " + p)
    else:
        print("同步自检：enemies.lua / towers.lua / waves.lua / balance_model.py 一致 ✓")


def main():
    check_sync()
    print("=" * 84)
    print("FPC = %.4f  R = %.4f  EL_RATE = %.4f  RG_SLOPE = %.6f" % (FPC, R, EL_RATE, RG_SLOPE))
    print("ARMOR_W = %.1f  EFF = %.2f  S_SLOPE = %.3f" % (ARMOR_W, EFF, S_SLOPE))
    print("BUILD_TIME = %.0f  max_bonus(w) = %.0f + %.0f·w  P_MED = %.2f  INCLUDE = %.2f" % (
        BUILD_TIME, WAIT_A, WAIT_B, P_MED, INCLUDE))
    print("等待金折入 I：每波 = INCLUDE·P_MED·max_bonus(w) = %.3f·(%.0f+%.0f·w)；"
          "w1=%.1f w10=%.1f w20=%.1f" % (
        INCLUDE * P_MED, WAIT_A, WAIT_B,
        wait_est(1), wait_est(10), wait_est(20)))
    print("=" * 84)
    for name in ("EASY", "NORMAL", "HARD"):
        d = DIFF[name]
        row(name, d, "(credits=%d core=%d hp×%.2f speed×%.2f)" % (
            d["credits"], d["core"], d["hp"], d["speed"]))
    # 关键波次
    print("\nhp_growth(1..20) = " + ", ".join("%.3f" % hp_growth(w) for w in range(1, TOTAL + 1)))
    print("reward_growth(1,10,20) = %.3f, %.3f, %.3f" % (
        reward_growth(1), reward_growth(10), reward_growth(20)))
    print("hp_growth_endless(21,25,30) = %.3f, %.3f, %.3f" % (
        hp_growth_endless(21), hp_growth_endless(25), hp_growth_endless(30)))
    # sanity：三档 E/P 开局不突刺 + 全程缓升（E/P == R·S(w)·档位系数，理论上就是直线）
    ok = True
    for name in ("EASY", "NORMAL", "HARD"):
        d = DIFF[name]
        ep = [Ebase(w) * hp_growth(w) * d["hp"] / (d["credits"] + income(w)) / (FPC * EFF)
              for w in range(1, TOTAL + 1)]
        early_ok = ep[0] <= min(ep) * 1.05 + 1e-9   # 开局就是最低档（不突刺）
        rise = ep[-1] > ep[0]
        ok = ok and early_ok and rise
        print("  %-6s 开局最低=%s  末/首=%.2f  E/P %.2f..%.2f" % (
            name, early_ok, ep[-1] / ep[0], min(ep), max(ep)))
    print("目标（开局低 + 全程平缓上升）：", "OK" if ok else "FAIL")


if __name__ == "__main__":
    main()

"""td_features.py —— 新功能定点验收（无尽 / 塔血量破墙 / 维修塔 / AI 优先级 /
13 型建造列表 / 采矿机产金 / 战斗中提前放波 / 欠压降载）。

每个用例起一局干净进程，走控制通道真玩，读 debug_state 断言。
用法: python td_features.py [base_seed]
"""
import json, os, sys, time
from td_play import Host, Bot, SAVES
from td_checks import Game

PORT_BASE = 8600
_results = []


def check(name, ok, detail=""):
    _results.append((name, ok, detail))
    print(("  PASS " if ok else "  FAIL ") + name + ("  " + detail if detail else ""))


# ── A：无尽模式 ──────────────────────────────────────────────────────
def run_endless_once(seed, stop_wave=21, timeout=420):
    sdir = os.path.join(SAVES, str(seed))
    os.makedirs(sdir, exist_ok=True)
    sav = os.path.join(sdir, "towerdef.sav")
    if os.path.exists(sav):
        os.remove(sav)  # 两次跑从同一默认菜单起，输入序列才逐位一致
    h = Host(7900 + (seed % 100), seed)
    try:
        h.set_param("Start credits", 5000)
        bot = Bot(h, seed, cheat=True, verbose=False)
        st = bot.run("EASY", "OPEN", 400000, timeout=timeout,
                     endless=True, stop_wave=stop_wave)
    finally:
        h.close()
    return st


def test_endless(seed):
    st = run_endless_once(seed, stop_wave=22)
    check("A: 无尽模式越过第 20 波（不判通关）",
          st["max_wave"] > 20 and not st["won"] and not st["over"],
          "max_wave=%d phase=%s" % (st["max_wave"], st["end"]["phase"]))
    check("A: 第 21 波内容由预算生成（多种类型花预算）",
          len(st.get("wave21", [])) >= 3, "wave21=%s" % st.get("wave21"))
    return st


def test_endless_repro(seed):
    a = run_endless_once(seed, stop_wave=22)
    b = run_endless_once(seed, stop_wave=22)
    same = (a.get("wave21") == b.get("wave21")
            and a["max_wave"] == b["max_wave"])
    check("A: 同种子同输入 → 无尽波次可复现",
          same, "wave21 %s vs %s" % (a.get("wave21"), b.get("wave21")))


# ── B：塔血量 ────────────────────────────────────────────────────────
def test_tower_hp(seed):
    g = Game(seed, diff="EASY", style="OPEN")
    try:
        check("B: 建出 GUN", g.build_near("GUN"))
        d = g.debug()
        t = d["towers"][0]
        check("B: 塔带 hp/max_hp（GUN=100）",
              t["hp"] == 100 and t["max_hp"] == 100,
              "hp=%s/%s" % (t.get("hp"), t.get("max_hp")))
    finally:
        g.close()


# ── C：维修塔 ────────────────────────────────────────────────────────
def test_repair(seed):
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        g.move_to(g.mw - 6, g.mh // 2)
        ok_r = g.build_near("REACTOR")
        reactors = [t for t in g.debug()["towers"] if t["type"] == "REACTOR"]
        check("C: 建出反应堆（被拆对象）", ok_r and len(reactors) == 1)
        if not reactors:
            return
        r = reactors[0]
        ok_rep = False
        for dx, dy in ((0, 1), (0, -1), (1, 0), (-1, 0), (1, 1), (-1, -1)):
            g.move_to(r["x"] + dx, r["y"] + dy)
            if g.build_here("REPAIR"):
                ok_rep = True
                break
        check("C: 建出维修塔 REPAIR", ok_rep)
        g.h.step("space")            # 提前放波
        g.h.step(None, frames=3600)  # 让敌人拆反应堆、维修塔治疗
        d = g.debug()
        check("C: 维修塔确实治疗了受损友军（heals>0）",
              d.get("heals", 0) > 0, "heals=%s" % d.get("heals"))
    finally:
        g.close()


# ── D：AI 目标优先级 ─────────────────────────────────────────────────
def test_reactor_priority(seed):
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        # 反应堆放在刷怪口正前方（OPEN 单口在左侧中部），敌人一出场就在 8 格侦察圈内
        g.move_to(4, g.mh // 2)
        if not g.build_near("REACTOR"):
            check("D: 建出反应堆", False)
            return
        check("D: 建出反应堆", True)
        g.h.step("space")
        found, dumped = False, False
        reactor = [t for t in g.debug()["towers"] if t["type"] == "REACTOR"][0]
        for _ in range(200):
            for e in g.debug()["enemies"]:
                if e.get("reason") == "reactor":
                    found = True
            if found:
                break
            g.h.step(None, frames=15)
        # 顺带验证反应堆被扣血（真的在拆）
        dmg = False
        for _ in range(200):
            rr = next((t for t in g.debug()["towers"] if t["type"] == "REACTOR"), None)
            if rr is None or rr["hp"] < rr["max_hp"]:
                dmg = True
                break
            g.h.step(None, frames=30)
        check("D: 敌人把最近反应堆选为目标（P1）", found)
        check("D: 反应堆被拆掉血/拆除", dmg)
    finally:
        g.close()


# ── E：新增塔型（LASER / HELL / SNIPER / MORTAR）────────────────────
def test_new_towers(seed):
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        # 建造列表应含全部 13 型（X 循环一圈不重样）
        seen = set()
        for _ in range(13):
            seen.add(g.debug()["selected_type"])
            g.h.step("x")
        check("E: 建造列表含 13 型", len(seen) == 13, "seen=%d" % len(seen))

        # 四种新塔都能建出来（放在刷怪口前方，敌人会路过它们的射程）
        new_types = ["LASER", "HELL", "SNIPER", "MORTAR"]
        spots = [(5, g.mh // 2 - 2), (7, g.mh // 2 - 2), (5, g.mh // 2 + 2), (7, g.mh // 2 + 2)]
        placed = {}
        for typ, (cx, cy) in zip(new_types, spots):
            got = False
            for dx in range(0, 5):
                for dy in range(-3, 4):
                    g.move_to(max(1, min(g.mw - 2, cx + dx)), max(1, min(g.mh - 2, cy + dy)))
                    if g.build_here(typ):
                        got = True
                        break
                if got:
                    break
            placed[typ] = got
        check("E: 四种新塔都能建造", all(placed.values()), str(placed))

        types = {t["type"] for t in g.debug()["towers"]}
        check("E: 新塔已进入场上", all(nt in types for nt in new_types), str(sorted(types)))

        # 放一波，验证新塔真能开火并结算击杀（血条/连续/抛射各有各的结算路径）
        g.h.step("space")
        g.h.step(None, frames=3600)
        d = g.debug()
        kills = sum(t["kills"] for t in d["towers"] if t["type"] in new_types)
        check("E: 新塔能开火并击杀", kills > 0, "kills=%d" % kills)
    finally:
        g.close()


# ── D2：敌人也拆采矿机（与反应堆同一套 P1）──────────────────────────
def test_miner_priority(seed):
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        # 采矿机放在刷怪口正前方：敌人一出场就在侦察圈内，会把它当"值钱目标"拆
        g.move_to(4, g.mh // 2)
        ok = g.build_here("MINER")
        check("D2: 建出采矿机", ok)
        if not ok:
            return
        g.h.step("space")
        found = False
        for _ in range(240):
            if any(e.get("reason") == "reactor" for e in g.debug()["enemies"]):
                found = True
                break
            g.h.step(None, frames=15)
        check("D2: 敌人把采矿机当 P1 目标拆（reason=reactor 类）", found)
    finally:
        g.close()


# ── F：采矿机（周期产金 / 吃电）──────────────────────────────────────
def test_miner(seed):
    g = Game(seed, diff="EASY", style="OPEN")
    try:
        ok = False
        for dx in range(0, 6):
            g.move_to(min(g.mw - 2, g.mw // 2 + dx), g.mh // 2)
            if g.build_here("MINER"):
                ok = True
                break
        check("F: 建出采矿机", ok)
        if not ok:
            return
        d0 = g.debug()
        check("F: 采矿机占 8 电（L1）", d0["power_used"] == 8, "used=%d" % d0["power_used"])
        # 布防期无敌人 → 金币上涨只可能来自采矿机（L1 = 每 6s +5）
        g.h.step(None, frames=400)
        d1 = g.debug()
        check("F: 布防期采矿机产金（≥ +5）",
              d1["credits"] >= d0["credits"] + 5,
              "credits %d -> %d" % (d0["credits"], d1["credits"]))
    finally:
        g.close()


# ── G：战斗中提前放波（场上最多两拨）────────────────────────────────
def test_early_wave(seed):
    g = Game(seed, diff="EASY", style="OPEN")
    try:
        g.h.step("space")            # 布防期提前放第 1 波
        d = g.debug()
        check("G: 布防期 space 开第 1 波", d["wave"] == 1 and d["phase"] == "combat",
              "wave=%d phase=%s" % (d["wave"], d["phase"]))
        g.h.step(None, frames=600)   # 让第 1 波出怪
        check("G: 场上只有一拨", g.debug()["active_waves"] == 1,
              "active=%d" % g.debug()["active_waves"])
        g.h.step("space")            # 战斗中提前招第 2 波
        d = g.debug()
        check("G: 战斗中能招下一波（wave 2 / 两拨）",
              d["wave"] == 2 and d["active_waves"] == 2,
              "wave=%d active=%d" % (d["wave"], d["active_waves"]))
        g.h.step("space")            # 再按：两拨在手 → 应被拒
        d = g.debug()
        check("G: 已有两拨时再招被拒（wave 不变）",
              d["wave"] == 2 and d["active_waves"] == 2,
              "wave=%d active=%d" % (d["wave"], d["active_waves"]))
    finally:
        g.close()


# ── H：欠压（按超出比例降载）────────────────────────────────────────
def test_overload(seed):
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        # 基础电力上限 8；不建反应堆，纯堆塔把它顶过去（GUN 每座 1 电）
        for i in range(40):
            g.move_to(min(g.mw - 2, 3 + i % 12), min(g.mh - 2, 3 + (i // 12) * 2))
            g.build_here("GUN")
            if g.debug()["overload"]:
                break
        d = g.debug()
        check("H: 堆塔触发欠压", d["overload"], "used=%d cap=%d" % (d["power_used"], d["power_cap"]))
        if not d["overload"]:
            return
        over = (d["power_used"] - d["power_cap"]) / max(1, d["power_cap"])
        check("H: 降载比例 = 超出比例（overload_over）",
              abs(d["overload_over"] - over) < 1e-6,
              "over=%.3f reported=%.3f" % (over, d["overload_over"]))
        check("H: 降载系数 = max(0.2, 1-超出)（overload_rate）",
              abs(d["overload_rate"] - max(0.2, 1 - over)) < 1e-6,
              "rate=%.3f" % d["overload_rate"])
    finally:
        g.close()


def main():
    base = int(sys.argv[1]) if len(sys.argv) > 1 else 1400
    print("== towerdef 新功能验收 (A–H) ==")
    for fn, off in [(test_tower_hp, 1), (test_repair, 2),
                    (test_reactor_priority, 3), (test_miner_priority, 11),
                    (test_endless, 4), (test_endless_repro, 5),
                    (test_new_towers, 6), (test_miner, 7),
                    (test_early_wave, 8), (test_overload, 9)]:
        print("-- %s --" % fn.__name__)
        try:
            fn(base + off)
        except Exception as e:
            check(fn.__name__ + " (exception)", False, repr(e))
    ok = sum(1 for _, o, _ in _results if o)
    print("\n%d/%d passed" % (ok, len(_results)))


if __name__ == "__main__":
    main()

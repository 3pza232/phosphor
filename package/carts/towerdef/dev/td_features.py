"""td_features.py —— A/B/C/D 新功能定点验收（无尽 / 塔血量破墙 / 维修塔 / AI 优先级）。

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


def main():
    base = int(sys.argv[1]) if len(sys.argv) > 1 else 1400
    print("== towerdef 新功能验收 (A/B/C/D) ==")
    for fn, off in [(test_tower_hp, 1), (test_repair, 2),
                    (test_reactor_priority, 3), (test_endless, 4),
                    (test_endless_repro, 5)]:
        print("-- %s --" % fn.__name__)
        try:
            fn(base + off)
        except Exception as e:
            check(fn.__name__ + " (exception)", False, repr(e))
    ok = sum(1 for _, o, _ in _results if o)
    print("\n%d/%d passed" % (ok, len(_results)))


if __name__ == "__main__":
    main()

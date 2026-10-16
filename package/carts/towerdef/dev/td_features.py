"""td_features.py —— 新功能定点验收（无尽 / 塔血量拆塔 / 维修塔 / AI 优先级 /
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
        d0 = g.debug()
        g.move_to(d0["core_x"] - 3, d0["core_y"])  # 贴磁芯：敌人会经过，便于拆它/被修
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

        # 四种新塔都能建出来并开火：放在磁芯供电圈内（基地 200 供电，四座正好 200），
        # 位置在磁芯左侧的进怪方向，敌人扑磁芯时会进入它们的射程。
        new_types = ["LASER", "HELL", "SNIPER", "MORTAR"]
        d0 = g.debug()
        cx0, cy0 = d0["core_x"], d0["core_y"]
        spots = [(cx0 - 4, cy0 - 2), (cx0 - 4, cy0 + 2), (cx0 - 2, cy0 - 2), (cx0 - 2, cy0 + 2)]
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
        d0 = g.debug()
        ok = False
        # 放在磁芯供电圈内（采矿机 L1 耗电 60，需通电才产金）
        for dx, dy in ((0, -2), (0, 2), (-2, -2), (-2, 2), (-3, 0), (-2, 0)):
            if g.build_at(d0["core_x"] + dx, d0["core_y"] + dy, "MINER"):
                ok = True
                break
        check("F: 建出采矿机", ok)
        if not ok:
            return
        d0 = g.debug()
        m = g.tower("MINER")
        check("F: 采矿机 L1 耗电 60 且被基地供电",
              m and m["draw"] == 60 and m["powered"] is True,
              "draw=%s powered=%s" % (m and m["draw"], m and m["powered"]))
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


# ── H：激光削弱（线宽 1/1/2、攻速加成 0.9）+ 电力 UI 移除 ────────────
def test_laser_nerf(seed):
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        check("H: 建出 LASER", g.build_near("LASER"))
        g.h.step("a")  # L2
        g.h.step("a")  # L3
        t = g.tower("LASER")
        check("H: 满级线宽=2（thickness_by {1,1,2}）",
              t and t["level"] == 3 and t["thick"] == 2,
              "lvl=%s thick=%s" % (t and t["level"], t and t["thick"]))
        # 攻速间隔 = base 1.0 × 0.9² = 0.81（旧版 0.8 → 0.64）
        check("H: 满级攻速间隔=0.81（up.rate 0.9，加成变小）",
              t and abs(t["interval"] - 0.81) < 1e-6,
              "interval=%s" % (t and t["interval"]))
    finally:
        g.close()


def test_ui_no_power(seed):
    """电力 UI 移除：顶部 HUD 与右栏都不再有全局电力读数（POWER）与旧字段。"""
    g = Game(seed, diff="EASY", style="OPEN")
    try:
        g.build_near("GUN")  # 让侧栏进入"塔详情"（含耗电行）
        g.h.step(None, frames=5)
        txt = g.screen()
        check("H: 顶部/右栏已无全局电力读数（无 POWER）", "POWER" not in txt,
              "screen 含 POWER" if "POWER" in txt else "")
        d = g.debug()
        old = [k for k in ("power_used", "power_cap", "overload", "overload_over", "overload_rate")
               if k in d]
        check("H: debug_state 已无旧电力字段", not old, "still=%s" % old)
        check("H: debug_state 报新电力（power 列表 + 每塔 powered）",
              isinstance(d.get("power"), list) and len(d["power"]) >= 1
              and "powered" in (d["towers"][0] if d["towers"] else {}))
    finally:
        g.close()


# ── I：存档 → 继续（完整对局快照）────────────────────────────────────
def test_save_continue(seed):
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        # 先形成一个"值得还原"的局面：两种塔 + 进战斗走一会
        g.build_near("GUN")
        g.move("right")
        g.build_near("CANNON")
        g.h.step("space")
        g.h.step(None, frames=300)
        d0 = g.debug()
        check("I: 存档前已有进度（wave>=1 且有塔）",
              d0["wave"] >= 1 and len(d0["towers"]) >= 1,
              "wave=%d towers=%d" % (d0["wave"], len(d0["towers"])))
        t0 = sorted((t["type"], t["x"], t["y"], t["level"]) for t in d0["towers"])

        # S：存档并回菜单（菜单态没有 cursor_x，读原始 debug 而非 Game.debug 封装）
        g.h.step("s")
        dm = g.h.debug()
        check("I: S 后回到菜单", dm["phase"] == "menu", dm["phase"])
        s0 = g._saved("save", "")
        check("I: save 已写入且非空", bool(s0), "len=%d" % len(s0))
        check("I: save_used=0（可继续）", g._saved("save_used", "") == "0")
        check("I: 菜单出现继续行", g.h.debug().get("has_save") is True)

        # 导航到"继续"行（menu_rows.CONTINUE = 5）并按 A 载入
        for _ in range(12):
            if g.h.debug().get("menu_row") == 5:
                break
            g.h.step("down")
        check("I: 选中继续行", g.h.debug().get("menu_row") == 5)
        g.h.step("a")
        d1 = g.debug()  # 载入那一帧 update 提前 return：这里读到的就是原始恢复态

        check("I: 继续后回到对局", d1["phase"] in ("build", "combat"), d1["phase"])
        check("I: credits 与存档前一致", d1["credits"] == d0["credits"],
              "%s vs %s" % (d1["credits"], d0["credits"]))
        check("I: wave 与存档前一致", d1["wave"] == d0["wave"],
              "%s vs %s" % (d1["wave"], d0["wave"]))
        check("I: 核心血与存档前一致", d1["core_hp"] == d0["core_hp"],
              "%s vs %s" % (d1["core_hp"], d0["core_hp"]))
        t1 = sorted((t["type"], t["x"], t["y"], t["level"]) for t in d1["towers"])
        check("I: 塔数量与类型一致", t0 == t1, "%s vs %s" % (t0, t1))
        check("I: 载入后 save_used=1（已消耗）", g._saved("save_used", "") == "1")

        # 往返一致性：载入后立刻再 S（此帧 game:update 不跑），重存应是同一串
        g.h.step("s")
        s1 = g._saved("save", "")
        check("I: 快照往返逐字一致（snapshot→restore→snapshot）", s0 == s1,
              "len %d vs %d" % (len(s0), len(s1)))
    finally:
        g.close()


# ── J：一局结束消耗存档（save_used=1）────────────────────────────────
def test_end_consumes(seed):
    g = Game(seed, diff="HARD", style="OPEN")
    try:
        g.h.step("period")
        g.h.step("period")
        over = False
        for _ in range(600):
            d = g.debug()
            if d["phase"] == "over":
                over = True
                break
            if d["phase"] == "build":
                g.h.step("space")
            g.h.step(None, frames=200)
        check("J: 一局打到结束（over）", over, "phase=%s" % g.debug()["phase"])
        check("J: 结束后 save_used=1", g._saved("save_used", "") == "1",
              "save_used=%s" % g._saved("save_used", ""))
    finally:
        g.close()


def main():
    base = int(sys.argv[1]) if len(sys.argv) > 1 else 1400
    print("== towerdef 新功能验收 (A–J) ==")
    for fn, off in [(test_tower_hp, 1), (test_repair, 2),
                    (test_reactor_priority, 3), (test_miner_priority, 11),
                    (test_endless, 4), (test_endless_repro, 5),
                    (test_new_towers, 6), (test_miner, 7),
                    (test_early_wave, 8), (test_laser_nerf, 9), (test_ui_no_power, 16),
                    (test_save_continue, 12), (test_end_consumes, 13)]:
        print("-- %s --" % fn.__name__)
        try:
            fn(base + off)
        except Exception as e:
            check(fn.__name__ + " (exception)", False, repr(e))
    ok = sum(1 for _, o, _ in _results if o)
    print("\n%d/%d passed" % (ok, len(_results)))


if __name__ == "__main__":
    main()

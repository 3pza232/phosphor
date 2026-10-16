"""td_power_shot.py —— 范围供电的视觉证据：截图 + 读屏。

产出（dev/shots/）：
  power_1_offline_x.png  断电塔**同格**叠红 x（另对照通电塔无 x）
  power_2_reactor_ring.png  光标在反应堆上 → 画供电圈
  power_3_build_ring.png    空地选反应堆待建 → 画供电圈
  power_4_base_panel.png    光标在磁基磁芯上 → 侧栏"发电 a/200"
用法: python td_power_shot.py [seed]
"""
import os, re, sys
from _paths import run_root  # noqa: F401  (确保 dev 目录可导入)
from td_checks import Game

DEV = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(DEV, "shots")


def find_offscreen(g):
    lines = g.screen().split("\n")
    core = g.debug()
    for Y, L in enumerate(lines):
        X = L.find("@")
        if X >= 0:
            return X - core["core_x"], Y - core["core_y"]
    raise SystemExit("找不到磁芯 @（screen 定位失败）")


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 4242
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        d = g.debug()
        print("core=(%d,%d) core_radius=%d  REACTOR_RADIUS=%d" % (
            d["core_x"], d["core_y"], d["core_radius"], d["power"][0]["radius"]
            if d["power"] and d["power"][0]["kind"] == "reactor" else 4))
        # 放在地图中部，供电圈不贴边、看得清
        p = g.find_slots([(0, 0), (2, 0), (0, 9)],
                         xr=range(g.mw // 3, g.mw // 2), yr=range(g.mh // 3, g.mh // 2))
        assert p, "no slots"
        ax, ay = p
        g.build_at(ax, ay, "REACTOR")
        g.build_at(ax + 2, ay, "GUN")     # 圈内 → 通电
        g.build_at(ax, ay + 9, "GUN")     # 圈外 → 断电
        d = g.debug()
        ts = {(t["x"], t["y"]): t for t in d["towers"]}
        print("reactor@(%d,%d)  在圈内 GUN powered=%s  圈外 GUN powered=%s" % (
            ax, ay, ts[(ax + 2, ay)]["powered"], ts[(ax, ay + 9)]["powered"]))

        # ── 1) 断电塔同格红 x ──
        g.move_to(1, 1)  # 移开光标
        px, py = find_offscreen(g)
        saw = False
        for _ in range(16):
            g.h.step(None, frames=5)
            lines = g.screen().split("\n")
            if lines[py + ay + 9][px + ax] == "x":
                saw = True
                break
        g.shot(os.path.join(SHOTS, "power_1_offline_x.png"))
        lines = g.screen().split("\n")
        print("① 断电塔(%d,%d) 格上字符=%r（闪烁红 x，saw=%s）；通电塔(%d,%d)=%r" % (
            ax, ay + 9, lines[py + ay + 9][px + ax], saw,
            ax + 2, ay, lines[py + ay][px + ax + 2]))

        # ── 2) 光标在反应堆上 → 供电圈 ──
        g.move_to(ax, ay)
        g.h.step(None, frames=3)
        g.shot(os.path.join(SHOTS, "power_2_reactor_ring.png"))
        txt = g.screen()
        m = re.search(r"OUT\s+\d+/\d+", txt)
        print("② 光标在反应堆：侧栏 %r（供电圈应见 dev/shots/power_2_reactor_ring.png）" % (m and m.group(0)))

        # ── 3) 空地选反应堆待建 → 供电圈 ──
        g.move_to(ax + 3, ay + 6)  # 挪到空地
        g.cycle_to("REACTOR")
        g.h.step(None, frames=3)
        g.shot(os.path.join(SHOTS, "power_3_build_ring.png"))
        print("③ 空地待建反应堆：见 dev/shots/power_3_build_ring.png（供电圈）")

        # ── 4) 基地磁芯：侧栏 发电 a/200 ──
        d = g.debug()
        g.move_to(d["core_x"], d["core_y"])
        g.h.step(None, frames=3)
        g.shot(os.path.join(SHOTS, "power_4_base_panel.png"))
        txt = g.screen()
        m = re.search(r"OUT\s+\d+/200", txt)
        print("④ 光标在基地磁芯：侧栏 %r" % (m and m.group(0)))

        # 未通电塔详情
        g.move_to(ax, ay + 9)
        g.h.step(None, frames=2)
        txt = g.screen()
        print("   断电塔详情含 'NO POWER':", "NO POWER" in txt,
              "| 含 'DRAW 20':", bool(re.search(r"DRAW\s+20", txt)))
    finally:
        g.close()


if __name__ == "__main__":
    main()

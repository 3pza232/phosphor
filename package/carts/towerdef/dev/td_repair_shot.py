"""td_repair_shot.py —— 造一处"反应堆被拆 + 维修塔治疗"的场面并截图，肉眼核对治疗特效。"""
import os, sys
from td_checks import Game

DEV = os.path.dirname(os.path.abspath(__file__))
SHOTS = os.path.join(DEV, "shots")


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1402
    g = Game(seed, diff="EASY", style="OPEN", credits=9000)
    try:
        g.move_to(4, g.mh // 2)
        g.build_near("REACTOR")
        r = [t for t in g.debug()["towers"] if t["type"] == "REACTOR"][0]
        ok = False
        # 维修塔离反应堆 3 格：光束够长，肉眼能看出是"从维修塔打过去"的
        for dx, dy in ((0, 3), (3, 0), (0, -3), (-3, 0), (0, 1), (1, 0)):
            g.move_to(r["x"] + dx, r["y"] + dy)
            if g.build_here("REPAIR"):
                ok = True
                break
        print("repair built:", ok)
        g.h.step("space")
        seen = 0
        for i in range(1500):
            d = g.debug()
            if d.get("heals", 0) > seen:
                seen = d["heals"]
                g.h.step(None, frames=3)
                break
            g.h.step(None, frames=3)
        os.makedirs(SHOTS, exist_ok=True)
        p = os.path.join(SHOTS, "repair_heal.png")
        g.h.cmd({"cmd": "screenshot", "path": p})
        print("heals=%s -> %s" % (g.debug().get("heals"), p))
    finally:
        g.close()


if __name__ == "__main__":
    main()

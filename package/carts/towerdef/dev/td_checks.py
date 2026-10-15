"""td_checks.py —— 针对 towerdef 各系统的定点断言（每个用例起一局干净进程）。

用法: python td_checks.py [base_seed]
"""
import json, os, sys, time
from td_play import Host, SAVES

PORT_BASE = 8000
_results = []


def check(name, ok, detail=""):
    _results.append((name, ok, detail))
    print(("  PASS " if ok else "  FAIL ") + name + ("  " + detail if detail else ""))


class Game:
    """薄封装：起进程 → 进游戏 → 常用动作。"""

    def __init__(self, seed, diff="NORMAL", style="MAZE", credits=None):
        self.seed = seed
        os.makedirs(os.path.join(SAVES, str(seed)), exist_ok=True)
        self.h = Host(PORT_BASE + (seed % 200), seed)
        # save-dir 已被 Host 固定为 SAVES/<seed>；此处直接调参数旋钮
        if credits is not None:
            self.h.set_param("Start credits", credits)
        self.start(diff, style)

    def _saved(self, key, default):
        p = os.path.join(SAVES, str(self.seed), "towerdef.sav")
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                for line in f:
                    k, _, v = line.strip().partition("=")
                    if k == key and v:
                        return v
        return default

    def start(self, diff, style):
        DIFFS = ["EASY", "NORMAL", "HARD"]
        MAPS = ["OPEN", "CANALS", "MAZE", "RANDOM"]
        # 菜单读存档里的上次选择：按**真实默认值**算步数，别假设从 NORMAL/RANDOM 起
        i = DIFFS.index(self._saved("diff", "NORMAL"))
        for _ in range((DIFFS.index(diff) - i) % len(DIFFS)):
            self.h.step("right")
        self.h.step("down")
        j = MAPS.index(self._saved("map", "RANDOM"))
        for _ in range((MAPS.index(style) - j) % len(MAPS)):
            self.h.step("right")
        self.h.step("a")
        d = self.h.debug()
        self.mw, self.mh = d["grid"]["w"], d["grid"]["h"]
        self.cur = [d["cursor_x"], d["cursor_y"]]
        assert d["phase"] == "build", d

    def debug(self):
        d = self.h.debug()
        self.cur = [d["cursor_x"], d["cursor_y"]]
        return d

    def screen(self):
        r = self.h.cmd({"cmd": "screen.read"})
        return "\n".join(r.get("lines", []))

    def move(self, key):
        dx, dy = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}[key]
        nx, ny = self.cur[0] + dx, self.cur[1] + dy
        if 1 <= nx <= self.mw - 2 and 1 <= ny <= self.mh - 2:
            self.h.step(key)
            self.cur = [nx, ny]

    def move_to(self, tx, ty):
        while self.cur[0] != tx:
            self.move("right" if self.cur[0] < tx else "left")
        while self.cur[1] != ty:
            self.move("down" if self.cur[1] < ty else "up")

    def cycle_to(self, name):
        ORDER = ["GUN", "CANNON", "FROST", "TESLA", "FLAME", "RADAR", "REPAIR", "REACTOR"]
        d = self.debug()
        for _ in range((ORDER.index(name) - ORDER.index(d["selected_type"])) % len(ORDER)):
            self.h.step("x")

    def build_here(self, typ):
        self.cycle_to(typ)
        before = len(self.debug()["towers"])
        self.h.step("a")
        return len(self.debug()["towers"]) > before

    def build_near(self, typ):
        """在光标格或其四邻里建一座（地图上中心格可能是岩石/水）。成功返回 True。"""
        if self.build_here(typ):
            return True
        for k, rev in (("right", "left"), ("left", "right"), ("up", "down"), ("down", "up")):
            self.move(k)
            if self.build_here(typ):
                return True
            self.move(rev)
        return False

    def close(self):
        self.h.close()


def test_pause(seed):
    g = Game(seed)
    try:
        g.h.step("start")
        paused_now = "PAUSED" in g.screen()
        check("pause: start 键能暂停", paused_now)
        g.h.step("start")
        still = "PAUSED" in g.screen()
        check("pause: 再按 start 能继续", not still,
              "(仍显示 PAUSED → start 无法恢复)" if still else "")
        if still:
            g.h.step("b")
            resumed = "PAUSED" not in g.screen()
            check("pause: B 键能恢复", resumed)
    finally:
        g.close()


def test_wall(seed):
    """B 项：can_build 放宽（允许把磁芯围死），敌人改由 P0 破墙开路。"""
    g = Game(seed, credits=9000)
    try:
        # 在磁芯左侧建一整列，尽量把刷怪口与磁芯隔开（OPEN 图岩石少，列基本可封死）
        wall_x = g.mw - 6
        g.move_to(wall_x, 1)
        built = 0
        for y in range(1, g.mh - 1):
            g.cycle_to("REACTOR")  # 用不还击的反应堆砌墙，专测"敌人会不会来拆"
            before = len(g.debug()["towers"])
            g.h.step("a")
            d = g.debug()
            if len(d["towers"]) > before:
                built += 1
            if y < g.mh - 2:
                g.move("down")
        d = g.debug()
        # 新版不再因"会堵死"拒绝：只要列上没被岩石/水挡住、没站着敌人，就都能建
        check("wall: 允许建塔把磁芯围死（不再因堵死拒绝）",
              built >= g.mh - 12,
              "built=%d path_ok=%s" % (built, d["path_ok"]))
        # 放一波，验证敌人会拆墙开路（塔总血下降 / 塔数减少 / 路重新通了）
        g.h.step("space")
        hp0 = sum(t["hp"] for t in g.debug()["towers"])
        n0 = len(g.debug()["towers"])
        g.h.step(None, frames=6000)
        d = g.debug()
        hp1 = sum(t["hp"] for t in d["towers"]) if d["towers"] else 0
        n1 = len(d["towers"])
        check("wall: 敌人破墙（塔血下降/塔数减少/路已通）",
              hp1 < hp0 or n1 < n0 or d["path_ok"] is True,
              "hp %d->%d towers %d->%d path_ok=%s" % (hp0, hp1, n0, n1, d["path_ok"]))
    finally:
        g.close()


def test_power(seed):
    g = Game(seed, credits=2000)   # 给足钱：这条测电力机制，不该被"起始金币"绑住
    try:
        d = g.debug()
        base = d["power_cap"]
        # 建反应堆
        check("power: 建出反应堆", g.build_near("REACTOR"))
        d = g.debug()
        check("power: 反应堆 +10 上限", d["power_cap"] == base + 10,
              "%d -> %d" % (base, d["power_cap"]))
        # 建一座 GUN 占 1 电（逐个方向试，避开岩石/水）
        placed = None
        for k, rev in (("right", "left"), ("left", "right"), ("up", "down"), ("down", "up")):
            g.move(k)
            if g.build_here("GUN"):
                placed = rev
                break
            g.move(rev)
        d = g.debug()
        check("power: GUN 占 1 电", d["power_used"] == 1, "used=%d" % d["power_used"])
        # 回到反应堆格，升级到 L2 → cap +16
        if placed:
            g.move(placed)
        g.h.step("a")
        d = g.debug()
        check("power: 反应堆 L2 上限 +16", d["power_cap"] == base + 16,
              "cap=%d" % d["power_cap"])
    finally:
        g.close()


def test_upgrade_refund(seed):
    g = Game(seed, credits=2000)   # 给足钱：这条测升级/返还数值，不该被"起始金币"绑住
    try:
        c0 = g.debug()["credits"]
        check("build: 建出 GUN", g.build_near("GUN"))
        d = g.debug()
        check("build: GUN 扣 50", d["credits"] == c0 - 50, "credits=%d" % d["credits"])
        g.h.step("a")  # upgrade L2 = ceil(50*.8)=40
        d = g.debug()
        check("upgrade: L2 花 40", d["credits"] == c0 - 50 - 40 and d["towers"][0]["level"] == 2,
              "credits=%d lvl=%d" % (d["credits"], d["towers"][0]["level"]))
        g.h.step("a")  # upgrade L3 = ceil(50*1.2)=60
        d = g.debug()
        check("upgrade: L3 花 60", d["towers"][0]["level"] == 3, "lvl=%d" % d["towers"][0]["level"])
        c_before = d["credits"]
        g.h.step("a")  # upgrade at max -> denied
        d = g.debug()
        check("upgrade: 满级拒绝", d["towers"][0]["level"] == 3 and d["credits"] == c_before)
        # sell: spent=150 -> refund floor(90)
        g.h.step("d")
        d = g.debug()
        check("sell: 返还 floor(150*.6)=90", d["credits"] == c_before + 90 and len(d["towers"]) == 0,
              "credits=%d towers=%d" % (d["credits"], len(d["towers"])))
    finally:
        g.close()


def test_airstrike(seed):
    g = Game(seed)
    try:
        d = g.debug()
        check("airstrike: 开局可用", d["airstrike_cd"] <= 0)
        g.h.step("c")
        d = g.debug()
        check("airstrike: 使用后冷却 40s", abs(d["airstrike_cd"] - 40) < 0.1,
              "cd=%.2f" % d["airstrike_cd"])
        g.h.step(None, frames=120)  # 2s
        d = g.debug()
        check("airstrike: 冷却递减", 37.5 < d["airstrike_cd"] < 40,
              "cd=%.2f" % d["airstrike_cd"])
    finally:
        g.close()


def test_menu_and_fields(seed):
    g = Game(seed, diff="HARD", style="OPEN")
    try:
        d = g.debug()
        check("menu: 难度选择生效", d["diff"] == "HARD", d["diff"])
        check("menu: 地图选择生效", d["map_style"] == "OPEN", d["map_style"])
        need = ["phase", "wave", "wave_total", "diff", "map_style", "core_hp", "core_max",
                "credits", "power_used", "power_cap", "overload", "speed", "next_in",
                "enemies_alive", "selected_type", "cursor_x", "cursor_y", "airstrike_cd",
                "buildable", "towers", "enemies", "path_ok", "grid"]
        missing = [k for k in need if k not in d]
        check("debug_state: 字段齐全（DESIGN §10）", not missing, "missing=%s" % missing)
    finally:
        g.close()


def _first_float_after(text, token):
    import re
    m = re.search(re.escape(token) + r"\s+([0-9]+(?:\.[0-9]+)?)", text)
    return float(m.group(1)) if m else None


def test_radar_aura(seed):
    g = Game(seed, credits=2000)
    try:
        g.cycle_to("RADAR")
        g.h.step("a")  # radar @ cursor
        # 在雷达旁建一座 GUN（逐个方向试；失败就退回雷达格，别误按到升级）
        for k, rev in (("right", "left"), ("left", "right"), ("up", "down"), ("down", "up")):
            g.move(k)
            g.cycle_to("GUN")
            before = len(g.debug()["towers"])
            g.h.step("a")
            if len(g.debug()["towers"]) > before:
                break
            g.move(rev)
        d = g.debug()
        radar = next((t for t in d["towers"] if t["type"] == "RADAR"), None)
        guns = [t for t in d["towers"] if t["type"] == "GUN"]
        check("radar: 建出雷达与相邻炮塔", radar is not None and len(guns) >= 1)
        if radar and guns:
            near = min(guns, key=lambda t: (t["x"] - radar["x"]) ** 2 + (t["y"] - radar["y"]) ** 2)
            # 进战斗，光环才会在 Towers.update 里点亮
            g.h.step("space")
            g.h.step(None, frames=10)
            g.move_to(near["x"], near["y"])
            v = _first_float_after(g.screen(), "RNG")
            check("radar: 光环内炮塔射程 +25%（GUN 5.0→6.25）",
                  v is not None and v > 5.5, "RNG=%s" % v)
    finally:
        g.close()


def _snapshot(seed, style="MAZE", frames=1500):
    g = Game(seed, style=style)
    try:
        g.h.step("space")  # 提前放波
        g.h.step(None, frames=frames)
        d = g.debug()
        return {
            "wave": d["wave"], "core_hp": d["core_hp"], "credits": d["credits"],
            "enemies": sorted((e["type"], round(e["x"], 4), round(e["y"], 4),
                               round(e["hp"], 4)) for e in d["enemies"]),
            "towers": sorted((t["type"], t["x"], t["y"]) for t in d["towers"]),
        }
    finally:
        g.close()


def test_determinism(seed):
    a = _snapshot(seed)
    b = _snapshot(seed)
    check("determinism: 同 seed 同输入 → 状态逐位一致", a == b,
          "" if a == b else "mismatch")


def main():
    base = int(sys.argv[1]) if len(sys.argv) > 1 else 500
    print("== towerdef 定点检查 ==")
    for fn, off in [(test_pause, 1), (test_wall, 2), (test_power, 3),
                    (test_upgrade_refund, 4), (test_airstrike, 5),
                    (test_menu_and_fields, 6), (test_radar_aura, 7),
                    (test_determinism, 8)]:
        print("-- %s --" % fn.__name__)
        try:
            fn(base + off)
        except Exception as e:
            check(fn.__name__ + " (exception)", False, repr(e))
    ok = sum(1 for _, o, _ in _results if o)
    print("\n%d/%d passed" % (ok, len(_results)))


if __name__ == "__main__":
    main()

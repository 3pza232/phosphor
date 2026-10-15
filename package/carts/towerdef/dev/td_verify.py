"""td_verify.py —— 逐条验收本次改动（键位/速度/侧栏数据/射程圈/升级射程）。

用控制通道真玩：读 debug_state 断言数据，读 screen.read 断言侧栏文案，
另存两张 PNG（光标在塔上 / 在空地）供肉眼比对射程圈。
"""
import json, os, socket, subprocess, sys, time

from _paths import run_root
DEV = os.path.dirname(os.path.abspath(__file__))
ROOT = run_root()
EXE = os.path.join(ROOT, "phosphor.exe")
CART = os.path.join(ROOT, "carts", "towerdef")
SHOTS = os.path.join(DEV, "shots")
SAVES = os.path.join(DEV, "saves", "verify")

PASS, FAIL = [], []


def check(name, ok, detail=""):
    (PASS if ok else FAIL).append(name)
    print(("  PASS " if ok else "  FAIL ") + name + ("  " + detail if detail else ""))


class Host:
    def __init__(self, port, seed):
        os.makedirs(SAVES, exist_ok=True)
        self.buf, self.pending, self.next_id, self.cur = b"", {}, 1, None
        args = [EXE, "--cart", CART, "--headless", "--control", str(port),
                "--seed", str(seed), "--frames", "9000000",
                "--save-dir", SAVES,
                "--config", os.path.join(DEV, "td_test_config.json")]
        self.proc = subprocess.Popen(args, cwd=ROOT,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.sock = None
        for _ in range(120):
            try:
                self.sock = socket.create_connection(("127.0.0.1", port), timeout=0.5)
                break
            except OSError:
                time.sleep(0.1)
        if not self.sock:
            raise RuntimeError("no control port")
        self.sock.settimeout(20.0)
        self.readline()
        self.cmd({"cmd": "time.step", "frames": 1})

    def readline(self):
        while b"\n" not in self.buf:
            c = self.sock.recv(65536)
            if not c:
                raise RuntimeError("closed")
            self.buf += c
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode("utf-8", "replace"))

    def send(self, o):
        o = dict(o); o["id"] = self.next_id; self.next_id += 1
        self.sock.sendall((json.dumps(o) + "\n").encode())
        return o["id"]

    def recv_id(self, w):
        if w in self.pending:
            return self.pending.pop(w)
        while True:
            m = self.readline()
            if m.get("id") == w:
                return m
            if m.get("id") is not None:
                self.pending[m["id"]] = m

    def cmd(self, o):
        return self.recv_id(self.send(o))

    def step(self, key=None, frames=1):
        ids = []
        if key:
            ids.append(self.send({"cmd": "input.inject", "key": key, "frames": 1}))
        ids.append(self.send({"cmd": "time.step", "frames": frames}))
        for i in ids[:-1]:
            self.recv_id(i)
        self.recv_id(ids[-1])
        return self.debug()

    def debug(self):
        return self.cmd({"cmd": "state.query"}).get("debug")

    def screen(self):
        r = self.cmd({"cmd": "screen.read"})
        return r.get("lines", [])

    def shot(self, name):
        os.makedirs(SHOTS, exist_ok=True)
        p = os.path.join(SHOTS, name)
        self.cmd({"cmd": "screenshot", "path": p})
        return p

    def set_credits(self, v):
        self.cmd({"cmd": "debug.set", "name": "Start credits", "value": v})

    def close(self):
        try:
            self.cmd({"cmd": "quit"})
        except Exception:
            pass
        try:
            self.sock.close()
        except Exception:
            pass
        try:
            self.proc.wait(timeout=5)
        except Exception:
            self.proc.kill()


def panel_lines(lines):
    # 侧栏文案在整屏文本右侧。这些 token（DMG/RNG/COST/SPEED…）只出现在侧栏，
    # 直接搜整屏即可，不必精确裁列（裁列易被左右侧壁的 | 干扰）。
    return "\n".join(lines)


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 777
    h = Host(9900 + (seed % 50), seed)
    try:
        h.set_credits(9000)  # 必须在开始前设：Game.new 时才读这个起始金币
        d = h.step("a")
        # 找一块能建的空地（从光标四邻试），建一座 GUN
        ORDER = ["GUN", "CANNON", "FROST", "TESLA", "FLAME", "LASER", "HELL", "SNIPER", "MORTAR", "RADAR", "REPAIR", "REACTOR"]

        def select(name):
            dd = h.debug()
            n = (ORDER.index(name) - ORDER.index(dd["selected_type"])) % len(ORDER)
            for _ in range(n):
                h.step("x")
            return h.debug()["selected_type"]

        check("Z/X 切塔型：X 下一个", select("CANNON") == "CANNON")
        check("Z/X 切塔型：Z 上一个", h.step("z")["selected_type"] == "GUN")
        check("Z/X 切塔型：X 循环回 GUN", select("GUN") == "GUN")

        select("GUN")
        placed = None
        for key, rev in (("right", "left"), ("left", "right"), ("up", "down"), ("down", "up")):
            before = len(h.debug()["towers"])
            h.step("a")
            if len(h.debug()["towers"]) > before:
                placed = True
                break
            h.step(rev)
        check("A 建造", placed is True)

        # ---- #3a 光标在已建塔上：侧栏显示塔数据 ----
        d = h.debug()
        tx, ty = d["towers"][0]["x"], d["towers"][0]["y"]
        select("FLAME")  # 故意选另一种塔，证明显示的是"塔的"而非"待建的"
        panel = panel_lines(h.screen())
        check("#3 塔上侧栏显示塔数据（DMG/RNG/KILLS）",
              "DMG" in panel and "RNG" in panel and "KILLS" in panel)

        # ---- #4 光标在塔上：射程圈 = 该塔射程（GUN L1=5.0），而非待建 FLAME(3.0) ----
        p_on = h.shot("ring_on_tower_GUN_L1.png")

        # ---- #5 升级提高射程，并同步侧栏 ----
        def rng_from_panel():
            for ln in panel_lines(h.screen()).splitlines():
                if "RNG" in ln:
                    tok = ln.split("RNG")[1].strip().split()
                    if tok:
                        try:
                            return float(tok[0])
                        except ValueError:
                            return None
            return None

        h.step("a")  # L2
        r2 = rng_from_panel()
        d = h.debug()
        lvl2 = d["towers"][0]["level"]
        h.step("a")  # L3
        r3 = rng_from_panel()
        # GUN 升级档案 up.range=1.0：L2=6.0、L3=7.0（新档位下射程增幅收窄，命中判定随之放宽）
        check("#5 升级射程明显变大 (5.0 -> +)", lvl2 == 2 and r2 and r2 >= 6.0,
              "L2 RNG=%s" % r2)
        check("#5 L3 射程更大", r3 and r3 >= 7.0, "L3 RNG=%s" % r3)

        # ---- #4b 移到空地：射程圈恢复成待建塔型（FLAME=3.0） ----
        h.step("right")  # 移开一格（空地）
        d = h.debug()
        check("#4 光标已移开塔", not any(t["x"] == d["cursor_x"] and t["y"] == d["cursor_y"]
                                        for t in d["towers"]))
        p_off = h.shot("ring_off_tower_FLAME_L1.png")

        # ---- #3b 空地：侧栏显示待建造塔型完整数据 ----
        panel = panel_lines(h.screen())
        check("#3 空地侧栏显示待建塔数据（COST/POWER/DMG/RNG/RATE）",
              all(k in panel for k in ("COST", "POWER", "DMG", "RNG", "RATE")))
        check("#3 空地显示当前待建塔型 FLAME", "FLAME" in panel)

        # ---- #1 空袭改 C ----
        d = h.debug()
        cd0 = d["airstrike_cd"]
        h.step("c")
        d = h.debug()
        check("#1 C = 空袭（冷却起跳 40s）", cd0 <= 0 and d["airstrike_cd"] > 39)

        # ---- #2 速度读数 + 循环 ----
        sp = h.step("period")["speed"]
        check("#2 . 升速到 2", sp == 2)
        sp = h.step("period")["speed"]
        check("#2 . 升速到 3", sp == 3)
        sp = h.step("period")["speed"]
        check("#2 . 在 3 处循环回 1（旧版会卡住）", sp == 1)
        panel = panel_lines(h.screen())
        check("#2 侧栏有速度读数 SPEED x1", "SPEED x1" in panel or "速度 x1" in panel, panel)

        # ---- #1 D = 拆除 ----
        # 先回到塔上再拆
        while h.debug()["cursor_x"] != tx:
            h.step("right" if h.debug()["cursor_x"] < tx else "left")
        while h.debug()["cursor_y"] != ty:
            h.step("down" if h.debug()["cursor_y"] < ty else "up")
        n_before = len(h.debug()["towers"])
        h.step("d")
        check("#1 D = 拆除", len(h.debug()["towers"]) == n_before - 1)

        print("\nscreenshots: %s  %s" % (p_on, p_off))
        print("\n%d passed, %d failed" % (len(PASS), len(FAIL)))
        if FAIL:
            print("FAILED: " + ", ".join(FAIL))
    finally:
        h.close()


if __name__ == "__main__":
    main()

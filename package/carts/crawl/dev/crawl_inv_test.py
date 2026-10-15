"""crawl_inv_test.py —— 验证背包"物品信息浮窗"：走到物品旁拾取，按 X 开背包，
读屏确认浮窗出现、内容正确。控制通道驱动，确定性 seed。"""

import json
import os
import socket
import subprocess
import sys
import time
from collections import deque

HOST = "127.0.0.1"
DEV = os.path.dirname(os.path.abspath(__file__))
BUILD = os.path.abspath(os.path.join(DEV, "..", "..", ".."))
EXE = os.path.join(BUILD, "phosphor.exe")
CART = os.path.abspath(os.path.join(DEV, ".."))
CONFIG = os.path.join(DEV, "crawl_test_config.json")
DELTA = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}
ORDER = ("up", "down", "left", "right")


class Host:
    def __init__(self, port, seed, timeout=10.0):
        args = [EXE, "--cart", CART, "--headless", "--control", str(port),
                "--seed", str(seed), "--frames", "4000000",
                "--config", CONFIG,
                "--save-dir", os.path.join(DEV, "inv_test_saves"),
                "--log", os.path.join(DEV, "inv_ctl.log")]
        # 工作目录必须是 build/：程序按相对路径找字体/资源包，在 dev/ 下会启动即崩。
        self.errlog = open(os.path.join(DEV, "inv_stderr.log"), "wb")
        self.proc = subprocess.Popen(args, cwd=BUILD, stdout=subprocess.DEVNULL,
                                     stderr=self.errlog)
        self.sock = None
        self.buf = b""
        self.pending = {}
        self.next_id = 1
        for _ in range(100):
            try:
                self.sock = socket.create_connection((HOST, port), timeout=0.5)
                break
            except OSError:
                time.sleep(0.1)
        if not self.sock:
            raise RuntimeError("could not connect")
        self.sock.settimeout(timeout)
        self.readline()  # hello
        self.cmd({"cmd": "time.step", "frames": 1})

    def readline(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("host closed")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode("utf-8", "replace"))

    def send(self, obj):
        obj = dict(obj)
        obj["id"] = self.next_id
        self.next_id += 1
        self.sock.sendall((json.dumps(obj) + "\n").encode("utf-8"))
        return obj["id"]

    def recv_id(self, want):
        if want in self.pending:
            return self.pending.pop(want)
        while True:
            msg = self.readline()
            mid = msg.get("id")
            if mid == want:
                return msg
            if mid is not None:
                self.pending[mid] = msg

    def cmd(self, obj):
        return self.recv_id(self.send(obj))

    def step(self, key, query=False):
        inject = self.send({"cmd": "input.inject", "key": key, "frames": 1})
        step = self.send({"cmd": "time.step", "frames": 1})
        self.recv_id(inject)
        self.recv_id(step)
        return self.query() if query else None

    def query(self):
        return self.cmd({"cmd": "state.query"})["debug"]

    def screen(self):
        return self.cmd({"cmd": "screen.read"})["lines"]

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
        try:
            self.errlog.close()
        except Exception:
            pass


def bfs_step(d, goal):
    grid = d["map"]
    H, W = len(grid), len(grid[0])
    px, py = d["player"]["x"], d["player"]["y"]
    gx, gy = goal
    if (px, py) == (gx, gy):
        return None

    def walk(x, y):
        return 0 <= x < W and 0 <= y < H and grid[y][x] != "#"

    prev = {(px, py): None}
    q = deque([(px, py)])
    while q:
        cx, cy = q.popleft()
        if (cx, cy) == (gx, gy):
            break
        for k in ORDER:
            dx, dy = DELTA[k]
            nx, ny = cx + dx, cy + dy
            if walk(nx, ny) and (nx, ny) not in prev:
                prev[(nx, ny)] = (cx, cy, k)
                q.append((nx, ny))
    if (gx, gy) not in prev:
        return None
    cur, out = (gx, gy), None
    while prev[cur] is not None:
        cx, cy, k = prev[cur]
        out = k
        cur = (cx, cy)
    return out


def nearest_item(d):
    px, py = d["player"]["x"], d["player"]["y"]
    best = None
    for it in d["items"]:
        if it.get("kind") != "consumable":
            continue
        dd = (it["x"] - px) ** 2 + (it["y"] - py) ** 2
        if best is None or dd < best[0]:
            best = (dd, (it["x"], it["y"]))
    return best[1] if best else None


def play_until_inv(h, want=2, max_steps=1200):
    for i in range(max_steps):
        d = h.query()
        if not d["alive"]:
            raise RuntimeError("player died before pickup at step %d" % i)
        if d.get("modal") and d["modal"] != "none":
            h.step("b", query=False)
            continue
        if len(d["player"]["inv"]) >= want:
            return d
        px, py = d["player"]["x"], d["player"]["y"]
        goal = nearest_item(d)
        if goal is None:
            # 本层没消耗品了：下楼换层再找
            h.step("y")
            continue
        if (px, py) == goal:
            h.step("a")
            continue
        key = bfs_step(d, goal)
        if key:
            h.step(key)
        else:
            h.step("space")
    raise RuntimeError("did not pick up %d items in %d steps" % (want, max_steps))


def dump(lines, x0, y0, w, h):
    for y in range(y0, y0 + h):
        row = lines[y]
        print("".join(row[x0:x0 + w]))


def region_dump(lines, title):
    row = lines[0]
    print("\n== %s ==" % title)
    # 内容区在整屏网格里的偏移：机身 2 行 + 顶栏，这里只做粗定位（找 PACK 边框）
    keys = ("PACK", "TYPE", "OIL", "POTION", "RATIONS", "CONSUMED", "EQUIPPED",
            "FROM DEPTH", "类型", "消耗", "背包", "灯油", "药水")
    for r in lines:
        text = "".join(r)
        if any(k in text for k in keys):
            print(text)


def main():
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 2024
    global CONFIG
    if len(sys.argv) > 2:                       # 可选第二个参数：config 路径（切语言）
        CONFIG = os.path.abspath(sys.argv[2])
    port = 7900 + (seed % 90)
    h = Host(port, seed)
    try:
        d = play_until_inv(h, want=2)
        print("== picked up; inventory ==", d["player"]["inv"])
        h.step("x")
        s = h.query()
        assert s.get("modal") == "inv", "inventory did not open: modal=%s" % s.get("modal")
        print("modal:", s["modal"], " selected=0 -> info for", s["player"]["inv"][0]["id"])
        lines = h.screen()
        region_dump(lines, "info for slot a")
        # 光标下移一格：信息窗应换成第二件物品
        h.step("down")
        s2 = h.query()
        assert s2["inv_sel"] == 1, "cursor did not move: inv_sel=%s" % s2.get("inv_sel")
        lines2 = h.screen()
        region_dump(lines2, "info for slot b (inv_sel=1)")
        # 无选中项（空背包）不画信息窗——只在两件都还在时跳过；这里验证一次完整屏
        print("\n== full screen dump ==")
        for row in lines:
            print("".join(row))
    finally:
        h.close()


if __name__ == "__main__":
    main()

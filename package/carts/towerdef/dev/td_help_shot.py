"""td_help_shot.py —— 截 K 键位表（zh / en 各一张），核对新键位与 key_name 渲染。"""
import json, os, socket, subprocess, time

DEV = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(DEV, "..", "..", ".."))
EXE = os.path.join(ROOT, "phosphor.exe")
CART = os.path.join(ROOT, "carts", "towerdef")
SHOTS = os.path.join(DEV, "shots")


class H:
    def __init__(self, port, cfg):
        self.buf, self.pending, self.nid = b"", {}, 1
        args = [EXE, "--cart", CART, "--headless", "--control", str(port),
                "--seed", "9", "--frames", "9000000",
                "--save-dir", os.path.join(DEV, "saves", "help"),
                "--config", cfg]
        self.p = subprocess.Popen(args, cwd=ROOT, stdout=subprocess.DEVNULL,
                                  stderr=subprocess.DEVNULL)
        self.s = None
        for _ in range(120):
            try:
                self.s = socket.create_connection(("127.0.0.1", port), timeout=0.5); break
            except OSError:
                time.sleep(0.1)
        self.s.settimeout(20)
        self.rl(); self.cmd({"cmd": "time.step", "frames": 1})

    def rl(self):
        while b"\n" not in self.buf:
            self.buf += self.s.recv(65536)
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode("utf-8", "replace"))

    def cmd(self, o):
        o = dict(o); o["id"] = self.nid; self.nid += 1
        self.s.sendall((json.dumps(o) + "\n").encode())
        while True:
            m = self.rl()
            if m.get("id") == o["id"]:
                return m

    def key(self, k):
        self.cmd({"cmd": "input.inject", "key": k, "frames": 1})
        self.cmd({"cmd": "time.step", "frames": 1})

    def close(self):
        try:
            self.cmd({"cmd": "quit"})
        except Exception:
            pass
        try:
            self.p.wait(timeout=5)
        except Exception:
            self.p.kill()


os.makedirs(SHOTS, exist_ok=True)
for tag, cfg in (("zh", os.path.join(ROOT, "config.json")),
                 ("en", os.path.join(DEV, "td_test_config.json"))):
    h = H(9940 + (0 if tag == "zh" else 1), cfg)
    try:
        h.key("a")  # 开始
        h.key("k")  # 打开键位表
        h.cmd({"cmd": "screenshot", "path": os.path.join(SHOTS, "help_%s.png" % tag)})
        if tag == "zh":
            print("\n".join(h.cmd({"cmd": "screen.read"}).get("lines", [])))
    finally:
        h.close()
print("done")

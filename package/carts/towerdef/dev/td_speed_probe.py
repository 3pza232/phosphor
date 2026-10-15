"""td_speed_probe.py —— 探针：, / . 到底有没有改变逻辑速度。

量两侧：debug 的 speed 字段（键有没有被读到）与固定帧数内 next_in 的推进量
（dt*speed 有没有真的生效）。同时验证循环（到顶后 . 应该回到 1，而不是无效）。
主机 cwd 必须是 build 根（字体/主题按运行目录找）。
"""
import json, os, socket, subprocess, sys, time

from _paths import run_root
DEV = os.path.dirname(os.path.abspath(__file__))
ROOT = run_root()
EXE = os.path.join(ROOT, "phosphor.exe")
CART = os.path.join(ROOT, "carts", "towerdef")
SAVES = os.path.join(DEV, "saves")


class Host:
    def __init__(self, port, seed, save_dir):
        self.buf = b""
        self.pending = {}
        self.next_id = 1
        args = [EXE, "--cart", CART, "--headless", "--control", str(port),
                "--seed", str(seed), "--frames", "9000000",
                "--save-dir", save_dir, "--config", os.path.join(ROOT, "config.json")]
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
            raise RuntimeError("could not connect to control port")
        self.sock.settimeout(20.0)
        self.readline()
        self.cmd({"cmd": "time.step", "frames": 1})

    def readline(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("host closed connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode("utf-8", "replace"))

    def send(self, obj):
        obj = dict(obj); obj["id"] = self.next_id; self.next_id += 1
        self.sock.sendall((json.dumps(obj) + "\n").encode("utf-8"))
        return obj["id"]

    def recv_id(self, want):
        if want in self.pending:
            return self.pending.pop(want)
        while True:
            msg = self.readline()
            if msg.get("id") == want:
                return msg
            if msg.get("id") is not None:
                self.pending[msg["id"]] = msg

    def cmd(self, obj):
        return self.recv_id(self.send(obj))

    def step(self, key=None, frames=1):
        ids = []
        if key:
            ids.append(self.send({"cmd": "input.inject", "key": key, "frames": 1}))
        ids.append(self.send({"cmd": "time.step", "frames": frames}))
        for i in ids[:-1]:
            self.recv_id(i)
        self.recv_id(ids[-1])
        return self.query().get("debug")

    def query(self):
        return self.cmd({"cmd": "state.query"})

    def debug(self):
        return self.query().get("debug")

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


def run(save_dir, seed, port):
    os.makedirs(save_dir, exist_ok=True)
    h = Host(port, seed, save_dir)
    try:
        d = h.step("a")
        print("start: phase=%s saved_speed=%s" % (d["phase"], d["speed"]))
        for k in ("period", "period", "period", "comma", "comma"):
            d = h.step(k)
            a = d["next_in"]
            d = h.step(None, frames=6)
            b = d["next_in"]
            print("  press %-6s -> speed=%d  6 frames next_in %.3f -> %.3f (d%.3f)"
                  % (k, d["speed"], a, b, a - b))
    finally:
        h.close()


if __name__ == "__main__":
    seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1234
    print("== 默认存档（可能残留 speed=3，就是旧版 . 失效的场景） ==")
    run(os.path.join(ROOT, "saves"), seed, 9531)
    print("== 干净存档（speed=1） ==")
    run(os.path.join(SAVES, "fresh"), seed, 9532)

"""td_play.py —— 通过控制通道真正"玩"一遍 towerdef，验证各系统在跑。

用法:
    python td_play.py [seed] [--frames N] [--cheat] [--diff EASY|NORMAL|HARD]
                      [--map OPEN|CANALS|MAZE|RANDOM] [--timeout S] [--quiet]

快:
  * 每步只发一趟网络：input.inject + time.step 一批写出，再按序读回应。
  * 不每步 state.query：本地推算光标，只在换相位/每 poll 帧查一次对齐。
  * 逻辑速度拉到 3x（period x2），同样帧数推进 3 倍游戏时间。
"""
import json, os, socket, subprocess, sys, time, math

HOST = "127.0.0.1"
# 脚本住在 build/carts/towerdef/dev，运行根（phosphor.exe / carts / config）在上溯三层。
# 子进程 cwd 必须是 build 根：字体与主题按运行目录找，不能是 dev。
WORK = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(WORK, "..", "..", ".."))
EXE = os.path.join(ROOT, "phosphor.exe")
CART = os.path.join(ROOT, "carts", "towerdef")
SAVES = os.path.join(WORK, "saves")


class Host:
    def __init__(self, port, seed, timeout=20.0):
        self.port = port
        args = [EXE, "--cart", CART, "--headless", "--control", str(port),
                "--seed", str(seed), "--frames", "9000000",
                "--save-dir", os.path.join(SAVES, str(seed)),
                "--log", os.path.join(SAVES, "ctl_%d.log" % seed),
                "--config", os.path.join(WORK, "td_test_config.json")]
        self.proc = subprocess.Popen(args, cwd=ROOT,
                                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.sock = None
        self.buf = b""
        self.pending = {}
        self.next_id = 1
        for _ in range(120):
            try:
                self.sock = socket.create_connection((HOST, port), timeout=0.5)
                break
            except OSError:
                time.sleep(0.1)
        if not self.sock:
            raise RuntimeError("could not connect to control port")
        self.sock.settimeout(timeout)
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

    def step(self, key=None, frames=1, query=False):
        ids = []
        if key:
            ids.append(self.send({"cmd": "input.inject", "key": key, "frames": 1}))
        ids.append(self.send({"cmd": "time.step", "frames": frames}))
        for i in ids[:-1]:
            self.recv_id(i)
        resp = self.recv_id(ids[-1])
        if not resp.get("ok", True):
            raise RuntimeError("time.step failed: %s" % resp.get("error"))
        if query:
            return self.query()
        return None

    def query(self):
        return self.cmd({"cmd": "state.query"})

    def debug(self):
        return self.query().get("debug")

    def set_param(self, name, value):
        return self.cmd({"cmd": "debug.set", "name": name, "value": value})

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


# ── 建造脚本规划：绕磁芯的环，内圈先建 ──
def build_plan():
    pts = {}
    for r in range(2, 15):
        for k in range(0, 48):
            a = k * math.pi / 24
            dx, dy = round(r * math.cos(a)), round(r * math.sin(a))
            if abs(dx) <= r and abs(dy) <= r and (dx or dy):
                pts.setdefault((dx, dy), abs(dx) + abs(dy))
    return [p for p, _ in sorted(pts.items(), key=lambda kv: kv[1])]


# 内圈用这几种轮换（含反应堆/雷达，覆盖全部 7 种塔）
TYPES_CYCLE = ["GUN", "CANNON", "TESLA", "RADAR", "CANNON", "GUN", "TESLA", "FROST",
               "CANNON", "TESLA", "GUN", "FLAME", "CANNON", "RADAR"]


class Bot:
    def __init__(self, h, seed, cheat=False, verbose=True):
        self.h = h
        self.seed = seed
        self.cheat = cheat
        self.verbose = verbose
        self.cur = [28, 22]
        self.frames = 0
        self.plan = build_plan()
        self.plan_i = 0
        self.type_i = 0
        self.stats = {
            "seed": seed, "games": [], "errors": [], "max_wave": 0,
            "builds": 0, "sells": 0, "upgrades": 0, "airstrikes": 0,
            "denied": 0, "kills": 0, "path_broken": 0, "neg_credits": 0,
            "won": False, "over": False, "frames": 0,
            "seen_enemies": set(), "seen_towers": set(), "waves_seen": set(),
        }

    # ── 低层 ──
    def _sync_cur(self, d):
        self.cur = [d["cursor_x"], d["cursor_y"]]

    def move(self, key):
        dx, dy = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}[key]
        nx, ny = self.cur[0] + dx, self.cur[1] + dy
        # main.lua 把光标 clamp 到 [1, MW-2] x [1, MH-2]
        if nx < 1 or nx > self.mw - 2 or ny < 1 or ny > self.mh - 2:
            return
        self.h.step(key)
        self.frames += 1
        self.cur = [nx, ny]

    def move_to(self, tx, ty):
        while self.cur[0] != tx:
            self.move("right" if self.cur[0] < tx else "left")
        while self.cur[1] != ty:
            self.move("down" if self.cur[1] < ty else "up")

    def press(self, key, frames=1):
        d = self.h.step(key, frames=frames, query=False)
        self.frames += frames
        return d

    # ── 菜单 ──
    def _saved(self, key, default):
        p = os.path.join(SAVES, str(self.seed), "towerdef.sav")
        if os.path.exists(p):
            with open(p, encoding="utf-8") as f:
                for line in f:
                    k, _, v = line.strip().partition("=")
                    if k == key and v:
                        return v
        return default

    def start_game(self, diff, style, endless=False):
        DIFFS = ["EASY", "NORMAL", "HARD"]
        MAPS = ["OPEN", "CANALS", "MAZE", "RANDOM"]
        d = self.h.debug()
        assert d["phase"] == "menu", d
        # 菜单会读存档里的上次选择：先按真实默认值算步数，别假设从 RANDOM/NORMAL 起
        i = DIFFS.index(self._saved("diff", "NORMAL"))
        for _ in range((DIFFS.index(diff) - i) % len(DIFFS)):
            self.press("right")
        self.press("down")  # -> MAP
        j = MAPS.index(self._saved("map", "RANDOM"))
        for _ in range((MAPS.index(style) - j) % len(MAPS)):
            self.press("right")
        self.press("down")  # -> ENDLESS
        if bool(self.h.debug().get("endless")) != bool(endless):
            self.press("right")
        self.press("a")
        d = self.h.debug()
        self.mw, self.mh = d["grid"]["w"], d["grid"]["h"]
        self._sync_cur(d)
        return d

    # ── 建造/升级 ──
    def select_type(self, name):
        # X 下一个塔型（Z 上一个）；按 Towers.ORDER 正向走
        ORDER = ["GUN", "CANNON", "FROST", "TESLA", "FLAME", "RADAR", "REPAIR", "REACTOR"]
        d = self.h.debug()
        cur = d["selected_type"]
        for _ in range((ORDER.index(name) - ORDER.index(cur)) % len(ORDER)):
            self.press("x")

    def next_spot(self):
        core = (self.mw - 3, self.mh // 2)
        while self.plan_i < len(self.plan):
            dx, dy = self.plan[self.plan_i]
            self.plan_i += 1
            tx, ty = core[0] + dx, core[1] + dy
            if 1 <= tx <= self.mw - 2 and 1 <= ty <= self.mh - 2:
                return (tx, ty)
        return None

    def try_build(self, typ):
        s = self.next_spot()
        if not s:
            return None
        self.move_to(*s)
        d = self.h.debug()
        self.select_type(typ)
        before = len(d["towers"])
        self.press("a")
        self.frames += 1
        d = self.h.debug()
        if len(d["towers"]) > before:
            self.stats["builds"] += 1
        else:
            self.stats["denied"] += 1
            if d["path_ok"] is False:
                self.stats["path_broken"] += 1
        return d

    def do_build_phase(self, d):
        # 1) 电力吃紧就先补反应堆（避免全场欠压）
        for _ in range(4):
            if d["power_used"] + 3 > d["power_cap"] and d["credits"] >= 60:
                nd = self.try_build("REACTOR")
                if nd is None:
                    break
                d = nd
            else:
                break
        # 2) 建攻击塔，直到预算/电力见底
        for _ in range(6):
            if d["credits"] < 130 or d["power_used"] >= d["power_cap"]:
                break
            typ = TYPES_CYCLE[self.type_i % len(TYPES_CYCLE)]
            self.type_i += 1
            nd = self.try_build(typ)
            if nd is None:
                break
            d = nd
        # 3) 升级已有塔（选最靠前的几座）
        for t in d["towers"][:4]:
            if d["credits"] < 120 or t["level"] >= 3:
                continue
            self.move_to(t["x"], t["y"])
            before = t["level"]
            self.press("a")
            self.frames += 1
            d = self.h.debug()
            nt = next((x for x in d["towers"] if x["x"] == t["x"] and x["y"] == t["y"]), None)
            if nt and nt["level"] > before:
                self.stats["upgrades"] += 1
        # 4) 偶尔拆一座（验证返还）
        if d["towers"] and d["credits"] < 80 and len(d["towers"]) > 3:
            t = d["towers"][-1]
            self.move_to(t["x"], t["y"])
            self.press("d")
            self.frames += 1
            self.stats["sells"] += 1
            d = self.h.debug()
        return d

    def do_combat(self, d):
        # 冷却好了就空袭（丢最靠前的敌人堆）
        if d["airstrike_cd"] <= 0 and d["enemies"]:
            e = min(d["enemies"], key=lambda x: x["dist"] if x["dist"] >= 0 else 1e9)
            self.move_to(max(1, min(self.mw - 2, int(e["x"]))),
                         max(1, min(self.mh - 2, int(e["y"]))))
            self.press("c")
            self.frames += 1
            self.stats["airstrikes"] += 1
            return self.h.debug()
        return d

    def run(self, diff, style, max_frames, poll=30, timeout=900.0, endless=False, stop_wave=None):
        started = time.time()
        deadline = started + timeout
        d = self.start_game(diff, style, endless)
        # 拉满速度 3x
        self.press("period")
        self.press("period")
        d = self.h.debug()
        self.stats["start"] = {k: d.get(k) for k in
                               ("phase", "diff", "map_style", "credits", "core_hp", "grid")}

        last_phase = None
        since_poll = 0
        while self.frames < max_frames:
            if time.time() > deadline:
                self.stats["errors"].append("timeout at frame %d" % self.frames)
                break
            if d["phase"] in ("won", "over"):
                break
            if d["path_ok"] is False:
                self.stats["path_broken"] += 1
            if d["credits"] < 0:
                self.stats["neg_credits"] += 1
            self.stats["max_wave"] = max(self.stats["max_wave"], d["wave"])
            for e in d["enemies"]:
                self.stats["seen_enemies"].add(e["type"])
            for t in d["towers"]:
                self.stats["seen_towers"].add(t["type"])
            self.stats["waves_seen"].add(d["wave"])
            if endless and d["wave"] >= 21 and "wave21" not in self.stats:
                self.stats["wave21"] = sorted(e["type"] for e in d["enemies"])
            if stop_wave is not None and d["wave"] >= stop_wave:
                break

            phase_changed = d["phase"] != last_phase
            last_phase = d["phase"]
            if phase_changed or since_poll >= poll:
                if d["phase"] == "build":
                    d = self.do_build_phase(d)
                    # 提前放波，加速
                    if d["phase"] == "build":
                        self.press("space")
                        self.frames += 1
                        d = self.h.debug()
                elif d["phase"] == "combat":
                    d = self.do_combat(d)
                since_poll = 0
                continue
            # 空转推进若干帧
            n = min(poll - since_poll, 60)
            self.h.step(None, frames=n)
            self.frames += n
            since_poll += n
            d = self.h.debug()

        self.stats["end"] = {k: d.get(k) for k in
                             ("phase", "wave", "credits", "core_hp", "power_used",
                              "power_cap", "overload", "enemies_alive")}
        self.stats["won"] = d["phase"] == "won"
        self.stats["over"] = d["phase"] == "over"
        self.stats["frames"] = self.frames
        self.stats["elapsed_s"] = round(time.time() - started, 1)
        # 收尾读 last_error
        q = self.h.query()
        if q.get("last_error"):
            self.stats["errors"].append(q["last_error"])
        return self.stats


def main():
    argv = sys.argv[1:]
    seed = int(argv[0]) if argv and not argv[0].startswith("--") else 42
    def opt(flag, default):
        if flag in argv:
            return argv[argv.index(flag) + 1]
        return default
    max_frames = int(opt("--frames", 200000))
    diff = opt("--diff", "NORMAL")
    style = opt("--map", "RANDOM")
    timeout = float(opt("--timeout", 900))
    cheat = "--cheat" in argv
    quiet = "--quiet" in argv
    endless = "--endless" in argv
    os.makedirs(os.path.join(SAVES, str(seed)), exist_ok=True)
    h = Host(7900 + (seed % 100), seed)
    try:
        if cheat:
            h.set_param("Start credits", 5000)
        bot = Bot(h, seed, cheat=cheat, verbose=not quiet)
        st = bot.run(diff, style, max_frames, timeout=timeout, endless=endless)
    finally:
        h.close()
    st["seed"] = seed
    for k in ("seen_enemies", "seen_towers", "waves_seen"):
        st[k] = sorted(st[k])
    print(json.dumps(st, indent=2, ensure_ascii=False))


if __name__ == "__main__":
    main()

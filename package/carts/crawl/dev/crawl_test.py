"""crawl_test.py —— 通过控制通道真正"玩"一遍 crawl，验证各系统在跑。

用法:
    python crawl_test.py [steps] [seed] [digest] [--poll N] [--timeout S]

为什么快:
  * 每步只发一趟网络：把 `input.inject` + `time.step`（+ 周期性 `state.query`）
    一次性写进 socket，再按序读回应，省掉原来的两次阻塞往返。
  * 不再每步全文 `state.query`：默认每 `--poll`(5) 步查一次，中间用本地移动模型
    推算玩家位置；遇到下楼/浮窗/死亡/通关等事件立刻强制查询对齐。
  * 有整局超时（默认 600s）与心跳输出，跑久也不会"看着像卡死"。

统计字段与旧版一致；`digest` 选项仍产出确定性摘要（同一构建 + 同 seed 应逐位一致）。
"""

import json
import socket
import subprocess
import sys
import time
import os
import hashlib
import random

HOST = "127.0.0.1"
WORK = os.path.dirname(os.path.abspath(__file__))
EXE = os.path.join(WORK, "phosphor.exe")
CART = os.path.join(WORK, "carts", "crawl")

DELTA = {"up": (0, -1), "down": (0, 1), "left": (-1, 0), "right": (1, 0)}
ORDER = ("up", "down", "left", "right")


class Host:
    def __init__(self, port, seed, tune=False, timeout=10.0):
        self.port = port
        args = [EXE, "--cart", CART, "--headless", "--control", str(port),
                "--seed", str(seed), "--frames", "4000000",
                "--save-dir", os.path.join(WORK, "crawl_test_saves"),
                "--log", os.path.join(WORK, "crawl_ctl.log")]
        if tune:
            # 英文界面让 phos.debug 参数名变成 ASCII，便于走 debug.set 调难度
            args += ["--config", os.path.join(WORK, "crawl_test_config.json")]
        self.proc = subprocess.Popen(
            args, cwd=WORK, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
        )
        self.sock = None
        self.buf = b""
        self.pending = {}          # id -> 已收到但尚未取用的回应（回应可能乱序）
        self.next_id = 1
        for _ in range(100):
            try:
                self.sock = socket.create_connection((HOST, port), timeout=0.5)
                break
            except OSError:
                time.sleep(0.1)
        if not self.sock:
            raise RuntimeError("could not connect to control port")
        self.sock.settimeout(timeout)
        self.readline()                                    # hello 握手（无 id）
        self.cmd({"cmd": "time.step", "frames": 1})        # 进入单步模式

    # ---- 低层收发 ----
    def readline(self):
        while b"\n" not in self.buf:
            chunk = self.sock.recv(65536)
            if not chunk:
                raise RuntimeError("host closed connection")
            self.buf += chunk
        line, self.buf = self.buf.split(b"\n", 1)
        return json.loads(line.decode("utf-8", "replace"))

    def send(self, obj):
        """只发不读；返回 id，稍后用 recv_id 对齐。"""
        obj = dict(obj)
        obj["id"] = self.next_id
        self.next_id += 1
        self.sock.sendall((json.dumps(obj) + "\n").encode("utf-8"))
        return obj["id"]

    def recv_id(self, want):
        """取指定 id 的回应。回应**可能乱序**到达（time.step 跟状态查询返回次序不定），
        所以把不匹配的先存起来，之后按 id 取用，绝不丢弃。"""
        if want in self.pending:
            return self.pending.pop(want)
        while True:
            msg = self.readline()
            mid = msg.get("id")
            if mid == want:
                return msg
            if mid is not None:
                self.pending[mid] = msg      # 先存，等对应请求来取
            # 无 id 的是主动事件，忽略

    def cmd(self, obj):
        return self.recv_id(self.send(obj))

    # ---- 组合动作 ----
    def step(self, key, query=False):
        """一趟写入完成 [注入按键 + 步进]；step 的回应要等主机跑完这一帧。

        注意：`state.query` 若和 `time.step` 同一批发出，会在步进**之前**被应答
        （拿到旧状态），必须等 step 的回应之后单独查，才是步进后的状态。"""
        inject = self.send({"cmd": "input.inject", "key": key, "frames": 1})
        step = self.send({"cmd": "time.step", "frames": 1})
        self.recv_id(inject)
        resp = self.recv_id(step)
        if not resp.get("ok", True):
            raise RuntimeError("time.step failed: %s" % resp.get("error"))
        if not query:
            return None
        return self.cmd({"cmd": "state.query"})["debug"]

    def query(self):
        return self.cmd({"cmd": "state.query"})["debug"]

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


def expected_radius(fuel):
    if fuel >= 67:
        return 9
    if fuel >= 34:
        return 7
    if fuel >= 10:
        return 5
    if fuel >= 1:
        return 3
    return 2


def adjacent_dir(d):
    px, py = d["player"]["x"], d["player"]["y"]
    best = None
    for m in d["monsters"]:
        dx, dy = m["x"] - px, m["y"] - py
        if abs(dx) <= 1 and abs(dy) <= 1 and not (dx == 0 and dy == 0):
            prio = abs(dx) + abs(dy)
            if best is None or prio < best[0]:
                key = None
                if dx == 0 and dy == -1:
                    key = "up"
                elif dx == 0 and dy == 1:
                    key = "down"
                elif dx == -1 and dy == 0:
                    key = "left"
                elif dx == 1 and dy == 0:
                    key = "right"
                if key:
                    best = (prio, key)
    return best[1] if best else None


def bfs_step(d, goal):
    """玩家（4 向）走一步靠近 goal；用 debug 暴露的地块网格做真寻路。"""
    grid = d["map"]
    H, W = len(grid), len(grid[0])
    px, py = d["player"]["x"], d["player"]["y"]
    gx, gy = goal
    if (px, py) == (gx, gy):
        return None

    def walk(x, y):
        return 0 <= x < W and 0 <= y < H and grid[y][x] != "#"

    from collections import deque
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
    cur = (gx, gy)
    step = None
    while prev[cur] is not None:
        cx, cy, k = prev[cur]
        step = k
        cur = (cx, cy)
    return step


def choose(d, rng):
    px, py = d["player"]["x"], d["player"]["y"]
    # 1) 相邻怪物：撞过去攻击（清路 / 升级）
    key = adjacent_dir(d)
    if key:
        return key
    # 2) 站在物品上：拾取
    for it in d["items"]:
        if it["x"] == px and it["y"] == py:
            return "a"
    # 3) 选目标：磷之心 > 楼梯（未到底）/ 守望者（最深）> 最近怪物
    goal = None
    for it in d["items"]:
        if it["id"] == "heart":
            goal = (it["x"], it["y"])
    if goal is None:
        if d["depth"] < 10:
            goal = (d["stairs"]["x"], d["stairs"]["y"])
            if (px, py) == goal:
                return "y"
        else:
            # 最深层：先杀守望者（它掉磷之心），没守望者了再取心 / 清怪
            warden = None
            best = None
            for m in d["monsters"]:
                if m["id"] == "warden":
                    warden = (m["x"], m["y"])
                    break
                dd = (m["x"] - px) ** 2 + (m["y"] - py) ** 2
                if best is None or dd < best[0]:
                    best = (dd, (m["x"], m["y"]))
            goal = warden or (best[1] if best else None)
    if goal:
        step = bfs_step(d, goal)
        if step:
            return step
    # 4) 兜底：随机走可走方向
    dirs = [k for k in ORDER if d["exits"].get(k)]
    return rng.choice(dirs) if dirs else "space"


# ---- 本地移动模型：两次真查询之间推算玩家位置 ----

def exits_from_grid(grid, px, py):
    def walk(x, y):
        return 0 <= y < len(grid) and 0 <= x < len(grid[y]) and grid[y][x] != "#"
    return {"up": walk(px, py - 1), "down": walk(px, py + 1),
            "left": walk(px - 1, py), "right": walk(px + 1, py)}


def predicted_view(d, pred, consumed):
    """用推算出的玩家位置，把最近一次真状态投影成"当前视图"。"""
    v = dict(d)
    pl = dict(d["player"])
    pl["x"], pl["y"] = pred
    v["player"] = pl
    v["items"] = [it for it in d["items"]
                  if (it["x"], it["y"], it["id"]) not in consumed]
    v["exits"] = exits_from_grid(d["map"], pred[0], pred[1])
    return v


def apply_move(d, pred, key):
    """按本地模型推算玩家走完 key 后的位置（不查主机）。"""
    if key not in DELTA:
        return pred
    dx, dy = DELTA[key]
    nx, ny = pred[0] + dx, pred[1] + dy
    if any(m["x"] == nx and m["y"] == ny for m in d["monsters"]):
        return pred                               # 撞怪 → 攻击，原地
    row = d["map"][ny] if 0 <= ny < len(d["map"]) else None
    if row is None or not (0 <= nx < len(row)) or row[nx] == "#":
        return pred                               # 撞墙 → 原地
    return [nx, ny]


def play(steps, seed, collect=False, poll=5, timeout=600.0, verbose=True):
    port = 7800 + (seed % 100)
    tune = bool(os.environ.get("CRAWL_TUNE"))
    os.makedirs(os.path.join(WORK, "crawl_test_saves"), exist_ok=True)
    h = Host(port, seed, tune)
    digest = hashlib.sha256()
    rng = random.Random(seed)
    poll = max(1, int(poll))
    stats = {"max_depth": 1, "kills_seen": 0, "max_turn": 0, "gold": 0, "max_steps": steps,
             "level": 1, "radius_ok": True, "errors": [], "won": False, "died": False}
    prev_monsters = None
    marks = set()
    MARKS = {
        "drain": ("怨灵吸走了你的光", "drains your light"),
        "split": ("分裂了", "splits"), "summon": ("守望者张开骨骸之门", "gate of bone"),
        "enrage": ("磷火暴燃", "phosphor flares"), "kill": ("倒下了", "falls"),
        "levelup": ("升级", "Level up"), "equip": ("换上了", "You equip"),
        "gold": ("金币", "gold"), "pickup": ("拾起", "pick up"),
        "descend": ("进入第", "descend to floor"), "lightout": ("灯灭了", "light dies"),
        "use_shock": ("冲击波", "shockwave"), "use_flame": ("烈焰吞没了", "Flames consume"),
        "use_blink": ("闪现到了别处", "blink elsewhere"), "use_map": ("布局尽收眼底", "reveals the floor"),
        "use_oil": ("倒空油瓶", "refill the lantern"), "use_potion": ("喝下药水", "drink the potion"),
        "use_ration": ("吃下干粮", "eat the rations"),
        "nostairs": ("没有楼梯", "no stairs"), "full": ("背包满了", "pack is full"),
        "better": ("已有的装备更好", "current gear is better"),
    }
    deadline = time.time() + timeout
    started = time.time()
    last_beat = started
    done = 0
    try:
        if tune:
            h.cmd({"cmd": "debug.set", "name": "Monster HP x", "value": 0.12})
            h.cmd({"cmd": "debug.set", "name": "Player ATK x", "value": 4.0})

        d = h.query()
        pred = [d["player"]["x"], d["player"]["y"]]
        consumed = set()
        force_poll = True

        i = 0
        while i < steps:
            if time.time() > deadline:
                stats["errors"].append(
                    "timeout after %.0fs at step %d/%d" % (timeout, i, steps))
                break

            if force_poll:
                if d is None:
                    d = h.query()
                pred = [d["player"]["x"], d["player"]["y"]]
                prev_monsters = None
                consumed.clear()
                force_poll = False

            _sample(d, stats, marks, MARKS, prev_monsters)
            prev_monsters = len(d["monsters"]) if d else None
            if collect:
                digest.update(json.dumps(_stable(d), sort_keys=True).encode())

            if d.get("modal") and d["modal"] != "none":
                d = h.step("b", query=True)
                pred = [d["player"]["x"], d["player"]["y"]]
                continue
            if not d["alive"]:
                stats["died"] = True
                d = h.step("a", query=True)
                pred = [d["player"]["x"], d["player"]["y"]]
                continue
            if d["won"]:
                stats["won"] = True
                break

            # 每 30 步开一次背包用一件（验证消耗品/浮窗/使用都跑得通）
            if i % 30 == 0 and d["player"]["inv"]:
                for k in ("x", "a", "b"):
                    h.step(k)
                d = h.query()
                pred = [d["player"]["x"], d["player"]["y"]]
                i += 1
                done += 1
                continue

            view = predicted_view(d, pred, consumed)
            key = choose(view, rng)
            # 最深层在追"最近的怪"（移动目标），推算位置会失准 —— 每步都查真状态。
            # 其余楼层：每 poll 步对齐一次；下楼必查（换层后地图全变）。
            do_query = (i % poll == 0) or (key == "y") or (d["depth"] >= 10)
            if key == "a":
                for it in d["items"]:
                    if it["x"] == pred[0] and it["y"] == pred[1]:
                        consumed.add((it["x"], it["y"], it["id"]))
            newd = h.step(key, query=do_query)
            if newd is not None:
                d = newd
                pred = [d["player"]["x"], d["player"]["y"]]
            else:
                pred = apply_move(d, pred, key)
            i += 1
            done += 1

            now = time.time()
            if verbose and now - last_beat >= 3.0:
                rate = done / max(0.001, now - started)
                print("  ... step %d/%d  depth %s  turn %s  %.1f steps/s"
                      % (i, steps, d.get("depth"), d.get("turn"), rate),
                      file=sys.stderr, flush=True)
                last_beat = now

        # 收尾：取一次最终真实状态，核对错误
        final = h.query()
        if final.get("last_error"):
            stats["errors"].append(final["last_error"])
        stats["marks"] = sorted(marks)
        stats["elapsed_s"] = round(time.time() - started, 2)
        stats["steps_run"] = done
        stats["steps_per_s"] = round(done / max(0.001, time.time() - started), 1)
        return stats, digest.hexdigest()
    finally:
        h.close()


def _stable(d):
    """摘要只涵盖本局确定性状态：剔除跨局持久的存档字段（runs/best_*）。"""
    if d is None:
        return None
    return {k: v for k, v in d.items()
            if k not in ("runs", "best_score", "best_depth")}


def _sample(d, stats, marks, MARKS, prev_monsters):
    if d is None:
        return
    stats["max_depth"] = max(stats["max_depth"], d["depth"])
    stats["max_turn"] = max(stats["max_turn"], d["turn"])
    stats["gold"] = max(stats["gold"], d["player"]["gold"])
    stats["level"] = max(stats["level"], d["player"]["level"])
    if d["player"]["light_radius"] != expected_radius(d["player"]["fuel"]):
        stats["radius_ok"] = False
    msg = d.get("last_msg", "")
    for name, subs in MARKS.items():
        if any(sub in msg for sub in subs):
            marks.add(name)
    ms = d["monsters"]
    if prev_monsters is not None and len(ms) < prev_monsters:
        stats["kills_seen"] += prev_monsters - len(ms)


if __name__ == "__main__":
    argv = sys.argv[1:]
    collect = "digest" in argv
    argv = [a for a in argv if a != "digest"]

    def take_opt(flag, default):
        if flag in argv:
            j = argv.index(flag)
            val = argv[j + 1]
            del argv[j:j + 2]
            return val
        return default

    timeout = float(take_opt("--timeout", 600))
    poll = int(take_opt("--poll", 8))

    steps = int(argv[0]) if len(argv) > 0 else 1500
    seed = int(argv[1]) if len(argv) > 1 else 42
    stats, dig = play(steps, seed, collect=collect, poll=poll, timeout=timeout)
    print(json.dumps(stats, indent=2, ensure_ascii=False))
    print("digest:", dig[:16], "steps:", stats["steps_run"], "seed:", seed,
          "steps/s:", stats["steps_per_s"])

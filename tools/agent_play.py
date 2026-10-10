#!/usr/bin/env python3
"""让 agent 开机器、从卡带架上挑一张卡带，然后操控它玩给你看。

与回归脚本的分工：`control_test.py` / `window_smoke.py` 验证**主机**的契约，
这里演示**通用玩法回路**——它不认识任何一张具体卡带：

    state.query 读卡带自报的 debug_state()  →  决定按哪个键  →  input.inject + time.step

开的是真窗口，所以你能看见 agent 的操作；标题里的 `[stepping]` 表示画面只在
`time.step` 时前进（单步模式让"注入 → 推进 → 观察"成为确定的回路）。
流速由 `--speed` 定：默认 1 = 实机流速（等的只是墙钟，推进仍走 `time.step`，
所以改流速不会改变发生过什么）；`--speed 0` 是"不等待"，几十倍速快放。

按键从哪来，按优先级挑第一个可用的：
  1. `--policy <文件.py>`：文件里定义 `choose(state) -> 键名或 None`，接你自己的策略
  2. 卡带自报的 `debug.next_key`：卡带愿意给"下一步按什么"就用它的
  3. `--keys a,b,space`：给定序列轮着按
  4. 都没有：在 `--key-pool` 里随便按（默认方向键与 a）——只能证明"机器在动"，
     不等于会玩

选哪张卡：`--shelf-cart <id>` 按名字挑（架上的顺序见 `state.query` 的 `shelf`），
`--shelf-down N` 只做相对移动，`--cart <路径>` 跳过卡带架直接进。

用法（在含 phosphor.exe 的构建目录里跑）::

    python ../tools/agent_play.py --shelf-cart bricks   # 开窗，挑 BRICKS 玩 40 步
    python ../tools/agent_play.py                       # 就玩架上当前选中的那张
    python ../tools/agent_play.py --cart carts/worms    # 跳过卡带架
    python ../tools/agent_play.py --speed 1                 # 实机流速（默认）
    python ../tools/agent_play.py --speed 0                 # 不等待，尽量快
    python ../tools/agent_play.py --seed 7 --keys right,a   # 固定种子：同一局可复跑
    python ../tools/agent_play.py --keys right,right,a --steps 60
    python ../tools/agent_play.py --policy ./my_policy.py

需要图形环境（会真的弹出一个窗口）。
"""

from __future__ import annotations

import argparse
import importlib.util
import os
import random
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from phos import Host, HostError  # noqa: E402

#: 没给策略时随便按的键池：方向键与面键——所有卡带至少认得这几颗
DEFAULT_POOL = ("left", "right", "up", "down", "a")

#: 插卡后等几帧：让卡带跑完 init 与第一帧的画面
INSERT_SETTLE_FRAMES = 4

#: 主机的逻辑帧率（kLogicStep = 1/60 秒）。画面走多快由它换算，不由渲染帧率决定
LOGIC_HZ = 60.0


def press(host, key: str, frames: int) -> None:
    """按一次键。走 `Host.key`（注入 + 精确推进）：单步模式下靠 sleep 等按键是没用的，
    帧不前进就不会产生输入边沿。"""
    host.key(key, frames=frames)


def pace(started: float, frames: int, speed: float) -> None:
    """把这一轮等到"这些帧在实机上该花的时间"，让画面按 `--speed` 走。

    只是等，不参与模拟：推进始终走 `time.step`，所以同一串按键在任何流速下
    结果都一样（`--speed` 只改变看得多快，不改变发生什么）。
    """
    if speed <= 0:      # 0 = 不等待：尽量快，跑回归/批处理用
        return
    budget = frames / (LOGIC_HZ * speed) - (time.perf_counter() - started)
    if budget > 0:
        time.sleep(budget)


def wait_for_shelf(host, limit: int = 400) -> None:
    """等开机动画走完。架子没出来之前谈不上"选游戏"，而 Enter 在这时是"跳过开机"。"""
    for _ in range(limit):
        if host.state().get("mode") == "SHELF":
            return
        host.step(10)
    raise SystemExit("等不到卡带架：机器一直没进到待机画面")


def insert_cart(host, shelf_down: int, frames: int) -> None:
    """在架上下移若干格后按 Enter 插卡。插完才知道插到的是哪一张。"""
    for _ in range(shelf_down):
        press(host, "down", frames)
    press(host, "start", frames)
    host.step(INSERT_SETTLE_FRAMES)


def shelf_index_of(host, wanted: str):
    """目标卡带在架上的下标；不在架上返回 None。

    认的是 `state.query` 的 `shelf`（玩家眼里的顺序：最近打开优先），
    不是 `carts.scan` 的磁盘目录顺序——两者不是一回事。
    """
    for index, cart_id in enumerate(host.state().get("shelf") or []):
        if cart_id == wanted:
            return index
    return None


def select_on_shelf(host, wanted: str, frames: int) -> None:
    """把架子光标走到 wanted 那一格并插卡。

    必须**先定位再插卡**：插一张卡就会把它记成"最近打开"，架子顺序随之改变，
    所以"插进去看是哪张、不对再换"这种试法会自己把顺序搅乱。
    """
    index = shelf_index_of(host, wanted)
    if index is None:
        raise SystemExit(f"架上没有 {wanted}（架上是: {host.state().get('shelf')}）")
    for _ in range(len(host.state().get("shelf") or []) + 2):
        if host.state().get("cursor") == index:
            break
        press(host, "right", frames)
    insert_cart(host, 0, frames)
    current = (host.state().get("cart") or {}).get("id", "")
    if current != wanted:
        raise SystemExit(f"插到了 {current}，不是 {wanted}（架上是: {host.state().get('shelf')}）")


def load_policy(path: str):
    """从 python 文件里取 choose(state) -> 键名。"""
    spec = importlib.util.spec_from_file_location("phos_agent_policy", path)
    if spec is None or spec.loader is None:
        raise SystemExit(f"读不了策略文件: {path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    choose = getattr(module, "choose", None)
    if not callable(choose):
        raise SystemExit(f"策略文件里要定义 choose(state) -> 键名或 None: {path}")
    return choose


def choose_key(state, policy, keys: list[str], index: int, pool):
    """挑这一轮要按的键；返回 (键名, 新的序列下标)。"""
    if policy is not None:
        return policy(state), index
    hint = (state.get("cart") or {}).get("debug")
    if isinstance(hint, dict) and isinstance(hint.get("next_key"), str):
        return hint["next_key"], index
    if keys:
        return keys[index % len(keys)], index + 1
    return random.choice(pool), index


def compact(value, limit: int = 96) -> str:
    """把卡带自报的状态压成一行，供人扫一眼。"""
    text = repr(value)
    return text if len(text) <= limit else text[: limit - 3] + "..."


def run(args) -> int:
    policy = load_policy(args.policy) if args.policy else None
    keys = [k.strip() for k in args.keys.split(",") if k.strip()] if args.keys else []
    pool = tuple(k.strip() for k in args.key_pool.split(",") if k.strip())

    extra = ["--save-dir", args.save_dir]
    if args.seed is not None:
        extra += ["--seed", str(args.seed)]
    with Host(cart=args.cart, headless=False, timeout=args.timeout, extra=extra) as host:
        if args.cart:
            print(f"  直接进卡带: {args.cart}")
            host.step(INSERT_SETTLE_FRAMES)
        else:
            wait_for_shelf(host)
            if args.shelf_cart:
                print(f"  在卡带架上挑 {args.shelf_cart}")
                select_on_shelf(host, args.shelf_cart, args.hold_frames)
            else:
                print(f"  在卡带架上下移 {args.shelf_down} 格后插卡")
                insert_cart(host, args.shelf_down, args.hold_frames)

        state = host.state()
        cart = state.get("cart") or {}
        if state.get("mode") != "PLAYING" or not cart.get("id"):
            print(f"  没进到游戏里（mode={state.get('mode')}）——卡片可能损坏或架子是空的")
            return 1
        start_frame = state.get("frame") or 0
        print(f"  正在玩的卡带: {cart.get('id')} [{cart.get('name')}]"
              f"   窗口: {state.get('video')}   单步: {state.get('stepping')}")

        index = 0
        for step in range(args.steps):
            started = time.perf_counter()
            key, index = choose_key(host.state(), policy, keys, index, pool)
            if key:
                press(host, key, args.hold_frames)   # 注入 + 精确推进，画面跟着走
            else:
                host.step(args.hold_frames)
            pace(started, args.hold_frames, args.speed)
            if (step + 1) % args.report_every == 0:
                current = host.state()
                debug = (current.get("cart") or {}).get("debug")
                print(f"  第 {step + 1:>3} 步  按 {str(key):<6} 帧={current.get('frame')}"
                      f"  卡带自报: {compact(debug)}")

        # 报**推进量**而不是帧号绝对值：主机在第一次 time.step 之前会按墙钟自己走几帧，
        # 那个偏移与本次操作无关，拿它做对照会假失败
        final = host.state()
        advanced = (final.get("frame") or 0) - start_frame
        print(f"  收工：帧 {final.get('frame')}（本次推进 {advanced} = {args.steps} 轮 × "
              f"{args.hold_frames} 帧），卡带 {compact((final.get('cart') or {}).get('debug'))}")
    print("  agent 的操作全程走控制通道（input.inject + time.step），键盘没有参与；"
          "同样的命令在 --headless 下也成立")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="通用 agent 玩家：开窗、选卡、按数据操控")
    parser.add_argument("--cart", help="跳过卡带架直接加载这张卡带（目录或 .phos）")
    parser.add_argument("--shelf-cart", help="按 id 在卡带架上挑这张卡带")
    parser.add_argument("--shelf-down", type=int, default=0,
                        help="插卡前在卡带架上往下走几格（默认 0 = 用当前选中的那张）")
    parser.add_argument("--steps", type=int, default=40, help="决策多少轮")
    parser.add_argument("--hold-frames", type=int, default=2,
                        help="每一轮推进几个逻辑帧。想跑高倍速就调大它：每轮要往返两三条命令，"
                             "命令本身就要几十毫秒，帧数太少时提速会被往返耗时卡住")
    parser.add_argument("--speed", type=float, default=1.0,
                        help="实机流速倍数：1 = 正常，4 = 四倍速，0 = 不等待（尽量快）")
    parser.add_argument("--keys", default="", help="逗号分隔的按键序列，轮着按")
    parser.add_argument("--key-pool", default=",".join(DEFAULT_POOL),
                        help="没有策略与序列时，从这里随便按")
    parser.add_argument("--policy", help="策略文件：定义 choose(state) -> 键名或 None")
    parser.add_argument("--report-every", type=int, default=10, help="每几步打印一次")
    parser.add_argument("--save-dir", default="saves/demo",
                        help="隔离的存档区（不碰你的进度）")
    parser.add_argument("--seed", type=int, help="固定随机种子：同一串按键每次跑出同一局")
    parser.add_argument("--timeout", type=float, default=25.0, help="单条命令的等待上限（秒）")
    args = parser.parse_args()
    try:
        return run(args)
    except HostError as err:
        print(f"  宿主没应答：{err}")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

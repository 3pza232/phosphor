#!/usr/bin/env python3
"""让人看见 agent 操作：**开真窗口**，agent 通过控制通道操控游戏。

与 `agent_play_snake.py` 的区别：那个跑 `--headless`（快、可自动化），
这个开窗口（慢、能被人看见）。两者用的是同一个控制通道——同一套指令
既能无人值守跑 CI，也能当着人的面操作。

窗口标题会写明"谁在操作"（由主机维护）：

    PHOSPHOR                              人自己在玩
    PHOSPHOR - agent :<port> [live]       agent 接管，实时推进
    PHOSPHOR - agent :<port> [stepping]   agent 接管，单步推进

用法（在含 phosphor.exe 的构建目录执行）::

    cd build
    python ../tools/agent_watch.py [--steps 30] [--save-dir saves/demo]
"""

from __future__ import annotations

import argparse
import shutil
import time
from pathlib import Path

from phos import Host, main_guard

DELTA = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}


def steer(host: Host) -> bool:
    """实时推进一帧的方向决策；返回是否还活着。"""
    debug = host.state()["debug"]
    if not debug["alive"]:
        host.key("start", frames=3)  # 死了就重开一局（和人类玩家一样的操作）
        time.sleep(0.4)
        return False

    # 贪心：朝食物走，且不允许 180 度掉头（会立刻撞死自己）
    direction = "right"
    if debug["food_x"] < debug["head_x"] and debug["dir_x"] != 1:
        direction = "left"
    elif debug["food_x"] > debug["head_x"] and debug["dir_x"] != -1:
        direction = "right"
    elif debug["food_y"] < debug["head_y"] and debug["dir_y"] != 1:
        direction = "up"
    elif debug["food_y"] > debug["head_y"] and debug["dir_y"] != -1:
        direction = "down"
    # 实时模式：只注入按键，不推进帧——画面由主机自己走（推进会把窗口冻住）
    host.inject_key(direction, frames=2)
    time.sleep(0.15)
    return True


def run(steps: int, save_dir: str) -> int:
    print("launching the windowed host (a window will open on your desktop)")
    # headless=False：这个脚本的全部意义就是让人看见窗口
    with Host(cart="carts/snake", extra=["--save-dir", save_dir], headless=False) as host:
        state = host.state()
        print()
        print("[1] the window is up - the human can see it")
        print(f"    video  : {state['video']}   control_port={state['control_port']}   "
              f"mode={state['mode']}")

        print()
        print("[2] agent steers the snake in REAL TIME - watch the window")
        print("    (it reads the cart's debug_state each tick and walks toward the food)")
        deaths = 0
        for _ in range(steps):
            if not steer(host):
                deaths += 1
        final = host.state()
        debug = final.get("debug", {})
        print(f"    after {steps} ticks: frame={final['frame']} "
              f"score={debug.get('score')} length={debug.get('length')} deaths={deaths}")

        print()
        print("[3] switch to frame stepping - the title says so, and the picture only")
        print("    advances when the agent asks for a frame")
        host.step(1)
        print(f"    state  : stepping={host.state().get('stepping')}")
        time.sleep(1.2)
        host.send("time.resume")
        print(f"    state  : stepping={host.state().get('stepping')}")

        print()
        print("[4] host key: pause the machine with an injected escape (same as pressing Esc)")
        host.key("escape", frames=1)
        time.sleep(1.5)
        print(f"    mode   : {host.state()['mode']}   (the pause menu is on screen)")
        host.key("escape", frames=1)
        time.sleep(1.2)
        print(f"    mode   : {host.state()['mode']}   (back to the game)")

        print()
        print("[5] done - closing the host and the window")

    print("    exited : True")
    print()
    print("everything you just saw in that window was driven by the control channel,")
    print("not by the keyboard - and the same commands work with --headless.")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--steps", type=int, default=30, help="实时操控多少个决策周期")
    parser.add_argument("--save-dir", default="saves/demo",
                        help="这一局的分数写到的隔离存档目录（不进玩家存档）")
    args = parser.parse_args()
    try:
        return run(args.steps, args.save_dir)
    finally:
        shutil.rmtree(Path(args.save_dir), ignore_errors=True)  # 给人看的这局不留档


if __name__ == "__main__":
    main_guard(main)

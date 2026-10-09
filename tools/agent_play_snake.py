#!/usr/bin/env python3
"""agent 上手示例：让脚本自己玩 SNAKE。

演示"agent 操控游戏"的完整闭环：

1. 起主机（无头 + 控制通道）
2. `state.query` 读玩法状态（卡带用 `debug_state()` 自报，不必解析画面）
3. `input.inject` 注入方向键
4. `time.step` 精确推进逻辑帧
5. 玩到结束，打印战绩与终局画面

换成别的卡带时：若它没提供 `debug_state()`，改用 `screen.read` 解析字符画面
（字符屏幕本身就是纯文本，agent 不需要视觉模型）。

用法（在含 phosphor.exe 的构建目录执行）::

    cd build
    python ../tools/agent_play_snake.py [--max-steps 300] [--save-dir saves/demo]
"""

from __future__ import annotations

import argparse
import shutil
from pathlib import Path

from phos import Host, main_guard

#: 蛇约每 5.4 帧移动一格，取 6 帧作为一次决策周期
STEP_INTERVAL = 6

DELTA = {"left": (-1, 0), "right": (1, 0), "up": (0, -1), "down": (0, 1)}
OPPOSITE = {"left": "right", "right": "left", "up": "down", "down": "up"}
FALLBACK = ("up", "down", "left", "right")


def direction_of(debug: dict) -> str:
    """卡带自报的方向向量 → 方向名（用来避免 180 度掉头）"""
    if debug["dir_x"] == 1:
        return "right"
    if debug["dir_x"] == -1:
        return "left"
    return "up" if debug["dir_y"] == -1 else "down"


def choose(debug: dict) -> str:
    """贪心选一步：先缩差距大的轴，且不允许掉头、不允许出界。

    找不到"更好"的方向就退回任意安全方向（活着比走得漂亮重要）。
    """
    toward_x = "right" if debug["food_x"] > debug["head_x"] else (
        "left" if debug["food_x"] < debug["head_x"] else None)
    toward_y = "down" if debug["food_y"] > debug["head_y"] else (
        "up" if debug["food_y"] < debug["head_y"] else None)
    prefer_x = abs(debug["food_x"] - debug["head_x"]) >= abs(debug["food_y"] - debug["head_y"])
    order = [toward_x, toward_y] if prefer_x else [toward_y, toward_x]
    order += [d for d in FALLBACK if d not in order]

    reverse = OPPOSITE[direction_of(debug)]
    for candidate in order:
        if candidate is None or candidate == reverse:
            continue
        dx, dy = DELTA[candidate]
        nx, ny = debug["head_x"] + dx, debug["head_y"] + dy
        if 0 <= nx < debug["arena_w"] and 0 <= ny < debug["arena_h"]:
            return candidate
    return "up"


def run(max_steps: int, save_dir: str) -> int:
    with Host(cart="carts/snake", extra=["--save-dir", save_dir]) as host:
        state = host.state()
        if not state.get("debug"):
            print("cart does not expose debug_state(); parse screen.read instead")
            return 1

        print(f"playing {state['cart']['name']} on {state['grid_w']}x{state['grid_h']} grid "
              f"(arena {state['debug']['arena_w']} x {state['debug']['arena_h']})")

        steps = 0
        best = 0
        while steps < max_steps:
            debug = host.state()["debug"]
            if not debug["alive"]:
                break
            if debug["score"] > best:
                best = debug["score"]
                print(f"  step {steps} : score {best} (length {debug['length']})")
            # 决策周期就是 STEP_INTERVAL 帧：按键本身不该额外多吃一帧
            host.inject_key(choose(debug))
            host.step(STEP_INTERVAL)
            steps += 1

        final = host.state()["debug"]
        print()
        print(f"result : steps={steps} alive={final['alive']} score={final['score']} "
              f"length={final['length']}")
        print("final frame:")
        print(host.screen_text())

    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--max-steps", type=int, default=300, help="最多决策多少次")
    parser.add_argument("--save-dir", default="saves/demo",
                        help="这次战绩写到的隔离存档目录（不进玩家存档）")
    args = parser.parse_args()
    try:
        return run(args.max_steps, args.save_dir)
    finally:
        # 演示玩出来的分数不该留在玩家存档里
        shutil.rmtree(Path(args.save_dir), ignore_errors=True)


if __name__ == "__main__":
    main_guard(main)

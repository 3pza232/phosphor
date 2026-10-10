#!/usr/bin/env python3
"""PHOSPHOR 窗口（GL）路径冒烟：真的开窗跑一段时钟，注入几个键，断言进程活着、通道还在应答、
退出干净。

无头回归覆盖的是文本导出与 CPU 光栅化；GL 渲染、窗口消息循环、帧率节流、`time.step`
的推进只在开窗时才走。内存越界这类故障往往**只在这条路径上出现**，而且常在过一会儿之后
才由分配器发现，所以这里做的是"最短但真的开窗"的检查：它不能替代逐像素对照，
而是补上那条没人走的路径。

需要图形环境（会真的弹出一个窗口）。驱动一律用**显式按下/松开**（`down:true` / `down:false`）：
它不依赖主机的按帧释放，实时与单步模式下行为一致；一次点按要跨过一个逻辑帧，
否则主机的按键采样看不见它。

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/window_smoke.py
    python ../tools/window_smoke.py --seconds 30 --cart carts/worms
"""

from __future__ import annotations

import argparse
import time

from phos import Host, HostError, main_guard, reporter

#: 开局后注入的按键：走路、跳跃、开合地图与键位表——都是要真正重绘的分支。
DRIVE_KEYS = ("right", "right", "b", "m", "m", "k", "k")

#: 一次"点按"里按住时长（秒）。实时模式下按键按下/松开之间要跨过一个逻辑帧，
#: 否则主机的按键采样会看不见它
TAP_SECONDS = 0.06


def tap(host, key: str) -> None:
    # 实时模式**不用 `frames`**：那是"按住 N 个逻辑帧后自动释放"，只在单步模式下才回包。
    # 显式按下 + 松开在两种模式下都成立
    host.send("input.inject", key=key, down=True)
    time.sleep(TAP_SECONDS)
    host.send("input.inject", key=key, down=False)


def tail_of(path: str, lines: int = 12) -> str:
    try:
        with open(path, "rb") as handle:
            text = handle.read().decode("utf-8", "replace").splitlines()
    except OSError:
        return ""
    return "\n".join(text[-lines:])


def run(seconds: float, cart: str) -> int:
    report, _ = reporter("window smoke")
    host = Host(cart=cart, headless=False, timeout=20.0)
    failure = None
    with host:
        report.check(host.state().get("video") != "headless", "宿主以窗口模式启动")

        phase = "起步"
        try:
            # 菜单 → 开局：往下走到底再确认，之后走真实时钟（不是 time.step）
            phase = "菜单按键"
            for _ in range(6):
                tap(host, "down")
            tap(host, "a")

            phase = "真实时钟运行"
            deadline = time.time() + seconds
            while time.time() < deadline:
                time.sleep(1.0)
                host.state()  # 每秒问一次：通道断了会在这里抛

            phase = "对局按键"
            for key in DRIVE_KEYS:
                tap(host, key)

            phase = "单步同步"
            host.step(5)
            first = host.state().get("frame", 0)
            second = host.step(7)
            report.check(second.get("frame", 0) - first == 7,
                         "time.step 在窗口模式下精确：请求 7 帧就推进 7 帧")
            host.send("time.resume")
        except HostError as err:
            failure = err

        report.check(failure is None,
                     f"窗口模式连续运行 {seconds:.0f} 秒未中断（走到：{phase}）")

    report.check(host.exited_cleanly, "quit 之后进程自己退出（未崩溃、未被强杀）")
    if failure is not None:
        print(f"     中断原因: {failure}")
        print("     （若卡在注入按键：本文件 tap() 用的是显式按下/松开，别改成带 frames 的注入）")
    if failure is not None or not host.exited_cleanly:
        log = tail_of(host.log_path)
        if log:
            print("  宿主 stderr 末尾：")
            for line in log.splitlines():
                print(f"    {line}")
    return report.finish()


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 窗口路径冒烟")
    parser.add_argument("--seconds", type=float, default=12.0, help="开窗持续秒数（默认 12）")
    parser.add_argument("--cart", default="carts/worms", help="用哪张卡带做冒烟")
    args = parser.parse_args()
    return run(args.seconds, args.cart)


if __name__ == "__main__":
    main_guard(main)

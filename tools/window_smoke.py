#!/usr/bin/env python3
"""PHOSPHOR 窗口路径冒烟：真的开窗跑一遍"菜单→开局→按键→单步→实时浸泡→干净退出"。

它测的是**窗口那条路本身**，不是画面对不对：GL 渲染、窗口消息循环、帧率节流、`time.step`
的推进只在开窗时才走，内存越界这类故障常**只在这条路径上出现**。像素级断言在
`tools/gl_smoke.py`（用 `frame.read` 读回真实帧），两者分工明确。

**为什么快**：确定性的部分（菜单、按键、`time.step` 精度）一律走**单步**（`host.key` =
注入 + `time.step`），不睡墙钟；只有最后那一段**实时浸泡**要真的过时间（默认 3 秒）——
它是唯一需要实时的部分（验帧率节流与长时间不崩）。`--seconds` 调它。
不再像以前那样"原速把 WORMS 玩十几秒"。

需要图形环境（会真的弹出一个窗口）。用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/window_smoke.py                 # 默认浸泡 3 秒
    python ../tools/window_smoke.py --seconds 10    # 想压久一点
"""

from __future__ import annotations

import argparse
import time

from phos import Host, HostError, main_guard, reporter

#: 开局后注入的按键：走路、跳跃、开合地图与键位表——都是要真正重绘的分支。
DRIVE_KEYS = ("right", "right", "b", "m", "m", "k", "k")

#: 开始项的记号：光标停在那一行时，卡带会在行首画 ">"。**认记号，不认行号** ——
#: 数按键次数是脆的：卡带的菜单一增减（WORMS 多了"地图宽窄"一行就这么回事），
#: 写死的次数就会停在别的行上，对局永远不开，而门禁看不出来
START_MARKERS = ("开始游戏", "开始")

#: 确认键：WORMS 的菜单确认是 **回车**（虚拟键 "start"），不是 A——A 要留给昵称输入。
#: 菜单型的卡带按它开局；本来就没有菜单的卡带按下去也无害
CONFIRM_KEY = "start"


def start_focused(host: Host) -> bool:
    """光标是否停在"开始"那一项上。

    判据是**同一行里既有光标记号 `>` 又有开始字样**：机身边框与侧栏也在同一行里，
    要求 `>` 在行首会永远判假 —— 那就成了"按了半天没开局、测试还全绿"。
    """
    for line in host.screen_text().splitlines():
        if ">" in line and any(marker in line for marker in START_MARKERS):
            return True
    return False


def enter_match(host: Host) -> bool:
    """进入对局：菜单光标默认停在**第一项**，按一次"上"会**循环到最下面那一项**——
    WORMS 的设置界面里，最后一项就是"开始游戏"。不调任何参数（只是冒烟），
    直接"上 + 确认"即可开局；本来就没有菜单的卡带按下去也无害。

    走单步：`host.key` = 注入 + `time.step`，比"实时点按 + 睡墙钟"快得多，且确定。
    """
    host.key("up")
    host.key(CONFIRM_KEY)
    return start_focused(host)


def soak(host: Host, seconds: float) -> None:
    """实时浸泡：让主机自己按真实时钟跑一段，每秒问一次状态（通道断了会在这里抛）。"""
    deadline = time.time() + seconds
    while time.time() < deadline:
        time.sleep(1.0)
        host.state()


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
            # ① 确定性部分：全走单步（快且确定）
            phase = "菜单 → 开局"
            enter_match(host)

            phase = "对局按键"
            for key in DRIVE_KEYS:
                host.key(key)

            phase = "单步同步"
            host.step(5)
            first = host.state().get("frame", 0)
            second = host.step(7)
            report.check(second.get("frame", 0) - first == 7,
                         "time.step 在窗口模式下精确：请求 7 帧就推进 7 帧")

            # ② 唯一需要实时的部分：让主机自己按真实时钟跑一段
            phase = "实时浸泡"
            host.send("time.resume")
            soak(host, seconds)
        except HostError as err:
            failure = err

        report.check(failure is None,
                     f"窗口路径全程未中断（菜单/按键/单步/实时 {seconds:.0f}s；走到：{phase}）")

    report.check(host.exited_cleanly, "quit 之后进程自己退出（未崩溃、未被强杀）")
    if failure is not None:
        print(f"     中断原因: {failure}")
    if failure is not None or not host.exited_cleanly:
        log = tail_of(host.log_path)
        if log:
            print("  宿主 stderr 末尾：")
            for line in log.splitlines():
                print(f"    {line}")
    return report.finish()


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 窗口路径冒烟")
    parser.add_argument("--seconds", type=float, default=3.0, help="实时浸泡秒数（默认 3）")
    parser.add_argument("--cart", default="carts/worms", help="用哪张卡带做冒烟")
    args = parser.parse_args()
    return run(args.seconds, args.cart)


if __name__ == "__main__":
    main_guard(main)

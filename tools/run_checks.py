#!/usr/bin/env python3
"""PHOSPHOR 门禁一键跑：把 tools/ 下的测试脚本按集合跑一遍并汇总。

为什么单有一个入口：门禁散在多个脚本里，各跑一遍容易漏、也难一眼看全。这里只管
**调度与汇总**，测试逻辑仍在各自脚本里（一个脚本一个契约，单一职责）。

默认只跑**无头**门禁（任何机器都能跑）；开窗门禁（`gl_smoke` / `window_smoke`）
用 `--gui` 加进来（需要图形环境）。任一失败 → 非 0 退出码，可直接当 CI 门禁。

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/run_checks.py            # 无头门禁
    python ../tools/run_checks.py --gui      # 再加上开窗门禁
    python ../tools/run_checks.py --list     # 只列出门禁
"""

from __future__ import annotations

import argparse
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent

#: 无头门禁：不依赖图形环境
HEADLESS_GATES = [
    ("unit", "unit_smoke.py", "纯逻辑单元测试（C++；颜色/文本/配置/色板/主题；无 GL）"),
    ("control", "control_test.py", "控制通道契约（握手/单步/读屏/注入/热重载/退出）"),
    ("draw", "draw_smoke.py", "叠加/半格契约（CPU 像素；需要 Pillow）"),
    ("layer", "layer_smoke.py", "图层合成契约（含不建层的零开销）"),
    ("cart", "cart_smoke.py", "出厂卡带：跑得完 / 不报错 / 同种子可复现"),
    ("net", "net_smoke.py", "局域网联机契约（两进程 + 发现）"),
]
#: 开窗门禁：被测的就是窗口/GL 那条路，需要图形环境
GUI_GATES = [
    ("gl", "gl_smoke.py", "GL 渲染路像素契约（需要图形环境与 Pillow）"),
    ("window", "window_smoke.py", "窗口路径：菜单/按键/单步/实时浸泡/干净退出"),
]


def run_gate(script: str) -> int:
    start = time.time()
    proc = subprocess.run([sys.executable, str(HERE / script)], check=False)
    elapsed = time.time() - start
    status = "ok  " if proc.returncode == 0 else "FAIL"
    print(f"  [{status}] {script}  ({elapsed:.1f}s, exit {proc.returncode})\n")
    return proc.returncode


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 门禁一键跑")
    parser.add_argument("--gui", action="store_true", help="连开窗门禁一起跑（需要图形环境）")
    parser.add_argument("--list", action="store_true", help="只列出门禁，不运行")
    args = parser.parse_args()

    gates = list(HEADLESS_GATES) + (list(GUI_GATES) if args.gui else [])
    if args.list:
        for key, script, what in gates:
            print(f"  {key:8} {script:18} {what}")
        return 0

    print(f"PHOSPHOR 门禁：{len(gates)} 项（{'含' if args.gui else '不含'}开窗）\n")
    failures = []
    for key, script, what in gates:
        print(f"── {key}: {what} ──")
        if run_gate(script) != 0:
            failures.append(script)

    print()
    if failures:
        print(f"结果：{len(failures)} 项失败：{', '.join(failures)}")
        return 1
    print(f"结果：全部 {len(gates)} 项通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""PHOSPHOR 纯逻辑单元测试门禁：跑构建目录下的 `phosphor_tests`。

测试用例本体在 `tests/` 下（C++），与主机共享同一份**纯逻辑**源码（颜色/文本/配置/
色板/主题…），所以测的就是真代码；不依赖 GL / 显卡 / 窗口，任何机器都能跑。
本脚本只负责"找到可执行文件、跑它、把退出码翻译成门禁结论"。

需要先构建（`-DPHOSPHOR_BUILD_TESTS=ON` 时随主机构建一起产出）。用法
（工作目录必须是含 phosphor_tests 的构建目录）::

    cd build
    python ../tools/unit_smoke.py
"""

from __future__ import annotations

import subprocess
from pathlib import Path

from phos import main_guard, reporter

#: 找可执行文件：Windows 带 .exe，其它平台不带
CANDIDATES = ("phosphor_tests.exe", "phosphor_tests")


def find_binary() -> Path | None:
    for name in CANDIDATES:
        candidate = Path(name)
        if candidate.is_file():
            return candidate
    return None


def run() -> int:
    report, _ = reporter("PHOSPHOR unit")

    binary = find_binary()
    report.check(binary is not None, "phosphor_tests 已构建（-DPHOSPHOR_BUILD_TESTS=ON）")
    if binary is None:
        return report.finish()

    proc = subprocess.run([str(binary)], capture_output=True, text=True)
    for line in proc.stdout.splitlines():
        print(f"  {line}")
    for line in proc.stderr.splitlines():
        print(f"  {line}")
    report.check(proc.returncode == 0, "全部单元测试通过")
    return report.finish()


if __name__ == "__main__":
    main_guard(run)

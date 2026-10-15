#!/usr/bin/env python3
"""PHOSPHOR 纯逻辑单元测试门禁：跑构建目录下的 `phosphor_tests`。

测试用例本体在 `tests/` 下（C++），与主机共享同一份**纯逻辑**源码（颜色/文本/配置/
色板/主题…），所以测的就是真代码；不依赖 GL / 显卡 / 窗口，任何机器都能跑。
本脚本只负责"找到可执行文件、跑它、把退出码翻译成门禁结论"。

`phosphor_tests` 是**纯测试产物**：`clean.py` 会把它清掉以保持构建目录干净。
所以它不在时本脚本**按需重建**（增量链一下，很快），用后即清的目录照样能通过门禁。

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/unit_smoke.py
"""

from __future__ import annotations

import shutil
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


def build_binary() -> None:
    """按需构建测试目标（幂等、增量）。找不到 cmake 或构建失败就静默返回，由调用方报错。"""
    cmake = shutil.which("cmake")
    if cmake is None:
        return
    subprocess.run([cmake, "--build", ".", "--target", "phosphor_tests"],
                   capture_output=True, text=True)


def run() -> int:
    report, _ = reporter("PHOSPHOR unit")

    binary = find_binary()
    if binary is None:
        build_binary()  # 常留目录里可能没有它：自愈一次（目标存在才会成功）
        binary = find_binary()
    if binary is None:
        # 本构建没产出测试目标——多半是默认的 PHOSPHOR_BUILD_TESTS=OFF（build/ 当发行目录）。
        # 这不算失败：跳过并给出开启方法。
        print("  skip  本构建未产出 phosphor_tests（未启用 PHOSPHOR_BUILD_TESTS=ON）")
        print("        要跑纯逻辑单元门禁：cmake -DPHOSPHOR_BUILD_TESTS=ON . 后重跑本脚本")
        return 0
    report.check(True, "phosphor_tests 可用")

    proc = subprocess.run([str(binary)], capture_output=True, text=True)
    for line in proc.stdout.splitlines():
        print(f"  {line}")
    for line in proc.stderr.splitlines():
        print(f"  {line}")
    report.check(proc.returncode == 0, "全部单元测试通过")
    return report.finish()


if __name__ == "__main__":
    main_guard(run)

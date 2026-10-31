#!/usr/bin/env python3
"""绿色免安装：从"别的工作目录"启动也能找到内容根（carts/theme/devkit）。

发行形态是"双击 exe"：CWD 往往是桌面或快捷方式目录，而不是 exe 所在目录。
主机因此按"exe 目录"解析内容根（CWD 本身是内容根时保持不动，开发/工具用法不受影响），
`--root` 可显式覆盖。这个门禁用子进程在临时目录里启动构建产物来验证：

* 运行模式：--headless 能开机（不会因找不到 theme/ 崩，也不会报卡带错误）；
* DevKit：--check-api 能回退到 exe 目录找到 devkit/phos.lua；
* 断言不依赖网络/图形，结果可复现。

跑法（在含 phosphor.exe 的构建目录）：python ../tools/portable_smoke.py
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

EXE = Path("phosphor.exe")
SCRATCH = Path("tests-out") / "portable"


class Checks:
    def __init__(self) -> None:
        self.failures = 0

    def check(self, condition: object, what: str) -> None:
        if condition:
            print(f"  ok   {what}")
        else:
            self.failures += 1
            print(f"  FAIL {what}")

    def finish(self) -> int:
        print()
        if self.failures:
            print(f"portable smoke: {self.failures} check(s) failed")
        else:
            print("portable smoke: all checks passed")
        return 1 if self.failures else 0


def main() -> int:
    checks = Checks()
    if not EXE.is_file():
        print("portable smoke: phosphor.exe not found (run inside the build directory)")
        return 1
    exe = EXE.resolve()
    build = Path.cwd().resolve()
    shutil.rmtree(SCRATCH, ignore_errors=True)
    elsewhere = SCRATCH / "empty-cwd"
    elsewhere.mkdir(parents=True)
    config = (SCRATCH / "config.json").resolve()
    saves = (SCRATCH / "saves").resolve()
    try:
        print("  -- 运行模式（CWD 不是内容根）--")
        run = subprocess.run(
            [str(exe), "--headless", "--frames", "6", "--dump-screen",
             "--config", str(config), "--save-dir", str(saves)],
            cwd=str(elsewhere), capture_output=True, text=True, encoding="utf-8", check=False)
        checks.check(run.returncode == 0, f"从外部目录启动成功（exit {run.returncode}）")
        grid = [line for line in run.stdout.splitlines() if line.strip()]
        checks.check(len(grid) > 10, f"画面有内容（{len(grid)} 行）")
        checks.check("ERROR" not in run.stderr, "没有加载错误（内容根解析正确）")

        print("  -- DevKit（从外部目录找 devkit/）--")
        api = subprocess.run([str(exe), "--check-api"], cwd=str(elsewhere),
                             capture_output=True, text=True, encoding="utf-8", check=False)
        checks.check(api.returncode == 0, f"--check-api 回退到 exe 目录（exit {api.returncode}）")

        print("  -- --root 显式覆盖 --")
        forced = subprocess.run(
            [str(exe), "--headless", "--frames", "4", "--dump-screen", "--root", str(build),
             "--config", str(config), "--save-dir", str(saves)],
            cwd=str(elsewhere), capture_output=True, text=True, encoding="utf-8", check=False)
        checks.check(forced.returncode == 0, f"--root 指定内容根可用（exit {forced.returncode}）")
    finally:
        shutil.rmtree(SCRATCH, ignore_errors=True)
    return checks.finish()


if __name__ == "__main__":
    sys.exit(main())

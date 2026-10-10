#!/usr/bin/env python3
"""清理运行目录里的临时物。

只清"可再生的临时物"：日志、打包产物、截图、演示用的隔离存档区、
冒烟跑出来的临时画面（tests-out/）。

**绝不触碰**：config.json（你的机器设置）、saves/*.sav（你的存档）、
carts/ 下的卡带本体、构建产物（exe / 库 / CMake 文件）。

用法（在含 phosphor.exe 的构建目录执行）::

    cd build
    python ../tools/clean.py
"""

from __future__ import annotations

import shutil
from pathlib import Path

#: 直接删除的路径（文件或目录）
EPHEMERAL_PATHS = ["imgui.ini", "dist", "shots", "saves/demo", "tests-out"]


def main() -> int:
    root = Path.cwd()
    removed = 0

    def drop(path: Path, label: str) -> None:
        nonlocal removed
        if not path.exists():
            return
        print(f"  - {label}")
        shutil.rmtree(path) if path.is_dir() else path.unlink()
        removed += 1

    print("cleaning ephemeral files (saves and settings are left alone)")

    for log in root.glob("*.log"):
        drop(log, f"log: {log.name}")
    for relative in EPHEMERAL_PATHS:
        drop(root / relative, relative)

    print()
    print(f"removed {removed} item(s); your config.json and saves/*.sav were not touched")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

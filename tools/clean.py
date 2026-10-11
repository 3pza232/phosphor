#!/usr/bin/env python3
"""清理运行目录里的临时物。

只清"可再生的临时物"：日志、打包产物、截图、演示用的隔离存档区、
冒烟跑出来的临时画面（tests-out/），以及**下划线开头的临时探针**
（现场调试时随手写的 `_probe.py` / `_shot.png` 之类）。

约定：临时探针一律以 `_` 开头。这条是为了让清理有据可依 ——
不带前缀的脚本分不出"临时"还是"要留的工具"，迟早攒成一片垃圾。

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

#: 按通配符删除的名字（匹配文件名本身，含目录）
EPHEMERAL_GLOBS = ["*.log", "_*"]


def main() -> int:
    root = Path.cwd()
    removed = 0

    def drop(path: Path, label: str) -> None:
        nonlocal removed
        if not path.exists():
            return
        print(f"  删除 {label}")
        shutil.rmtree(path) if path.is_dir() else path.unlink()
        removed += 1

    print("清理临时物（存档与设置一概不动）")

    for pattern in EPHEMERAL_GLOBS:
        for path in root.glob(pattern):
            drop(path, path.name)
    for relative in EPHEMERAL_PATHS:
        drop(root / relative, relative)

    print()
    print(f"清掉 {removed} 项；config.json 与 saves/*.sav 没有被碰")
    print("（临时探针按「下划线开头」识别：随手写的脚本请叫 _probe.py）")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

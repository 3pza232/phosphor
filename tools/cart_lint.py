#!/usr/bin/env python3
"""卡带静态检查门禁：对出厂卡带与 devkit 示例跑 `phosphor --check-cart`。

它不运行卡带（无窗口、无副作用、结果可复现），检查的是"一定会出问题"的写法：
manifest/入口有效性、隐式全局、用 `screen.size()` 当可玩宽、阻塞的 discover、
require 指向不存在的模块、以及既没有 debug_state 也没有 phos.observe。

错误 → 非零退出；警告只报告（内容里的已知债务不阻塞门禁，但会打印出来跟踪）。

跑法（在含 phosphor.exe 的构建目录）：python ../tools/cart_lint.py
"""

from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

EXE = Path("./phosphor.exe")
ROOTS = (Path("carts"), Path("devkit/examples"))


def main() -> int:
    if not EXE.is_file():
        print("cart lint: phosphor.exe not found (run inside the build directory)")
        return 1

    carts = sorted(
        path for root in ROOTS if root.is_dir()
        for path in root.iterdir()
        if (path / "manifest.lua").is_file()
    )
    errors = 0
    warnings = 0
    for cart in carts:
        proc = subprocess.run([str(EXE), "--check-cart", str(cart), "--json"],
                              capture_output=True, text=True, encoding="utf-8", check=False)
        try:
            result = json.loads(proc.stdout)
        except json.JSONDecodeError:
            print(f"  FAIL {cart}: 无法解析 lint 输出（exit {proc.returncode}）")
            print(proc.stderr[-400:])
            errors += 1
            continue
        issues = result.get("issues") or []
        if issues:
            print(f"  {result.get('id') or cart.name}:")
            for issue in issues:
                where = issue.get("where") or "<cart>"
                if issue.get("line"):
                    where += f":{issue['line']}"
                print(f"    {issue.get('severity'):5} {where:30} {issue.get('message')}")
        errors += int(result.get("errors", 0))
        warnings += int(result.get("warnings", 0))

    print()
    if errors:
        print(f"cart lint: {errors} error(s), {warnings} warning(s)")
        return 1
    print(f"cart lint: {len(carts)} cart(s), 0 error(s), {warnings} warning(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

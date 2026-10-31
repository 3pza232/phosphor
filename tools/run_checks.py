#!/usr/bin/env python3
"""PHOSPHOR 门禁一键跑：把 tools/ 下的门禁按集合跑一遍并汇总。

为什么单有一个入口：门禁散在多个脚本里，各跑一遍容易漏、也难一眼看全。这里只管
**调度与汇总**，测试逻辑仍在各自脚本里（一个脚本一个契约，单一职责）。

默认只跑**无头**门禁（任何机器都能跑）；开窗门禁（`gl_smoke` / `window_smoke`）
用 `--gui` 加进来（需要图形环境）。任一失败 → 非 0 退出码，可直接当 CI 门禁。

`unit` 项要求构建目录里真有 `phosphor_tests`：构建没开 `PHOSPHOR_BUILD_TESTS` 就**判失败**，
不按"跳过即通过"处理——那会把真的测试红伪装成绿。

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
from functools import partial
from pathlib import Path

HERE = Path(__file__).resolve().parent

EXE_CANDIDATES = ("phosphor.exe", "phosphor")
UNIT_CANDIDATES = ("phosphor_tests.exe", "phosphor_tests")


def find_binary(candidates: tuple[str, ...]) -> Path | None:
    return next((Path(name) for name in candidates if Path(name).is_file()), None)


def run_command(command: list[str], label: str) -> int:
    start = time.time()
    proc = subprocess.run(command, check=False)
    elapsed = time.time() - start
    status = "ok  " if proc.returncode == 0 else "FAIL"
    print(f"  [{status}] {label}  ({elapsed:.1f}s, exit {proc.returncode})\n")
    return proc.returncode


def run_script(script: str) -> int:
    return run_command([sys.executable, str(HERE / script)], script)


def run_includes() -> int:
    """依赖铁律：include 方向（纯源码核查，不依赖构建目录）"""
    return run_command([sys.executable, str(HERE / "check_includes.py")], "check_includes.py")


def run_api() -> int:
    """API 注解与实现一致：主机自检，不开窗"""
    exe = find_binary(EXE_CANDIDATES)
    if exe is None:
        print("  FAIL 找不到 phosphor.exe——请在含主机构建产物的目录里跑")
        return 1
    return run_command([str(exe), "--check-api"], f"{exe.name} --check-api")


def run_unit() -> int:
    """纯逻辑单元测试；产物不存在即失败（跳过即通过会掩盖真实的测试红）"""
    code = run_script("unit_smoke.py")  # 内含"目标存在则增量重建"的自愈
    if find_binary(UNIT_CANDIDATES) is None:
        # unit_smoke 把"未启用测试目标"当跳过；门禁不认跳过——跳过正是测试红被掩盖的地方
        print("  FAIL 构建目录里没有 phosphor_tests：本构建未启用 PHOSPHOR_BUILD_TESTS")
        print("        修法：cmake -DPHOSPHOR_BUILD_TESTS=ON . 后重建（或 cmake --preset dev）")
        return 1
    return code


#: 无头门禁：(key, 说明, 跑法)
HEADLESS_GATES = [
    ("includes", "依赖铁律：include 方向（对照 docs/engine/architecture.md 第一节）", run_includes),
    ("api", "API 注解与实现一致（phosphor.exe --check-api）", run_api),
    ("unit", "纯逻辑单元测试（C++；颜色/文本/配置/色板/主题；无 GL）", run_unit),
    ("control", "控制通道契约（握手/单步/读屏/注入/热重载/退出）", partial(run_script, "control_test.py")),
    ("draw", "叠加/半格契约（CPU 像素；需要 Pillow）", partial(run_script, "draw_smoke.py")),
    ("layer", "图层合成契约（含不建层的零开销）", partial(run_script, "layer_smoke.py")),
    ("ui", "声明式界面契约（组件/焦点/事件/主题；卡带样板）", partial(run_script, "ui_smoke.py")),
    ("cart", "出厂卡带：跑得完 / 不报错 / 同种子可复现", partial(run_script, "cart_smoke.py")),
    ("net", "局域网联机契约（两进程 + 发现）", partial(run_script, "net_smoke.py")),
]
#: 开窗门禁：被测的就是窗口/GL 那条路，需要图形环境
GUI_GATES = [
    ("gl", "GL 渲染路像素契约（需要图形环境与 Pillow）", partial(run_script, "gl_smoke.py")),
    ("window", "窗口路径：菜单/按键/单步/实时浸泡/干净退出", partial(run_script, "window_smoke.py")),
]


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 门禁一键跑")
    parser.add_argument("--gui", action="store_true", help="连开窗门禁一起跑（需要图形环境）")
    parser.add_argument("--list", action="store_true", help="只列出门禁，不运行")
    args = parser.parse_args()

    gates = list(HEADLESS_GATES) + (list(GUI_GATES) if args.gui else [])
    if args.list:
        for key, what, _run in gates:
            print(f"  {key:8} {what}")
        return 0

    print(f"PHOSPHOR 门禁：{len(gates)} 项（{'含' if args.gui else '不含'}开窗）\n")
    failures = []
    for key, what, run in gates:
        print(f"── {key}: {what} ──")
        if run() != 0:
            failures.append(key)

    print()
    if failures:
        print(f"结果：{len(failures)} 项失败：{', '.join(failures)}")
        return 1
    print(f"结果：全部 {len(gates)} 项通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())
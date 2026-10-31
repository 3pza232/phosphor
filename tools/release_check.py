#!/usr/bin/env python3
"""发布前检查：把"能不能发"收敛成一条命令。

与 run_checks 的分工：run_checks 是**开发门禁**（每次提交都跑）；本脚本是**发布检查**：
额外要求工作树干净、版本/CHANGELOG 一致，并跑文本/像素基线与内容包校验。
任一硬检查失败 → 非 0 退出。性能预算只报告、不判失败。

用法（仓库根或 build/ 下均可）：
    python tools/release_check.py
    python tools/release_check.py --allow-dirty   # 只看内容，不要求 git 干净
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent


def run(command: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess:
    return subprocess.run(command, cwd=cwd, capture_output=True, text=True, encoding="utf-8",
                          errors="replace", check=False)


def find_build(explicit: str | None) -> Path:
    if explicit:
        return Path(explicit).resolve()
    for name in ("build", "build-release", "build-ci"):
        candidate = REPO / name
        if (candidate / "phosphor.exe").is_file():
            return candidate
    return REPO / "build"


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 发布前检查")
    parser.add_argument("--build", help="构建目录（默认自动找 build/）")
    parser.add_argument("--allow-dirty", action="store_true", help="允许工作树有未提交改动")
    args = parser.parse_args()

    build = find_build(args.build)
    exe = build / "phosphor.exe"
    tests = build / "phosphor_tests.exe"
    failures: list[str] = []
    report: list[tuple[str, bool, str]] = []

    def step(name: str, ok: bool, detail: str = "") -> None:
        report.append((name, ok, detail))
        if not ok:
            failures.append(name)

    step("构建产物存在", exe.is_file() and tests.is_file(), str(build))
    if not exe.is_file() or not tests.is_file():
        for name, ok, detail in report:
            print(f"  {'ok  ' if ok else 'FAIL'} {name}  {detail}")
        return 1

    version = run([str(exe), "--version"], cwd=build).stdout.strip()
    step("--version 可读", version.startswith("PHOSPHOR "), version)

    changelog = REPO / "CHANGELOG.md"
    step("CHANGELOG 存在且提到当前版本",
         changelog.is_file() and version.removeprefix("PHOSPHOR ").strip() in changelog.read_text(
             encoding="utf-8"), str(changelog))

    if not args.allow_dirty:
        status = run(["git", "status", "--porcelain"], cwd=REPO).stdout.strip()
        step("工作树干净（或 --allow-dirty）", status == "",
             status.splitlines()[0] if status else "clean")

    checks = [
        ("门禁 14 项", [sys.executable, str(HERE / "run_checks.py")]),
        ("API 一致性", [str(exe), "--check-api"]),
        ("内容包校验", [str(exe), "--check-packs", "--root", str(REPO / "package")]),
        ("文本基线", [sys.executable, str(HERE / "shell_golden.py")]),
        ("像素基线", [sys.executable, str(HERE / "pixel_golden.py")]),
    ]
    for name, command in checks:
        proc = run(command, cwd=build)
        tail = (proc.stdout.strip().splitlines() or [""])[-1]
        step(name, proc.returncode == 0, tail[-120:])

    perf = run([sys.executable, str(HERE / "perf_budget.py")], cwd=build)
    perf_ok = perf.returncode == 0
    perf_tail = (perf.stdout.strip().splitlines() or [""])[-1]
    report.append(("性能预算（仅报告）", perf_ok, perf_tail[-120:]))

    print("PHOSPHOR 发布检查\n")
    for name, ok, detail in report:
        print(f"  {'ok  ' if ok else 'FAIL'} {name:26} {detail}")
    print()
    if failures:
        print(f"结果：{len(failures)} 项失败：{', '.join(failures)}")
        return 1
    print("结果：可以发布（硬检查全过；性能/像素基线为报告项）")
    return 0


if __name__ == "__main__":
    sys.exit(main())

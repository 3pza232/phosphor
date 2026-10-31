#!/usr/bin/env python3
"""内容包校验门禁：--check-packs 的契约回归。

两件事必须一直成立：
1) 出厂内容根零 error（发布包自带的内容包是"长这样才对"的样本）；
2) 坏包要能被点名并以退出码 2 失败，而不是静默回退。

不把 JSON 字段结构钉死到每个 key（那会让工具演进变成门禁噪音），只断言关键字段与可解析性。
"""

from __future__ import annotations

import json
import shutil
import subprocess
import sys
from pathlib import Path

EXE = next((name for name in ("phosphor.exe", "phosphor") if Path(name).is_file()), None)
FAILED: list[str] = []


def check(name: str, ok: bool, detail: str = "") -> None:
    if ok:
        print(f"  ok   {name}" + (f"  {detail}" if detail else ""))
    else:
        print(f"  FAIL {name}" + (f"  {detail}" if detail else ""))
        FAILED.append(name)


def run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run([EXE, *args], capture_output=True, text=True, encoding="utf-8",
                          errors="replace", check=False)


def main() -> int:
    if EXE is None:
        print("check-packs smoke: 找不到 phosphor.exe——请在构建目录里跑")
        return 1

    factory = run(["--check-packs"])
    check("出厂内容根 0 error", factory.returncode == 0, f"exit={factory.returncode}")
    check("summary 行存在", "checked " in factory.stdout and "0 error" in factory.stdout,
          factory.stdout.strip().splitlines()[-1] if factory.stdout.strip() else "(empty)")

    as_json = run(["--check-packs", "--json"])
    parsed = None
    try:
        parsed = json.loads(as_json.stdout)
    except json.JSONDecodeError:
        pass
    check("--json 可解析", parsed is not None)
    if parsed is not None:
        check("json.ok 且无 error", parsed.get("ok") is True and parsed.get("errors") == 0,
              f"packs={parsed.get('packs')} errors={parsed.get('errors')}")

    scratch = Path("tests-out") / "check-packs-bad"
    shutil.rmtree(scratch, ignore_errors=True)
    try:
        (scratch / "theme" / "skin" / "broken").mkdir(parents=True)
        sound = scratch / "theme" / "sound" / "default"
        sound.mkdir(parents=True)
        (sound / "sounds.lua").write_text(
            'return { insert = { file = "hit.wav" } }\n', encoding="utf-8")
        bad = run(["--check-packs", "--root", str(scratch)])
        check("坏包退出码 2", bad.returncode == 2, f"exit={bad.returncode}")
        check("坏包被点名", "error" in bad.stdout and "skin.lua" in bad.stdout,
              (bad.stdout.strip().splitlines()[-1] if bad.stdout.strip() else "(empty)"))
    finally:
        shutil.rmtree(scratch, ignore_errors=True)

    if FAILED:
        print(f"\ncheck-packs smoke: {len(FAILED)} 项失败")
        return 1
    print("\ncheck-packs smoke: all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())

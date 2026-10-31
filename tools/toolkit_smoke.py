#!/usr/bin/env python3
"""卡带工具层契约：排行榜 / 共享词表 / 数值格式化。

被测卡带是 devkit/examples/toolkit（写进隔离的 --save-dir，不碰玩家存档）。
断言的是卡带能依赖的行为：
* phos.score：构造即装载、add 返回名次、TOP N 降序截断、clear、跨 cart.reload 持久化；
* phos.lang.shared()：当前语言那一列（中/英各一份词表，缺省随 config 语言）；
* phos.text.score/clock/percent：千分位、mm:ss、百分比的唯一实现。

跑法（在含 phosphor.exe 的构建目录）：python ../tools/toolkit_smoke.py
"""

from __future__ import annotations

import re
import shutil
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from phos import Host  # noqa: E402

SAVE_DIR = Path("tests-out") / "toolkit-saves"


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
            print(f"toolkit smoke: {self.failures} check(s) failed")
        else:
            print("toolkit smoke: all checks passed")
        return 1 if self.failures else 0


def main() -> int:
    checks = Checks()
    shutil.rmtree(SAVE_DIR, ignore_errors=True)  # 从空榜开始，结果可复现
    try:
        with Host(cart="devkit/examples/toolkit",
                  extra=("--seed", "1", "--save-dir", str(SAVE_DIR))) as host:
            host.step(10)
            debug = host.state().get("debug") or {}
            checks.check(debug.get("available") is True, "phos.score 在声明 save 的卡带里可用")
            checks.check(debug.get("best") == 0 and debug.get("list") in ([], {}),
                         f"初始榜为空（{debug.get('list')}）")
            checks.check(debug.get("shared_score") == "得分",
                         f"共享词表取当前语言（{debug.get('shared_score')}）")

            print("  -- 格式化 --")
            formatted = debug.get("formatted") or {}
            checks.check(re.fullmatch(r"\d{2}:\d{2}", str(formatted.get("clock"))) is not None,
                         f"phos.text.clock 输出 mm:ss（{formatted.get('clock')}）")
            checks.check(formatted.get("percent") == "45.7%",
                         f"phos.text.percent 输出百分比（{formatted.get('percent')}）")

            print("  -- 排行榜 --")
            host.key("a"); host.step(2)
            debug = host.state().get("debug") or {}
            checks.check(debug.get("best") == 1000, f"add 之后 best=1000（{debug.get('best')}）")
            checks.check(debug.get("formatted", {}).get("score") == "1,000",
                         f"phos.text.score 千分位（{debug.get('formatted', {}).get('score')}）")
            host.key("a"); host.step(2)
            host.key("a"); host.step(2)
            debug = host.state().get("debug") or {}
            checks.check(debug.get("list") == [3000, 2000, 1000],
                         f"TOP N 降序（{debug.get('list')}）")

            print("  -- 持久化 --")
            host.send("cart.reload")
            host.step(6)
            debug = host.state().get("debug") or {}
            checks.check(debug.get("points") == 0,
                         f"reload 重置玩法状态（points={debug.get('points')}）")
            checks.check(debug.get("best") == 3000 and debug.get("list") == [3000, 2000, 1000],
                         f"排行榜从存档恢复（{debug.get('list')}）")

            print("  -- 清空 --")
            host.key("b"); host.step(3)
            debug = host.state().get("debug") or {}
            checks.check(debug.get("best") == 0 and debug.get("list") in ([], {}),
                         "clear 清空并落盘")
    finally:
        shutil.rmtree(SAVE_DIR, ignore_errors=True)
    checks.check(host.exited_cleanly, "宿主干净退出")
    return checks.finish()


if __name__ == "__main__":
    sys.exit(main())
#!/usr/bin/env python3
"""场景栈契约：phos.scene 的压栈 / 冻结世界 / 音频暂停 / 出栈恢复。

被测卡带是 devkit 的样板（devkit/examples/scene）：它把场景语义写进 debug_state，
因此断言的是"卡带能依赖的契约"，不是像素：

* push 之后 depth/top/modal/pause_world/audio_pause 与 state.query.scenes 一致；
* pause_world 生效：卡带自己的 update 不再推进（ticks 停住）；
* 场景绘制压在世界之上（浮窗文字出现在画面里）；
* pop 执行 on_exit、ticks 恢复推进、state.query.scenes 清空；
* 同一张卡带可以再次压栈（栈状态干净）。

跑法（在含 phosphor.exe 的构建目录）：python ../tools/scene_smoke.py
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from phos import Host  # noqa: E402


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
            print(f"scene smoke: {self.failures} check(s) failed")
        else:
            print("scene smoke: all checks passed")
        return 1 if self.failures else 0


def main() -> int:
    checks = Checks()
    with Host(cart="devkit/examples/scene", extra=("--seed", "1")) as host:
        host.step(8)
        before = host.state().get("debug") or {}
        checks.check(before.get("depth") == 0, "初始栈为空")
        checks.check(int(before.get("ticks", 0)) > 0, "世界在推进（ticks 增长）")

        print("  -- 压栈 --")
        host.key("start")
        host.step(4)
        state = host.state()
        debug = state.get("debug") or {}
        checks.check(debug.get("depth") == 1, f"depth=1（{debug.get('depth')}）")
        checks.check(debug.get("top") == "pause", f"top=pause（{debug.get('top')}）")
        checks.check(debug.get("modal") is True, "modal 标记可见")
        checks.check(debug.get("pause_world") is True, "pause_world 标记可见")
        checks.check(debug.get("audio_pause") is True, "audio_pause 标记可见")
        checks.check(debug.get("entered") == 1, "on_enter 执行一次")
        scenes = state.get("scenes") or []
        checks.check(len(scenes) == 1 and scenes[0].get("id") == "pause",
                     f"state.query.scenes 报出场景（{scenes}）")
        text = host.screen_text()
        checks.check("PAUSED" in text and "RESUME" in text, "浮窗画在世界之上")

        print("  -- 冻结世界 --")
        frozen_ticks = debug.get("ticks")
        host.step(12)
        after = host.state().get("debug") or {}
        checks.check(after.get("ticks") == frozen_ticks,
                     f"pause_world 生效：ticks 停在 {frozen_ticks}（现 {after.get('ticks')}）")

        print("  -- 出栈恢复 --")
        host.key("a")
        host.step(5)
        state = host.state()
        debug = state.get("debug") or {}
        checks.check(debug.get("depth") == 0, f"depth 归零（{debug.get('depth')}）")
        checks.check(debug.get("exited") == 1, "on_exit 执行一次")
        checks.check((state.get("scenes") or []) == [], "state.query.scenes 清空")
        resumed = int(debug.get("ticks", 0))
        host.step(5)
        checks.check(int((host.state().get("debug") or {}).get("ticks", 0)) > resumed,
                     "世界恢复推进")
        checks.check("SCENE DEMO" in host.screen_text(), "回到世界画面")

        print("  -- 可再次压栈 --")
        host.key("start")
        host.step(3)
        debug = host.state().get("debug") or {}
        checks.check(debug.get("depth") == 1 and debug.get("entered") == 2,
                     "第二次压栈成功且 on_enter 再执行")

        print("  -- 退出 --")
    checks.check(host.exited_cleanly, "宿主干净退出")
    return checks.finish()


if __name__ == "__main__":
    sys.exit(main())

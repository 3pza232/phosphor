#!/usr/bin/env python3
"""PHOSPHOR 控制通道回归：握手、状态查询、单步确定性、读屏、输入注入、
热重载、卡带扫描、未知命令、退出。

跨平台、带超时、不依赖 BOM。
每段都**断言**而不是只打印：失败以非 0 退出码结束，可直接当门禁用。

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/control_test.py
"""

from __future__ import annotations

import sys

from phos import Host, HostError, main_guard, reporter

#: 卡带屏幕上的两处文案，按主机当前界面语言取。
#: 界面语言是用户可切的设置，把中文写进断言只会在中文机器上通过——那才是硬编码。
#: （读数行本身按项目政策保持 ASCII，是更稳的锚点；这两条同时验证 i18n 生效）
CART_WORDS = {
    "zh": ("得分", "贪吃蛇"),
    "en": ("SCORE", "SNAKE"),
}


def run() -> int:
    report, _ = reporter("control channel")

    with Host(cart="carts/snake") as host:
        state = host.state()
        report.check(state.get("ok") is True, "state.query answers ok")
        report.check(isinstance(state.get("frame"), int), "state.query reports a frame number")
        report.check(state.get("mode") == "PLAYING", "snake is running (mode=PLAYING)")
        report.check(state.get("video") == "headless", "headless run reports video=headless")
        report.check(state.get("cart", {}).get("id") == "snake", "cart metadata identifies snake")
        print(f"state   : frame={state.get('frame')} grid={state.get('grid_w')}x{state.get('grid_h')}")

        # 调试篮子（phos.debug.number）：snake 注册了可调参数，agent 可读可写。
        # 参数名**随界面语言变**（本机会按 config 的语言给），故用状态里报出的名字，不写死中文
        params = state.get("debug_params") or []
        report.check(len(params) >= 1, "state.query exposes the cart's debug params")
        if params:
            pname = params[0]["name"]
            set_reply = host.send("debug.set", name=pname, value=0.05)
            report.check(set_reply.get("ok") is True, "debug.set writes a cart param")
            after = host.state().get("debug_params") or []
            report.check(any(p["name"] == pname and abs(p.get("value", 0) - 0.05) < 1e-6
                             for p in after),
                         "debug.set took effect (read back 0.05)")

        # 单步的确定性：两次 time.step 的帧号差必须精确等于请求的帧数
        first = host.step(30).get("frame")
        second = host.step(10)
        report.check(second.get("frame", 0) - first == 10, "time.step is exact (30 then 10 -> delta 10)")
        report.check(second.get("stepping") is True, "stepping mode is on after time.step")
        print(f"step    : 30 frames -> {first}, then 10 frames -> {second.get('frame')}")

        own_ui, cart_title = CART_WORDS.get(state.get("language", "zh"), CART_WORDS["zh"])
        screen = host.screen_text()
        report.check(own_ui in screen, "screen.read contains the cart's own UI")
        report.check(cart_title in screen, "screen.read contains the cart title")

        report.check(host.key("right", frames=3).get("ok") is True, "input.inject is accepted")

        reload_reply = host.send("cart.reload")
        report.check(reload_reply.get("ok") is True, "cart.reload succeeds")
        report.check(reload_reply.get("host_time") == 0, "reload resets the cart's own clock")

        carts = host.carts()
        # 卡带显示名现在按界面语言本地化，故按 id 找、名字非空即可（不写死中文/英文）
        report.check(any(c.get("id") == "snake" and c.get("name") for c in carts),
                     "carts.scan lists the installed cart")

        report.check(host.send("bogus").get("ok") is False, "unknown command is rejected, not ignored")

        host.close()
        # quit 之后进程必须**自己**退干净；要动 kill 才死就是没收拾好
        report.check(host.exited, "quit makes the host exit")
        report.check(host.exited_cleanly, "exit was clean (no kill needed)")

        errors = host.stderr_text().strip()
        if errors:
            print("stderr  : " + " | ".join(errors.splitlines()))

    return report.finish()


if __name__ == "__main__":
    main_guard(run)

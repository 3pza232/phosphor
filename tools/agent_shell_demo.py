#!/usr/bin/env python3
"""系统操控演示：agent 只用控制通道把整台机器开一遍。

流程：开机 → 卡带架 → 设置（切滤镜、切字体方案并还原）→ 插卡 → 暂停 →
拔卡 → 关机 → 核对"不留痕"。覆盖：主机保留键（Esc/F2）、菜单光标、
单步确定性、屏幕读取、卡带生命周期、config.json 的字面还原。

三个做法都是为了不被工具本身坑住：
  * 动态端口 + 全程超时——固定端口会被上次留下的宿主占住，然后永久阻塞；
  * 断言文案按 `state.query.language` 选，界面切成英文也不会假失败；
  * 菜单按**光标**走到目标项，不数按键次数（菜单项一增减就会走错行）。

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/agent_shell_demo.py
"""

from __future__ import annotations

import os
import shutil
import sys

from phos import Host, main_guard

# 界面文案：断言跟着界面语言走（文案表在主机侧，这里只挑要核对的那几条）
TEXT = {
    "zh": {
        "settings_title": "设置",
        "shelf_hint": "[F2] 设置",
        "scanlines": "扫描线",
        "resume": "继续游戏",
        "eject": "拔出卡带",
    },
    "en": {
        "settings_title": "SETTINGS",
        "shelf_hint": "[F2] SETTINGS",
        "scanlines": "SCANLINES",
        "resume": "RESUME",
        "eject": "EJECT CART",
    },
}

CONFIG = "config.json"
FONT_SCHEME_DIR = os.path.join("theme", "font", "_demo")
LOG = "demo_stderr.log"


def cycle_next(names: list[str], current: str) -> str:
    return names[(names.index(current) + 1) % len(names)]


def run() -> int:
    failures = 0
    step = 0

    def section(title: str) -> None:
        nonlocal step
        step += 1
        print(f"\n[{step}] {title}")

    def check(condition: object, what: str) -> None:
        nonlocal failures
        if condition:
            print(f"      ok   {what}")
        else:
            print(f"      FAIL {what}")
            failures += 1

    with open(CONFIG, "rb") as handle:
        config_before = handle.read()

    # 造一套备用字体方案：只有一个方案时"切换"根本没发生，后面的断言会假通过
    os.makedirs(FONT_SCHEME_DIR, exist_ok=True)
    shutil.copyfile(os.path.join("theme", "font", "default", "font.ttf"),
                    os.path.join(FONT_SCHEME_DIR, "font.ttf"))

    try:
        with Host(log_path=LOG) as host:
            lang = host.state().get("language", "zh")
            words = TEXT.get(lang, TEXT["zh"])

            section("power on, fast-forward past the boot animation")
            host.step(220)
            state = host.state()
            check(state.get("mode") == "SHELF", f"boot finished, mode={state.get('mode')}")

            section("on the shelf: the scanned carts are listed")
            carts = host.carts()
            first = carts[0]
            check(len(carts) >= 1, f"{len(carts)} cart(s) scanned")
            screen = host.screen_text()
            check(first["name"] in screen, f"shelf screen lists {first['name']}")
            check(words["shelf_hint"] in screen, f"shelf hint shows the real key ({words['shelf_hint']})")
            check(state.get("cart") is None, "no cart inserted yet")

            section("open SETTINGS (host key F2)")
            host.key("settings", frames=3)
            state = host.state()
            check(state.get("mode") == "SETTINGS", f"mode={state.get('mode')}")
            check(words["scanlines"] in host.screen_text(), "settings screen shows the CRT row")

            section("navigate to the FILTER row and cycle it forward")
            filters = state["packs"]["filter"]
            original = state["filter"]
            target = cycle_next(filters, original)
            host.key("down")
            host.key("right")
            state = host.state()
            check(state.get("filter") == target, f"filter: {original} -> {state.get('filter')}")
            check(target in host.screen_text(), "screen shows the new filter name")

            section("restore the setting (cycle back)")
            host.key("left")
            state = host.state()
            check(state.get("filter") == original, f"filter restored to {state.get('filter')}")

            section("navigate to the FONT SCHEME row and cycle it forward")
            schemes = state["packs"]["font"]
            font_original = state["font"]
            font_target = cycle_next(schemes, font_original)
            # 反空转断言：只有一个方案、或"下一项"等于当前项时，切换没发生，
            # 后面的断言会全部假通过——必须在这里先失败
            check(len(schemes) >= 2, f"{len(schemes)} font scheme(s) available (at least 2 needed)")
            check(font_target != font_original,
                  f"target scheme differs from current: {font_original} -> {font_target}")
            host.key("down")   # FILTER -> FONT SCHEME
            host.key("right")
            state = host.state()
            check(state.get("font") == font_target, f"font scheme: {font_original} -> {state.get('font')}")
            check(font_target in host.screen_text(), "screen shows the new scheme name")

            section("restore the font scheme")
            host.key("left")
            state = host.state()
            check(state.get("font") == font_original, f"font scheme restored to {state.get('font')}")

            section("leave SETTINGS with the host key escape")
            host.key("escape")
            state = host.state()
            check(state.get("mode") == "SHELF", f"mode={state.get('mode')}")

            section("insert the cartridge from the shelf (Enter = confirm)")
            host.key("start", frames=4)
            state = host.state()
            check(state.get("mode") == "PLAYING", f"mode={state.get('mode')}")
            check(state.get("cart", {}).get("id") == first["id"],
                  f"cart={state.get('cart', {}).get('id')} [{state.get('cart', {}).get('name')}]")
            host.step(60)
            check(first["name"] in host.screen_text(), "cart UI is on screen")
            check(state.get("debug") is not None, "cart reports debug_state")

            section("pause it with escape")
            host.key("escape")
            state = host.state()
            check(state.get("mode") == "PAUSED", f"mode={state.get('mode')}")
            pause_screen = host.screen_text()
            check(words["resume"] in pause_screen or words["eject"] in pause_screen,
                  "pause menu is up")

            section("choose EJECT in the pause menu (walk the cursor to it)")
            # 菜单顺序由主机定义（继续游戏 / 磁带码 / 拔出卡带），这里按光标走
            eject_row = 2
            check(words["eject"] in pause_screen, "pause menu offers EJECT")
            check(host.walk_cursor(eject_row) == eject_row, f"cursor is on EJECT (row {eject_row})")
            host.key("start", frames=4)
            state = host.state()
            check(state.get("mode") == "SHELF", f"mode={state.get('mode')}")
            check(state.get("cart") is None, "cart ejected")

            section("power off (escape on the shelf)")
            host.send("input.inject", key="escape", frames=1)
            host.wait()
            check(host.exited, "host process gone")

            errors = host.stderr_text()
            check("WARN" not in errors and "ERROR" not in errors,
                  "shutdown was clean (no warnings logged)")

        section("settings were restored; config.json written back byte-for-byte")
        with open(CONFIG, "rb") as handle:
            check(handle.read() == config_before, "config.json restored to its original bytes")
    finally:
        # 不留痕：字体方案目录与日志都要清掉；config.json 无条件写回原字节
        shutil.rmtree(FONT_SCHEME_DIR, ignore_errors=True)
        if os.path.exists(LOG):
            os.remove(LOG)
        try:
            with open(CONFIG, "wb") as handle:
                handle.write(config_before)
        except OSError:
            pass

    print()
    if failures == 0:
        print("all steps passed")
        return 0
    print(f"{failures} step(s) FAILED")
    return 1


if __name__ == "__main__":
    main_guard(run)

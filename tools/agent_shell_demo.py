#!/usr/bin/env python3
"""系统操控演示：agent 只用控制通道把整台机器开一遍。

流程：开机 → 卡带架 → 设置（切主题、切字体方案并还原）→ 插卡 → 暂停 →
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
        "theme": "游戏机主题",
        "font": "字体方案",
        "resume": "继续游戏",
        "eject": "拔出卡带",
    },
    "en": {
        "settings_title": "SETTINGS",
        "shelf_hint": "[F2] SETTINGS",
        "scanlines": "SCANLINES",
        "theme": "CONSOLE THEME",
        "font": "FONT SCHEME",
        "resume": "RESUME",
        "eject": "EJECT CART",
    },
}

CONFIG = "config.json"
FONT_SCHEME_DIR = os.path.join("theme", "font", "_demo")
LOG = "demo_stderr.log"


def goto_row(host, label: str, limit: int = 14) -> bool:
    """把设置光标移到标题为 label 的那一行；返回是否找到。

    两个信号都不够用：标题**每一行都画**（等于一步也不走），而行首的 '>' 与值里的
    '< 候选 >' 分隔符同形，只找 '>' 会停在任意"有候选值"的行上。光标标记固定在
    **内容区第 6 列**，所以就只在这一小段里找；行序与起始行一概不假设——界面记着
    上次停在哪一行，行数还会随版本增加。
    """

    def focused(text: str) -> bool:
        return any(">" in line[6:11] and label in line for line in text.splitlines())

    for _ in range(limit):
        if focused(host.screen_text()):
            return True
        host.key("down")
    return focused(host.screen_text())


def cycle_next(names: list[str], current: str) -> str:
    """设置里"下一项"会被切到哪个名字。

    当前值可能不是内容包：内置的 NONE（不改配色）就没有对应文件夹，玩家的设置
    里却可以是它。这时从列表头开始，而不是把 list.index 抛出来。
    """
    if current not in names:
        return names[0]
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
            # 架子按"最近打开"排序，与 carts.scan 的扫描顺序不同：只断言扫到的卡有在架上的
            check(any(c["name"] in screen for c in carts), "shelf screen lists a scanned cart")
            check(words["shelf_hint"] in screen, f"shelf hint shows the real key ({words['shelf_hint']})")
            check(state.get("cart") is None, "no cart inserted yet")

            section("open SETTINGS (host key F2)")
            host.key("settings", frames=3)
            state = host.state()
            check(state.get("mode") == "SETTINGS", f"mode={state.get('mode')}")
            check(words["scanlines"] in host.screen_text(), "settings screen shows the CRT row")

            section("navigate to the THEME row and cycle it forward")
            # 认 **id**：state.skin 是 id，packs.skin 是屏幕上给人看的名字，
            # 同一个包这两个值不同名（名字还会随语言变）——拿名字比 id 会假失败
            theme_ids = state["packs"]["skin_ids"]
            theme_names = state["packs"]["skin"]
            original_theme = state["skin"]
            target_theme = cycle_next(theme_ids, original_theme)
            check(len(theme_ids) >= 2, f"{len(theme_ids)} theme(s) available (at least 2 needed)")
            check(target_theme != original_theme,
                  f"target theme differs from current: {original_theme} -> {target_theme}")
            check(goto_row(host, words["theme"]), "cursor reached the THEME row")
            host.key("right")
            state = host.state()
            check(state.get("skin") == target_theme, f"theme: {original_theme} -> {state.get('skin')}")
            check(theme_names[theme_ids.index(target_theme)] in host.screen_text(),
                  "screen shows the new theme name")

            section("restore the theme (cycle back)")
            host.key("left")
            state = host.state()
            check(state.get("skin") == original_theme, f"theme restored to {state.get('skin')}")

            section("navigate to the FONT SCHEME row and cycle it forward")
            schemes = state["packs"]["font"]
            font_original = state["font"]
            font_target = cycle_next(schemes, font_original)
            # 反空转断言：只有一个方案、或"下一项"等于当前项时，切换没发生，
            # 后面的断言会全部假通过——必须在这里先失败
            check(len(schemes) >= 2, f"{len(schemes)} font scheme(s) available (at least 2 needed)")
            check(font_target != font_original,
                  f"target scheme differs from current: {font_original} -> {font_target}")
            check(goto_row(host, words["font"]), "cursor reached the FONT SCHEME row")
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
            # 架上选中的是哪张由"最近打开"顺序决定，所以从状态里读，不预设是哪一张
            inserted = state.get("cart", {})
            check(state.get("mode") == "PLAYING", f"mode={state.get('mode')}")
            check(inserted.get("id") is not None,
                  f"cart={inserted.get('id')} [{inserted.get('name')}]")
            host.step(60)
            check(bool(inserted.get("name")) and inserted["name"] in host.screen_text(),
                  "cart UI is on screen")
            check(state.get("debug") is not None, "cart reports debug_state")

            section("pause it with escape")
            host.key("escape")
            state = host.state()
            check(state.get("mode") == "PAUSED", f"mode={state.get('mode')}")
            pause_screen = host.screen_text()
            check(words["resume"] in pause_screen or words["eject"] in pause_screen,
                  "pause menu is up")

            section("F2 must NOT open settings from the pause menu (shelf-only)")
            # 设置浮层只在卡带架唤起；从暂停菜单跳进去会让"关掉设置回哪去"变含糊
            host.key("settings", frames=3)
            state = host.state()
            check(state.get("mode") == "PAUSED",
                  f"settings key ignored while paused; mode={state.get('mode')}")

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

#!/usr/bin/env python3
"""图层冒烟：核对**可选图层**的合成契约（见 docs/engine/layers.md）。

分层是"想用才取用"的新能力，所以这里同时钉住两端：

* **建了层**：层按 z 叠放；层里没写到的格透出下层（只写字形的 HUD 压在世界之上）；
  整块铺底的浮窗把世界盖住；整层显隐立刻生效；合成耗时如实报出；
  单层读取（`screen.read(layer=...)`）能拿到"只要世界"或"只要某一层"。
* **不建层**：`layers` 为空且 `merge_ms` 恒为 0 —— 主循环里连一次合成都不会发生。
  这一半是"纯增量"的可观测证据：既有卡带照旧走原来的单层路径。

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/layer_smoke.py
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from phos import Host, main_guard, reporter  # noqa: E402

#: devkit 里的图层示例卡带（世界 / HUD / 浮窗三层），不在出厂卡带列表里。
#: 出厂卡带里也有真用图层的（`carts/tetris` 四层、`carts/worms` 三层），但那些是
#: **玩法卡带**——门禁这里测的是契约本身，用最小示例更稳（改玩法不会牵连这条门禁）
DEMO_CART = "devkit/examples/layers"
WORLD_MARK = "WORLD LAYER"
HUD_MARK = "LAYERS DEMO"
WINDOW_MARK = "LAYER WINDOW"


def read_screen(host: Host, layer: str = "") -> list[str]:
    """读屏幕文本；失败时返回空（调用方的断言会报出这一项）。"""
    payload = host.send("screen.read", layer=layer) if layer else host.send("screen.read")
    return [line.rstrip() for line in payload.get("lines", [])]


def has(rows: list[str], mark: str) -> bool:
    return any(mark in row for row in rows)


def check_demo_cart(report: Any) -> None:
    with Host(cart=DEMO_CART, headless=True, timeout=20.0,
              extra=["--save-dir", "tests-out/layers"]) as host:
        host.step(10)
        state = host.state()
        layers = state.get("layers") or []
        report.check([layer["name"] for layer in layers] == ["hud", "overlay"],
                     f"层序按 z 升序：{layers}")
        report.check(all(layer["visible"] for layer in layers), "两层初始可见")
        merge_ms = state.get("merge_ms")
        report.check(merge_ms is not None and 0 <= merge_ms <= 0.3,
                     f"合成耗时在预算内（merge_ms={merge_ms}，上限 0.3ms）")

        debug = state.get("debug") or {}
        report.check(debug.get("layer_count") == 2,
                     f"卡带自报的层数（phos.layer.order）：{debug.get('layer_count')}")

        merged = read_screen(host)
        report.check(has(merged, WORLD_MARK), "合并结果含世界（底层照旧写 phos.screen）")
        report.check(has(merged, HUD_MARK), "合并结果含 HUD（层的字形压在世界之上）")
        report.check(has(merged, WINDOW_MARK), "合并结果含浮窗")

        # 浮窗自己 `clear` 铺了底板，所以窗口**内部**不该再有世界的 "." 点阵。
        # 这一条才真正验到"不透明浮窗挡住世界"——只看 WINDOW_MARK 在不在是验不到的。
        # 位置从屏幕本身推（标题画在框内第 3 列起），不写死坐标：屏幕行含机身外壳偏移，
        # 写死 region 的 y 会对不上
        row_at = next((i for i, row in enumerate(merged) if WINDOW_MARK in row), None)
        report.check(row_at is not None, "找得到浮窗的标题行")
        if row_at is not None:
            box_x = merged[row_at].index(WINDOW_MARK) - 3
            inner = [row[box_x + 1:box_x + 30] for row in merged[row_at + 1:row_at + 11]]
            report.check(all("." not in row for row in inner),
                         "浮窗内部看不到世界的点阵（底板铺实了，世界真的被挡住）")

        hud = read_screen(host, "hud")
        report.check(has(hud, HUD_MARK) and not has(hud, WORLD_MARK),
                     "按层读：只有该层自己的内容")
        report.check(read_screen(host, "nope") == [], "未知层名读不到东西（不误报默认视图）")

        host.key("b", frames=3)
        merged = read_screen(host)
        report.check(has(merged, WORLD_MARK) and not has(merged, HUD_MARK),
                     "隐藏 HUD 层：世界还在，HUD 不再出现")
        hidden = [layer for layer in (host.state().get("layers") or []) if layer["name"] == "hud"]
        report.check(hidden and hidden[0]["visible"] is False,
                     "state.query 如实报告层的可见性")

        host.key("a", frames=3)
        report.check(not has(read_screen(host), WINDOW_MARK),
                     "关掉浮窗：窗口不再出现（层每帧从透明开始）")

        host.key("right", frames=6)
        debug = host.state().get("debug") or {}
        report.check(debug.get("cursor_x", 0) > 0, f"输入照旧生效（光标 {debug.get('cursor_x')}）")


def check_no_layer_cart(report: Any) -> None:
    # 出厂卡带都没建层：读数必须干净，且不产生任何合成开销
    with Host(cart="carts/snake", headless=True, timeout=20.0,
              extra=["--save-dir", "tests-out/layers-none"]) as host:
        host.step(30)
        state = host.state()
        report.check(state.get("layers") == [], "没建层的卡带：layers 为空数组")
        report.check(state.get("merge_ms") == 0,
                     f"没建层的卡带：merge_ms={state.get('merge_ms')}（不进行合成）")


def run() -> int:
    report, _ = reporter("layer smoke")
    check_demo_cart(report)
    check_no_layer_cart(report)
    return report.finish()


if __name__ == "__main__":
    main_guard(run)

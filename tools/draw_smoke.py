#!/usr/bin/env python3
"""叠加与半格冒烟：核对**同格多笔**与**子位落笔**的绘制契约（见 design/draw-api.md）。

这两件事是引擎保证的（卡带不该自己拼象限字符），所以门禁用**最小示例卡带**钉住能力本身，
而不是拿玩法卡带去间接验 —— 玩法一改，间接验就会开始说谎。四条断言：

* **同格两笔**：一格先写一个字形、再 blend 一笔 —— 文本里是前面那一笔，
  而**画面里两笔的墨都在**（这一条只能读像素）
* **底色独立**：`back_rect` 铺到字形之外的格子 —— 字形不动，底色铺过去
* **半格**：`plot` 落在指定子位 —— 读像素确认"墨只出现在那一象限"（等于把位序也验了）
* **叠画上限**：一格满 3 笔后 blend 返回 false（卡带自报，门禁核对）

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/draw_smoke.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from phos import (  # noqa: E402
    Host,
    cell_quadrants,
    cell_rect,
    luminance,
    main_guard,
    patch_mean,
    reporter,
)

#: devkit 里的示例卡带（见它的 main.lua：每一处只用新原语画一样东西）
DEMO_CART = "devkit/examples/inks"

#: 场景行行首的记号：门禁靠它把"内容区列号"换算成整屏列号
MARKER = "<<<"

#: 判定"两笔都在"时用的颜色优势阈值（0~255，CRT 后处理会压暗，所以别取大）
DOMINANCE = 12

#: 判定"这一象限有墨"的相对亮度阈值
INK_MARGIN = 20


def run() -> int:
    report, _ = reporter("draw smoke")
    try:
        from PIL import Image  # noqa: PLC0415  延迟导入：只有这条门禁需要读像素
    except ImportError:
        report.check(False, "需要 Pillow 才能核对像素（pip install pillow）")
        return report.finish()

    with Host(cart=DEMO_CART, headless=True, timeout=30.0,
              extra=["--save-dir", "tests-out/draw"]) as host:
        host.step(10)
        state = host.state()
        debug = state.get("debug") or {}
        scenes = debug.get("scenes") or []
        report.check(len(scenes) >= 8, f"示例卡带自报了 {len(scenes)} 个场景")
        report.check(debug.get("cap_rejected") == 1,
                     "同一格叠满 3 笔后再 blend 被拒绝（返回 false）")

        payload = host.send("screen.read")
        lines = [line.rstrip() for line in payload.get("lines", [])]
        grid = (payload.get("width", 0), payload.get("height", 0))

        # 用行首记号定位内容区第 0 列：机身外壳多宽是皮肤的事，不该写进断言
        row_at = next((i for i, line in enumerate(lines) if MARKER in line), None)
        report.check(row_at is not None, "找得到场景行（行首记号）")
        if row_at is None or not scenes:
            return report.finish()
        base_col = lines[row_at].index(MARKER)

        # ① 文本视图：一格一个字形槽，取最前面那一笔
        wrong = []
        for scene in scenes:
            col = base_col + scene["x"]
            got = lines[row_at][col] if col < len(lines[row_at]) else ""
            if got != scene["front"]:
                wrong.append(f"({scene['x']},{scene['y']}) 期望 {scene['front']!r} 得到 {got!r}"
                             f"（{scene['note']}）")
        report.check(not wrong, "文本视图取的是最前面那一笔"
                                + ("：" + "；".join(wrong) if wrong else ""))

        shot_path = Path("tests-out/draw.png").resolve()
        shot_path.parent.mkdir(parents=True, exist_ok=True)
        shot = host.send("screenshot", path=str(shot_path))
        shot_size = (shot.get("width", 0), shot.get("height", 0))
        report.check(shot_size[0] > 0 and grid[0] > 0, f"截图与网格尺寸可用：{shot_size} / {grid}")
        if shot_size[0] == 0 or grid[0] == 0:
            return report.finish()

    image = Image.open(shot_path).convert("RGB")
    by_note = {scene["note"]: scene for scene in scenes}

    # ② 同格两笔：那一格里既要有红（X）也要有绿（|）
    blend = by_note["同格两笔"]
    rect = cell_rect(base_col + blend["x"], row_at, shot_size, grid)
    red = green = 0
    for y in range(int(rect[1]), int(rect[3])):
        for x in range(int(rect[0]), int(rect[2])):
            r, g, _ = image.getpixel((x, y))
            if r > g + DOMINANCE:
                red += 1
            elif g > r + DOMINANCE:
                green += 1
    report.check(red > 0 and green > 0,
                 f"同格两笔的墨都在画面里（红 {red} px、绿 {green} px）")

    # ③ 底色独立：字形左右各一格铺上了底色（这两格没有字形，铺没铺只能读像素）
    back = by_note["底色独立"]
    extra = []
    for dx in (-1, 1):
        rect = cell_rect(base_col + back["x"] + dx, row_at, shot_size, grid)
        extra.append(patch_mean(image, (rect[0] + rect[2]) / 2, (rect[1] + rect[3]) / 2))
    lit = [luminance(p) for p in extra]
    report.check(min(lit) > INK_MARGIN,
                 f"back_rect 铺到了字形之外的格子（左右两格亮度 {[round(v) for v in lit]}）")

    # ④ 半格：墨只出现在该子位所在的象限 —— 这一条把位序也验了
    bad = []
    for note in ("左上", "右上", "左下", "右下", "同格两次 plot 合并"):
        scene = by_note[note]
        rect = cell_rect(base_col + scene["x"], row_at, shot_size, grid)
        means = [luminance(mean) for mean in cell_quadrants(image, rect)]
        brightest = means.index(max(means))
        darkest = means.index(min(means))
        if brightest == darkest or means[brightest] - means[darkest] < INK_MARGIN:
            bad.append(f"{note}：四象限亮度 {[round(v) for v in means]} 分不出墨在哪")
    report.check(not bad, "plot 的墨落在指定子位上" + ("：" + "；".join(bad) if bad else ""))

    return report.finish()


if __name__ == "__main__":
    main_guard(run)

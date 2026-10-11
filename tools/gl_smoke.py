#!/usr/bin/env python3
"""PHOSPHOR 窗口（GL）像素门禁：给 GL 渲染路补上唯一的像素级断言。

无头回归覆盖的是文本导出与 **CPU 光栅化**（`screenshot` / `draw_smoke`）；
GL 渲染、逐层叠画、着色器的笔画覆盖率分支只在**开窗**时才走，而且此前没有任何
东西核对它们画出了什么 —— `window_smoke.py` 只证明"进程活着"。
这条门禁用控制通道的 `frame.read`（glReadPixels 读回**真实帧**）逐像素核对契约：

* **不是全黑**：最基本的一条；"整屏黑却全绿溜过"正是这条门禁要根治的病
* **同格两笔**：一格先 put 红 X、再 blend 绿 | —— 画面里两笔的墨都要在
  （只有 GL 着色器按笔画覆盖率混合才画得出来，CPU 那条路画不到）
* **半格**：`plot` 的墨落在指定子位（四象限亮度分出高下），位序也被一并验了
* **逐层叠画**：图层示例卡带的世界 / HUD / 浮窗三层都要出现在同一帧里：
  世界（绿）与 HUD（黄）同时可见，且开关浮窗会明显改变整帧亮度（浮窗不透明、盖住世界）

需要图形环境（会真的弹窗）与 Pillow。GL 回读依赖真实/软件 GL 上下文：
CI 上没有图形环境时本脚本会以明确报错退出，而不是假绿 —— 该跑它的地方（开发机、
带 llvmpipe 的作业）才跑。用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/gl_smoke.py
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from phos import (  # noqa: E402
    Host,
    cell_quadrants,
    cell_rect,
    luminance,
    main_guard,
    reporter,
)

#: 示例卡带：每一处只用一种新原语画一样东西（见它们的 main.lua）
INKS_CART = "devkit/examples/inks"
LAYERS_CART = "devkit/examples/layers"

#: 场景行行首的记号：门禁靠它把"内容区列号"换算成整屏列号（不假设机身多宽）
MARKER = "<<<"

#: "两笔都在"的通道优势阈值（0~255）：CRT 后处理会压暗，别取大
DOMINANCE = 12

#: "这一象限/该处有墨"的亮度阈值
INK_MARGIN = 16


def _enter_cart(host: Host, settle: int = 24) -> None:
    """推进到对局中（mode == PLAYING）并让瞬态（开机动画、插卡闪烁）过去。

    开机动画把 `pressed("a")` 当作跳过（App::boot_should_end），所以**只在仍处于
    BOOT 时**才按键 —— 免得那一下落到卡带上（图层示例的 `a` 正是"开关浮窗"）。
    settle 要够长（默认 24 帧）：插卡后 0.3s 内主机**隔帧跳过绘制**（电压闪烁），
    落到那一帧读回来的画面是暗的，会让像素断言假失败。
    """
    host.step(1)
    for _ in range(8):
        if host.state().get("mode") != "BOOT":
            break
        host.key("a")
        host.step(1)
    host.step(settle)


def _set_window(host: Host, want: int) -> int:
    """把图层示例的浮窗拨到 want（1 开 / 0 关），返回最终状态。门禁据此不猜初始值。"""
    for _ in range(4):
        current = (host.state().get("debug") or {}).get("window_open")
        if current == want:
            return int(current or 0)
        host.key("a")
        host.step(1)
    return int((host.state().get("debug") or {}).get("window_open") or 0)


def _locate_marker(host: Host) -> tuple[int, int, tuple[int, int]]:
    """返回 (标记所在行号, 内容区第 0 列的整屏列号, (网格宽, 网格高))。"""
    payload = host.send("screen.read")
    lines = payload.get("lines", [])
    grid = (payload.get("width", 0), payload.get("height", 0))
    row_at = next((i for i, line in enumerate(lines) if MARKER in line), None)
    if row_at is None:
        raise RuntimeError("找不到场景行（行首记号 <<<）")
    return row_at, lines[row_at].index(MARKER), grid


def check_inks(report) -> None:
    """GL 路：同一格叠两笔 + 子位落笔，读回真实像素核对。"""
    with Host(cart=INKS_CART, headless=False, timeout=30.0,
              extra=["--save-dir", "tests-out/gl"]) as host:
        _enter_cart(host)
        row_at, base_col, grid = _locate_marker(host)

        shot_path = Path("tests-out/gl_inks.png").resolve()
        shot_path.parent.mkdir(parents=True, exist_ok=True)
        reply = host.send("frame.read", path=str(shot_path))
        size = (reply.get("width", 0), reply.get("height", 0))
        report.check(size[0] > 0 and size[1] > 0, f"frame.read 读回真实帧：{size}")
        report.check(reply.get("lit_ratio", 0.0) > 0.002,
                     f"画面不是全黑（亮像素占比 {reply.get('lit_ratio', 0.0):.4f}）")
        if size[0] == 0:
            return

    try:
        from PIL import Image  # noqa: PLC0415  延迟导入：只有读像素才需要
    except ImportError:
        report.check(False, "需要 Pillow 才能核对像素（pip install pillow）")
        return

    image = Image.open(shot_path).convert("RGB")

    # ① 同格两笔：内容区 (4,4) 那格里红（X）与绿（|）都要有
    rect = cell_rect(base_col + 4, row_at, size, grid)
    red = green = 0
    for y in range(int(rect[1]), int(rect[3])):
        for x in range(int(rect[0]), int(rect[2])):
            r, g, _ = image.getpixel((x, y))
            if r > g + DOMINANCE:
                red += 1
            elif g > r + DOMINANCE:
                green += 1
    report.check(red > 0 and green > 0,
                 f"GL 路径下同格两笔的墨都在（红 {red} px、绿 {green} px）")

    # ② 半格：四个子位各落一格，墨必须出现在对应象限（位序也被验了）
    bad = []
    for dx, note in ((16, "左上"), (17, "右上"), (18, "左下"), (19, "右下"), (24, "同格两次 plot 合并")):
        rect = cell_rect(base_col + dx, row_at, size, grid)
        means = [luminance(m) for m in cell_quadrants(image, rect)]
        if max(means) - min(means) < INK_MARGIN:
            bad.append(f"{note}：四象限亮度 {[round(v) for v in means]} 分不出墨在哪")
    report.check(not bad, "GL 路径下 plot 的墨落在指定子位上" + ("：" + "；".join(bad) if bad else ""))


def check_layers(report) -> None:
    """GL 路：逐层叠画。世界 / HUD / 浮窗三层要在同一帧里各就各位。"""
    with Host(cart=LAYERS_CART, headless=False, timeout=30.0,
              extra=["--save-dir", "tests-out/gl"]) as host:
        _enter_cart(host)

        def read_frame(name: str) -> tuple[dict, Path]:
            path = Path(f"tests-out/{name}.png").resolve()
            path.parent.mkdir(parents=True, exist_ok=True)
            host.step(2)
            return host.send("frame.read", path=str(path)), path

        # 不猜初始状态：显式拨到"开"，再读；这样开机跳过键那一下有没有落到卡带上都不影响
        report.check(_set_window(host, 1) == 1, "浮窗可开启")
        opened, open_path = read_frame("gl_layers_open")
        report.check(opened.get("lit_ratio", 0.0) > 0.002, "叠层画面不是全黑")
        report.check(_set_window(host, 0) == 0, "浮窗可关闭")
        closed, closed_path = read_frame("gl_layers_closed")

    try:
        from PIL import Image  # noqa: PLC0415
    except ImportError:
        report.check(False, "需要 Pillow 才能核对像素（pip install pillow）")
        return

    open_img = Image.open(open_path).convert("RGB")
    closed_img = Image.open(closed_path).convert("RGB")

    def channel_counts(img) -> tuple[int, int]:
        """整帧里"明显偏绿"与"明显偏黄"的像素数（世界绿字 / HUD 黄字）。"""
        greens = yellows = 0
        for y in range(0, img.height, 3):
            for x in range(0, img.width, 3):
                r, g, b = img.getpixel((x, y))
                if g > r + DOMINANCE and g > b + DOMINANCE:
                    greens += 1
                elif r > b + 30 and g > b + 30:
                    yellows += 1
        return greens, yellows

    greens, yellows = channel_counts(open_img)
    report.check(greens > 0, f"世界层（绿字）出现在叠层画面里（{greens} px）")
    report.check(yellows > 0, f"HUD 层（黄字）压在世界之上同时可见（{yellows} px）")

    # 浮窗不透明：开与关整帧平均亮度应明显不同（浮窗铺了一块比世界底亮的板）
    open_luma = sum(luminance(open_img.getpixel((x, y)))
                    for y in range(0, open_img.height, 4)
                    for x in range(0, open_img.width, 4))
    closed_luma = sum(luminance(closed_img.getpixel((x, y)))
                      for y in range(0, closed_img.height, 4)
                      for x in range(0, closed_img.width, 4))
    n = len(range(0, open_img.height, 4)) * len(range(0, open_img.width, 4))
    delta = (open_luma - closed_luma) / max(1, n)
    report.check(delta > 2.0, f"浮窗层确实叠上去了（开/关整帧平均亮度差 {delta:.1f}）")

    # 浮窗不透明确凿一些：浮窗铺的是一块**比世界底亮得多**的灰板（世界底是近黑的暗色），
    # 所以开窗时"亮像素"数应远多于关窗。比整帧平均值更硬——它直接数被灰板盖住的面积
    def bright_pixels(img) -> int:
        count = 0
        for y in range(0, img.height, 3):
            for x in range(0, img.width, 3):
                if luminance(img.getpixel((x, y))) > 35:
                    count += 1
        return count

    bright_open, bright_closed = bright_pixels(open_img), bright_pixels(closed_img)
    report.check(bright_open > bright_closed * 3,
                 f"浮窗不透明：开窗铺出的亮板盖住了世界（luma>35 像素 开 {bright_open} / 关 {bright_closed}）")


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 窗口（GL）像素门禁")
    parser.add_argument("--only", choices=("inks", "layers"), default=None,
                        help="只跑其中一段（默认两段都跑）")
    args = parser.parse_args()

    report, _ = reporter("gl smoke")
    if args.only in (None, "inks"):
        check_inks(report)
    if args.only in (None, "layers"):
        check_layers(report)
    return report.finish()


if __name__ == "__main__":
    main_guard(main)

#!/usr/bin/env python3
"""卡带冒烟：出厂卡带各跑一段，断言**主机没被卡带拖坏**。

它**不比对像素**。卡带的画面本来就随内容变——风速、天气、地图、站位、乃至一句文案，
改了都该变；把画面钉死，等于把"内容变了"报成"引擎坏了"。内容对不对是卡带作者的事，
这里只钉住主机那侧的硬性质：

* **跑得完**：帧数到点自己退出（不靠外部超时救场）；
* **不出错**：无卡带错误、无 Lua 报错、无看门狗；
* **有画面**：截图是合法 PNG 且不是空白屏，屏幕文本里有实字符；
* **可复现**：同种子同参数跑两遍，屏幕文本与像素**逐字节一致**——这条是主机属性，
  时间推进、随机源、渲染都不许掺进墙钟或别的运行期状态。

用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/cart_smoke.py                # 出厂卡带各 240 帧、跑两遍
    python ../tools/cart_smoke.py --frames 3000  # 拉长时间轴：抓"跑久了才露头"的问题
    python ../tools/cart_smoke.py --cart worms   # 只跑一张（可重复给）

失败时两遍的产物都留在 `tests-out/`，可以直接比对。
"""

from __future__ import annotations

import argparse
import json
import shutil
import subprocess
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from phos import reporter  # noqa: E402

#: 跑一遍的默认参数：与卡带内容无关，只保证"够久、够全"
DEFAULT_SEED = 5
DEFAULT_FRAMES = 240

#: 一遍跑不完就判失败：卡带把主循环卡死时，只有这里能发现
RUN_TIMEOUT = 90.0

#: 出现这些字样说明主机侧出了问题（卡带报错、看门狗、截图失败）
ERROR_MARKERS = ("ERROR", "WARN: screenshot failed", "cart error", "watchdog",
                 "nil value", "attempt to")

#: PNG 的魔数与 IHDR 位置：合法性与宽高都从头 24 字节读，不依赖第三方库
PNG_MAGIC = b"\x89PNG\r\n\x1a\n"

#: 空白屏（纯色）压出来的 PNG 只有几百字节，真画面是几十上百 KB
MIN_PNG_BYTES = 8192

#: 屏幕文本里的实字符下限：宿主外壳至少有边框与铭牌，一个都不剩说明没画东西
MIN_VISIBLE_CHARS = 200

EXE = "./phosphor.exe"
SCRATCH_DIR = Path("tests-out")


def scan_carts() -> tuple[list[str], list[str]]:
    """用主机的 `--scan --json` 取卡带清单，返回（可加载的 id, 加载失败的说明）。

    卡带是什么由主机定义，工具不另立一套。**加载失败的必须报出来**：否则一张卡带坏掉时
    `--scan` 只是把它标成 error，这里就变成"少测一张"，看着仍然全绿——那是最坏的假绿。
    """
    result = subprocess.run([EXE, "--scan", "carts", "--json"], capture_output=True, text=True)
    try:
        carts = json.loads(result.stdout).get("carts", [])
    except json.JSONDecodeError:
        detail = result.stdout.strip() or result.stderr.strip() or "没有任何输出"
        raise SystemExit(f"读不了 --scan --json：{detail}")
    ok = [cart["id"] for cart in carts if not cart.get("error")]
    broken = [f"{cart['id']}（{cart['error']}）" for cart in carts if cart.get("error")]
    return ok, broken


def png_size(data: bytes):
    """PNG 的宽高；不是合法 PNG 就返回 None。"""
    if len(data) < 24 or data[:8] != PNG_MAGIC or data[12:16] != b"IHDR":
        return None
    return (int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big"))


def visible_chars(text: str) -> int:
    return sum(1 for ch in text if not ch.isspace())


def first_difference(expected: str, actual: str) -> str:
    """第一处不同的行——比"两次不一样"多给一句能直接定位的话。"""
    want, got = expected.splitlines(), actual.splitlines()
    for index, (a, b) in enumerate(zip(want, got), 1):
        if a != b:
            return f"第 {index} 行不同：|{a.rstrip()}| vs |{b.rstrip()}|"
    if len(want) != len(got):
        return f"行数不同：{len(want)} vs {len(got)}"
    return "文本相同——差异在像素上"


def run_once(cart_id: str, seed: int, frames: int, tag: str) -> tuple[int, str, str, bytes]:
    """跑一遍，返回（退出码, 屏幕文本, 错误输出, PNG 字节）。

    每次都用**全新**的存档区：卡带会把自己的最高分、进度画到屏幕上，
    沿用上一遍留下的存档，"同参数"就不再是同一起点了。
    """
    SCRATCH_DIR.mkdir(parents=True, exist_ok=True)
    saves = SCRATCH_DIR / "saves"
    shutil.rmtree(saves, ignore_errors=True)
    png = SCRATCH_DIR / f"{cart_id}.run{tag}.png"
    png.unlink(missing_ok=True)
    try:
        result = subprocess.run(
            [EXE, "--cart", f"carts/{cart_id}", "--headless", "--seed", str(seed),
             "--frames", str(frames), "--dump-screen", "--screenshot", str(png),
             "--save-dir", str(saves)],
            capture_output=True, text=True, timeout=RUN_TIMEOUT)
    except subprocess.TimeoutExpired:
        return -1, "", f"{RUN_TIMEOUT:g} 秒内没跑完（卡带把主循环卡住了？）", b""
    return result.returncode, result.stdout, result.stderr, (png.read_bytes() if png.exists() else b"")


def main() -> int:
    parser = argparse.ArgumentParser(description="卡带冒烟：跑得完 / 不出错 / 有画面 / 可复现")
    parser.add_argument("--cart", action="append", default=[], help="只跑这张卡带（可重复给）")
    parser.add_argument("--seed", type=int, default=DEFAULT_SEED, help="随机种子")
    parser.add_argument("--frames", type=int, default=DEFAULT_FRAMES, help="每遍跑多少逻辑帧")
    args = parser.parse_args()

    if not Path(EXE).exists():
        raise SystemExit(f"{EXE} 不存在——请在含 phosphor.exe 的构建目录里运行")

    available, broken = scan_carts()
    carts = args.cart or available
    if not carts:
        raise SystemExit("没有可测的卡带（carts/ 下没有能加载的卡带？）")

    report, _ = reporter("cart smoke")
    print(f"  参数: seed={args.seed} frames={args.frames}   卡带 {len(carts)} 张，各跑两遍")
    report.check(not broken, "carts/ 下没有加载失败的卡带"
                             + (f"：{broken}" if broken else ""))

    for cart_id in carts:
        started = time.perf_counter()
        code, text, err, png = run_once(cart_id, args.seed, args.frames, "1")
        elapsed = time.perf_counter() - started

        hit = [marker for marker in ERROR_MARKERS if marker in text or marker in err]
        report.check(code == 0 and not hit,
                     f"{cart_id}: {args.frames} 帧跑完、无报错"
                     f"（{elapsed:.1f}s，退出码 {code}" + (f"，命中 {hit}" if hit else "") + "）")

        dims = png_size(png)
        report.check(dims is not None, f"{cart_id}: 截图是合法 PNG（{dims}）")
        report.check(len(png) >= MIN_PNG_BYTES,
                     f"{cart_id}: 画面不是空白（PNG {len(png)} 字节）")
        report.check(visible_chars(text) >= MIN_VISIBLE_CHARS,
                     f"{cart_id}: 屏幕上有内容（实字符 {visible_chars(text)}）")

        code2, text2, err2, png2 = run_once(cart_id, args.seed, args.frames, "2")
        same = code2 == code and text2 == text and png2 == png
        report.check(same, f"{cart_id}: 同种子跑两遍逐字节一致（可复现）")
        if not same:
            print(f"        两遍的产物留在 {SCRATCH_DIR}/（{cart_id}.run1.* 与 .run2.*）")
            print(f"        {first_difference(text, text2)}")

    return report.finish()


if __name__ == "__main__":
    raise SystemExit(main())

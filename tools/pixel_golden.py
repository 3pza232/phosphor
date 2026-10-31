#!/usr/bin/env python3
"""画面像素基线（**非门禁**）：固定场景的 headless 截图 vs tools/golden/pixel/。

为什么需要它：文本基线（shell_golden.py）只能证明"字符网格没变"，字体、CRT 后处理、
主题配色与像素级绘制（同格两笔 / 半格）的回归它看不见。这里用同一台构建出的
phosphor.exe 跑固定帧数、固定种子的场景，把 CPU 光栅化截图缩到 320x180 后与基线比。

**非门禁**：不同机器的字体光栅化/驱动差异会造成几十个像素的差异，误报率不值得。
界面有意改变时手动跑 --update 重建基线并在 review 里看 diff。

跑法（仓库根或含 phosphor.exe 的构建目录都可）::

    python tools/pixel_golden.py            # 校验（失败非零退出）
    python tools/pixel_golden.py --update   # 重建基线（界面有意改变时才做）

状态隔离：每个场景独立 tests-out/pixel-golden/<scene>/{config.json,saves,recent.txt}，
不碰玩家的 config.json / saves / recent.txt；固定 --seed 与 --frames。
基线生成依赖构建目录里的出厂卡带（build/carts）：自己塞进 build/carts 的卡带会改变
卡带架场景，属预期。
"""

from __future__ import annotations

import argparse
import shutil
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent
GOLDEN_DIR = HERE / "golden" / "pixel"

#: 缩略尺寸：基线很小（单张几十 KB），同时保留字形/配色差异的可辨识度。
THUMB = (320, 180)

#: 判定阈值：平均绝对差（全通道）<= 2，且"明显差异像素"比例 <= 0.5%。
#: 明显差异 = 任一通道绝对差 > 8：LANCZOS 缩放后的轻微振铃不该算回归。
MAD_LIMIT = 2.0
OBVIOUS_DELTA = 8
OBVIOUS_RATIO_LIMIT = 0.005

SEED = 1

#: 固定场景。画面只由 --frames/--seed/出厂卡带内容决定（无墙钟、无外部输入）。
SCENES = (
    ("snake_f90", "carts/snake", 90),
    ("xiangqi_f90", "carts/xiangqi", 90),
    ("shelf_f264", None, 264),  # 264 帧：开机自检播完、落在卡带架
)


def find_exe() -> tuple[Path, Path]:
    """返回 (exe, 工作目录)。优先仓库根的 build/phosphor.exe，其次当前目录。"""
    candidates = (
        (REPO / "build" / "phosphor.exe", REPO / "build"),
        (Path.cwd() / "phosphor.exe", Path.cwd()),
    )
    for exe, workdir in candidates:
        if exe.is_file():
            return exe.resolve(), workdir.resolve()
    raise SystemExit("找不到 phosphor.exe（期望 build/phosphor.exe 或在构建目录里运行）")


def capture(exe: Path, workdir: Path, name: str, cart: str | None, frames: int):
    """跑一帧并返回缩略后的 RGB 图（Pillow Image）。"""
    from PIL import Image  # noqa: PLC0415  延迟导入：只有本工具需要 Pillow

    scene_dir = workdir / "tests-out" / "pixel-golden" / name
    shutil.rmtree(scene_dir, ignore_errors=True)
    scene_dir.mkdir(parents=True)
    config = scene_dir / "config.json"
    config.write_text("{}\n", encoding="utf-8")  # 空配置 = 全默认；不读玩家设置
    screenshot = scene_dir / f"{name}.png"

    command = [
        str(exe),
        "--headless",
        "--frames",
        str(frames),
        "--seed",
        str(SEED),
        "--config",
        str(config),
        "--save-dir",
        str(scene_dir / "saves"),
        "--recent",
        str(scene_dir / "recent.txt"),
        "--screenshot",
        str(screenshot),
    ]
    if cart:
        command += ["--cart", cart]
    proc = subprocess.run(command, cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"{name}: phosphor.exe 退出码 {proc.returncode}\n{proc.stderr[-800:]}")
    if not screenshot.is_file():
        raise RuntimeError(f"{name}: 没有生成截图 {screenshot}\n{proc.stderr[-800:]}")
    with Image.open(screenshot) as image:
        return image.convert("RGB").resize(THUMB, Image.Resampling.LANCZOS)


def compare(expected, actual) -> tuple[float, float]:
    """返回 (平均绝对差, 明显差异像素比例)。两图尺寸一致。"""
    if expected.size != actual.size:
        raise ValueError(f"尺寸不一致：基线 {expected.size} vs 当前 {actual.size}")
    lhs = expected.tobytes()
    rhs = actual.tobytes()
    total = 0
    obvious = 0
    pixels = len(lhs) // 3
    for offset in range(0, len(lhs), 3):
        dr = abs(lhs[offset] - rhs[offset])
        dg = abs(lhs[offset + 1] - rhs[offset + 1])
        db = abs(lhs[offset + 2] - rhs[offset + 2])
        total += dr + dg + db
        if max(dr, dg, db) > OBVIOUS_DELTA:
            obvious += 1
    return total / (pixels * 3), obvious / pixels


def main() -> int:
    parser = argparse.ArgumentParser(
        description="画面像素基线（非门禁；字体/驱动差异可能误报）")
    parser.add_argument("--update", action="store_true", help="重建基线（界面有意改变时才做）")
    args = parser.parse_args()

    try:
        from PIL import Image  # noqa: F401, PLC0415
    except ImportError:
        print("pixel golden: 需要 Pillow（pip install pillow）")
        return 1

    exe, workdir = find_exe()
    print(f"pixel golden: exe={exe}  size={THUMB[0]}x{THUMB[1]}  "
          f"阈值 MAD<={MAD_LIMIT} obvious<={OBVIOUS_RATIO_LIMIT:.1%}")
    if args.update:
        GOLDEN_DIR.mkdir(parents=True, exist_ok=True)

    failures = 0
    try:
        for name, cart, frames in SCENES:
            current = capture(exe, workdir, name, cart, frames)
            baseline = GOLDEN_DIR / f"{name}.png"
            if args.update:
                current.save(baseline, optimize=True)
                print(f"  wrote {baseline.relative_to(REPO)}  "
                      f"({baseline.stat().st_size // 1024} KB)")
                continue
            if not baseline.is_file():
                print(f"  FAIL {name}: 基线缺失（先跑 --update）")
                failures += 1
                continue
            from PIL import Image  # noqa: PLC0415

            with Image.open(baseline) as image:
                expected = image.convert("RGB")
            mad, obvious = compare(expected, current)
            ok = mad <= MAD_LIMIT and obvious <= OBVIOUS_RATIO_LIMIT
            print(f"  {'ok  ' if ok else 'FAIL'} {name}: mad={mad:.3f} "
                  f"obvious={obvious:.3%}")
            if not ok:
                failures += 1
    except (OSError, RuntimeError) as error:
        print(f"pixel golden: {error}")
        return 1

    if args.update:
        print("\n基线已更新：请把 tools/golden/pixel/*.png 的 diff 一起 review。")
        return 0
    if failures:
        print(f"\npixel golden: {failures} 个场景与基线不一致")
        return 1
    print("\npixel golden: 全部场景一致")
    return 0


if __name__ == "__main__":
    sys.exit(main())

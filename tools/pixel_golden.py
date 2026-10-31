#!/usr/bin/env python3
"""画面像素基线（**非门禁**）：固定场景的截图 vs tools/golden/pixel/。

为什么需要它：文本基线（shell_golden.py）只能证明"字符网格没变"，字体、CRT 后处理、
主题配色与像素级绘制（同格两笔 / 半格）的回归它看不见。这里用同一台构建出的
phosphor.exe 跑固定场景，把 CPU 光栅化截图缩到 320x180 后与基线比。

场景有两类：
* CLI 直出（--frames/--seed/--screenshot）：snake / xiangqi / 卡带架；
* 控制通道驱动（tools/phos.py 的 Host）：设置 / Mod / 磁带码 / UI 示例。外壳屏
  （设置、Mod）整屏含机身边框，而边灯是呼吸动画（相位取决于控制通道接管前的实时帧），
  所以这两屏在缩略前裁到 80x45 内容区；卡带画面（磁带码/UI）不带呼吸灯，保留整屏。

**非门禁**：不同机器的字体光栅化/驱动差异会造成几十个像素的差异，误报率不值得。
界面有意改变时手动跑 --update 重建基线并在 review 里看 diff。

跑法（仓库根或含 phosphor.exe 的构建目录都可）::

    python tools/pixel_golden.py            # 校验（失败非零退出）
    python tools/pixel_golden.py --update   # 重建基线（界面有意改变时才做）

状态隔离：每个场景独立 tests-out/pixel-golden/<scene>/{config.json,saves,recent.txt}，
不碰玩家的 config.json / saves / recent.txt；固定 --seed，CLI 场景固定 --frames，
控制通道场景固定单步次数。基线生成依赖构建目录里的出厂卡带（build/carts）与
build/devkit：自己塞进 build/carts 的卡带会改变卡带架场景，属预期。
"""

from __future__ import annotations

import argparse
import json
import os
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

#: 默认字体/皮肤下的一屏网格与内容区（字符格）：截图 1344x816 = 84x51 格，每格 16px。
#: 只用于裁掉外壳机身边灯（呼吸动画），不参与坐标计算以外的任何逻辑。
GRID = (84, 51)
CONTENT_CELLS = (2, 3, 80, 45)


def _drive_settings(host) -> None:
    """开机自检播完（264 帧，与 CLI 卡带架场景同一帧数）→ 设置屏。"""
    host.step(264)
    host.key("settings")
    host.step(3)


def _drive_mods(host) -> None:
    host.step(264)
    host.key("m")
    host.step(3)


def _drive_tape(host) -> None:
    """真实卡带 → Esc 暂停 → 移到磁带码 → 进入。"""
    host.step(60)
    host.key("escape")
    host.step(3)
    host.key("down")
    host.step(1)
    host.key("start")
    host.step(3)


def _drive_ui_example(host) -> None:
    host.step(12)


#: CLI 直出场景：(名字, 卡带, 帧数)。
CLI_SCENES = (
    ("snake_f90", "carts/snake", 90),
    ("xiangqi_f90", "carts/xiangqi", 90),
    ("shelf_f264", None, 264),  # 开机自检播完、落在卡带架
)

#: 控制通道场景：(名字, 卡带, 驱动, 是否裁内容区)。
#: 设置/Mod 是闲置外壳屏，机身边灯呼吸相位受控制通道接管前的实时帧影响 → 裁掉机身。
#: 磁带码/UI 在卡带画面路径上，边灯常亮，整屏截图本身可复现。
HOST_SCENES = (
    ("settings", None, _drive_settings, True),
    ("mods", None, _drive_mods, True),
    ("tape_f66", "carts/snake", _drive_tape, False),
    ("ui_example_f12", "devkit/examples/ui", _drive_ui_example, False),
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


def _prepare_scene(workdir: Path, name: str,
                   config_text: str) -> tuple[Path, Path, Path, Path, Path]:
    """建独立场景目录，返回 (dir, config, saves, recent, raw 截图路径)。"""
    scene_dir = workdir / "tests-out" / "pixel-golden" / name
    shutil.rmtree(scene_dir, ignore_errors=True)
    scene_dir.mkdir(parents=True)
    config = scene_dir / "config.json"
    config.write_text(config_text, encoding="utf-8")  # 隔离配置；不读玩家设置
    saves = scene_dir / "saves"
    saves.mkdir()
    recent = scene_dir / "recent.txt"
    raw = scene_dir / f"{name}-raw.png"
    return scene_dir, config, saves, recent, raw


def _crop_content(image):
    """裁到内容区（去掉机身边框/呼吸灯）。默认皮肤下截图恰为 84x51 格。"""
    cols, rows = GRID
    if image.width % cols != 0 or image.height % rows != 0:
        raise RuntimeError(
            f"截图尺寸 {image.width}x{image.height} 不是默认 {cols}x{rows} 格；"
            "换过字体/皮肤时先确认内容区几何再更新工具")
    cell = image.width // cols
    x, y, w, h = CONTENT_CELLS
    return image.crop((x * cell, y * cell, (x + w) * cell, (y + h) * cell))


def _load_and_save_source(raw: Path, scene_dir: Path, name: str, crop: bool):
    """把原始截图规范化成场景 source PNG（裁边后重存），返回 Pillow RGB 图。"""
    from PIL import Image  # noqa: PLC0415

    with Image.open(raw) as loaded:
        image = loaded.convert("RGB")
    if crop:
        image = _crop_content(image)
    image.save(scene_dir / f"{name}.png", optimize=True)
    raw.unlink()
    return image


def _thumbnail(image):
    from PIL import Image  # noqa: PLC0415

    return image.resize(THUMB, Image.Resampling.LANCZOS)


def capture_cli(exe: Path, workdir: Path, name: str, cart: str | None, frames: int):
    scene_dir, config, saves, recent, raw = _prepare_scene(workdir, name, "{}\n")
    command = [
        str(exe), "--headless", "--frames", str(frames), "--seed", str(SEED),
        "--config", str(config), "--save-dir", str(saves), "--recent", str(recent),
        "--screenshot", str(raw),
    ]
    if cart:
        command += ["--cart", cart]
    proc = subprocess.run(command, cwd=workdir, capture_output=True, text=True,
                          encoding="utf-8", errors="replace", check=False)
    if proc.returncode != 0:
        raise RuntimeError(f"{name}: phosphor.exe 退出码 {proc.returncode}\n{proc.stderr[-800:]}")
    if not raw.is_file():
        raise RuntimeError(f"{name}: 没有生成截图 {raw}\n{proc.stderr[-800:]}")
    return _thumbnail(_load_and_save_source(raw, scene_dir, name, crop=False))


_PHOS = None


def _phos():
    """延迟 import tools/phos.py（Host + DEFAULT_CONFIG）。"""
    global _PHOS
    if _PHOS is None:
        sys.path.insert(0, str(HERE))
        import phos  # noqa: PLC0415

        _PHOS = phos
    return _PHOS


def capture_host(exe: Path, workdir: Path, name: str, cart: str | None, drive, crop: bool):
    """控制通道驱动到目标屏，发 screenshot 命令，按需裁内容区后缩略。"""
    phos = _phos()
    # 与 shell_golden 用同一份 DEFAULT_CONFIG：设置/Mod/磁带码测的就是文本基线的那一屏
    config_text = json.dumps(phos.DEFAULT_CONFIG, ensure_ascii=False)
    scene_dir, config, saves, recent, raw = _prepare_scene(workdir, name, config_text)
    Host = phos.Host
    old_cwd = os.getcwd()
    try:
        os.chdir(workdir)  # Host 以 cwd 作为运行目录（内容根/相对 exe 的约定）
        extra = ("--seed", str(SEED), "--recent", str(recent), "--save-dir", str(saves))
        with Host(exe=str(exe), cart=cart, config=str(config),
                  log_path=str(scene_dir / "host_stderr.log"), extra=extra) as host:
            drive(host)
            reply = host.send("screenshot", path=str(raw))
            if not reply.get("path"):
                raise RuntimeError(f"{name}: 控制通道 screenshot 失败：{reply}")
    finally:
        os.chdir(old_cwd)
    if not raw.is_file():
        raise RuntimeError(f"{name}: 控制通道没有生成截图 {raw}")
    return _thumbnail(_load_and_save_source(raw, scene_dir, name, crop=crop))


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
        for name, cart, frames in CLI_SCENES:
            current = capture_cli(exe, workdir, name, cart, frames)
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
        for name, cart, drive, crop in HOST_SCENES:
            current = capture_host(exe, workdir, name, cart, drive, crop)
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

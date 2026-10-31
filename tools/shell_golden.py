#!/usr/bin/env python3
"""外壳界面的文本基线：驱动每个屏，把 screen.read 的结果逐字节存进 tests/golden/shell/。

为什么需要它：UI 组件层迁移外壳时，判断"对不对"不能靠肉眼——同一屏在迁移前后必须
逐字节一致。基线是**行为契约**，不是截图替代品：文本网格本身就零误差。

跑法（在含 phosphor.exe 的构建目录）：

    python ../tools/shell_golden.py --write    # 重新生成基线（界面有意改变时才做）
    python ../tools/shell_golden.py            # 校验（不一致非零退出）

基线里不含随机/时间内容：所有输入都由控制通道单步驱动，帧数固定。
前提：**在干净的构建目录里跑**（只有出厂卡带）。卡带架的顺序与条目来自 `carts/`：
开发时自己塞进去的卡带会改变这一屏，属预期——要么先移走，要么不要用这条基线
断言自己的私有卡带。工具用 `--recent` 隔离了"最近打开"顺序，不碰玩家设置。
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from phos import DEFAULT_CONFIG, Host  # noqa: E402

GOLDEN_DIR = HERE.parent / "tests" / "golden" / "shell"


def _dump_screen(frames: int, seed: int = 1) -> str:
    """不经控制通道的一帧捕获：--frames 精确推进 N 帧后 --dump-screen。

    boot 动画的字符随动画时间变化，而控制通道接管前宿主会先跑若干实时帧
    （数量取决于进程启动耗时），文本因此不稳定。这条路径没有那个竞态。
    """
    import json
    import subprocess
    import tempfile

    with tempfile.TemporaryDirectory() as tmp:
        config = Path(tmp) / "config.json"
        config.write_text(json.dumps(DEFAULT_CONFIG, ensure_ascii=False), encoding="utf-8")
        proc = subprocess.run(
            ["./phosphor.exe", "--headless", "--frames", str(frames), "--seed", str(seed),
             "--config", str(config), "--save-dir", str(Path(tmp) / "saves"), "--dump-screen"],
            capture_output=True, text=True, encoding="utf-8", check=False)
        if proc.returncode != 0:
            raise RuntimeError(f"dump-screen failed: {proc.stderr[-800:]}")
        return proc.stdout

#: 固定种子：boot 动画与部分内容用 phos.sys.random，不固定种子基线就不稳定。
#: --recent 指向运行目录下的文件：卡带架顺序来自"最近打开"，不能借用玩家的 recent.txt，
#: 否则同一份基线在干净目录与开发目录里不一致。
SEED = ("--seed", "1", "--recent", "tests-out/golden-recent.txt",
        # 存档也隔离：磁带码屏会列出本机存档，若共用运行目录的 saves/
        # 基线会随"谁跑过哪张卡带"漂移
        "--save-dir", "tests-out/golden-saves")


def _normalize_shelf_order(host: Host) -> None:
    """把"最近打开"顺序归一化：按 id 升序依次装载并弹出，最后一张在最前。

    卡带架首屏的顺序由 recent 决定；不归一化时，基线会在"跑过某张卡带"之后漂移。
    走控制通道而不是直接写文件：顺序的语义由主机自己产生，测试只驱动行为。
    """
    ids = sorted(c["id"] for c in host.carts() if c.get("id"))
    for cart_id in ids:
        host.send("cart.load", path=f"carts/{cart_id}")
        host.step(2)
        host.send("cart.eject")
        # 拔卡收缩动画约 21 帧：没放完之前外壳不接收输入，架子也还没画出来
        host.step(30)


#: 一个屏 = 一段驱动脚本 + 期望捕获的文本。boot/shelf/settings/mods/search 共用一个宿主；
#: 游戏内暂停/磁带码需要真实卡带，另起一个。
def _screens() -> dict[str, str]:
    shots: dict[str, str] = {}
    shots["boot"] = _dump_screen(24)

    with Host(extra=SEED) as host:
        host.step(264)
        _normalize_shelf_order(host)
        host.step(4)
        shots["shelf"] = host.screen_text()
        host.key("settings")
        host.step(3)
        shots["settings"] = host.screen_text()
        host.key("escape")
        host.step(3)
        host.key("m")
        host.step(3)
        shots["mods"] = host.screen_text()
        host.key("escape")
        host.step(3)
        host.key("f")
        host.text("sn")
        host.step(3)
        shots["search"] = host.screen_text()
        host.key("escape")
        host.step(2)
        # 错误屏：装载一张不存在的卡带，主机进入 CART_ERROR
        host.send("cart.load", path="carts/__missing__")
        host.step(3)
        shots["error"] = host.screen_text()

    with Host(cart="carts/snake", extra=SEED) as host:
        host.step(60)
        host.key("escape")
        host.step(3)
        shots["paused"] = host.screen_text()
        host.key("down")
        host.step(1)
        host.key("start")
        host.step(3)
        shots["tape"] = host.screen_text()
    return shots


def main() -> int:
    parser = argparse.ArgumentParser(description="外壳界面文本基线")
    parser.add_argument("--write", action="store_true", help="重建基线文件")
    args = parser.parse_args()

    import shutil
    shutil.rmtree("tests-out/golden-saves", ignore_errors=True)

    shots = _screens()
    GOLDEN_DIR.mkdir(parents=True, exist_ok=True)

    failed = 0
    for name in sorted(shots):
        path = GOLDEN_DIR / f"{name}.txt"
        text = shots[name]
        if args.write:
            path.write_text(text, encoding="utf-8")
            print(f"  wrote {path.relative_to(HERE.parent)}  ({len(text)} bytes)")
            continue
        if not path.exists():
            print(f"  FAIL {name}: 基线缺失（先跑 --write）")
            failed += 1
            continue
        expected = path.read_text(encoding="utf-8")
        if expected == text:
            print(f"  ok   {name}")
        else:
            print(f"  FAIL {name}: 与基线不一致")
            failed += 1
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
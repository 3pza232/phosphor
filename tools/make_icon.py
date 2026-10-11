#!/usr/bin/env python3
"""从 theme/icon/phos_icon.jpg 生成 Windows 可执行文件用的多尺寸 .ico。

为什么是**开发期**脚本、而不是构建期生成：工程构建不依赖 Python（见 architecture.md），
而 exe 的图标是**链接期资源**（嵌进可执行文件，不像窗口图标那样运行时能换），所以
`.ico` 只在开发期生成一次、随源码提交。换了 `phos_icon.jpg` 想同步 exe 图标时再跑一次：

    python tools/make_icon.py

尺寸覆盖 Explorer / 任务栏 / Alt-Tab 各场景。窗口图标（`glfwSetWindowIcon`）读的是
那份 jpg，运行时即可替换；两者是**两件事**，见 docs/content-packs.md。
"""

from __future__ import annotations

import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "package" / "theme" / "icon" / "phos_icon.jpg"
DST = ROOT / "package" / "theme" / "icon" / "phos_icon.ico"
SIZES = (16, 24, 32, 48, 64, 128, 256)


def main() -> int:
    try:
        from PIL import Image  # noqa: PLC0415
    except ImportError:
        print("需要 Pillow 才能生成图标（pip install pillow）", file=sys.stderr)
        return 2
    if not SRC.exists():
        print(f"找不到源图：{SRC}", file=sys.stderr)
        return 2

    image = Image.open(SRC).convert("RGBA")
    image.save(DST, format="ICO", sizes=[(size, size) for size in SIZES])
    print(f"wrote {DST.relative_to(ROOT)} ({DST.stat().st_size} bytes)")
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""PHOSPHOR 控制通道客户端：工具脚本共用的最小库。

为什么不用 PowerShell：这些脚本要驱动一个 CMake/C++ 项目，本身与 Windows
无关。用 Python 只依赖标准库就能在任何平台跑，也就没有 .ps1 的 UTF-8 BOM、
控制台代码页、`ReadLine()` 无超时（会永久挂死）这些与项目无关的坑。

约定：工作目录是含 phosphor.exe 的构建目录（build/）——程序按相对路径找
carts/、theme/、config.json。

用法::

    from phos import Host, free_port

    with Host(cart="carts/snake") as host:
        host.step(60)
        assert host.state()["mode"] == "PLAYING"
        host.key("right")
        print(host.screen_text())
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import time
from typing import Any, Iterable, Sequence


def free_port() -> int:
    """向系统要一个空闲端口。

    固定端口有个致命失败模式：上一次运行留下的宿主进程占着端口时，
    新连接会连到"旧宿主"上，等一个再也不会来的握手，于是永久阻塞。
    每次运行都换端口，这个失败模式就不存在了。
    """
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as probe:
        probe.bind(("127.0.0.1", 0))
        return int(probe.getsockname()[1])


class HostError(RuntimeError):
    """控制通道层面的失败（连不上、超时、主机退出）"""


class Host:
    """一次被驱动的宿主运行。用 with 语句确保进程一定被收掉。"""

    def __init__(
        self,
        exe: str = "./phosphor.exe",
        cart: str | None = None,
        extra: Iterable[str] = (),
        timeout: float = 15.0,
        log_path: str | None = None,
        headless: bool = True,
    ) -> None:
        if not os.path.exists(exe):
            raise HostError(f"{exe} 不存在——请在含 phosphor.exe 的构建目录里运行")
        self.timeout = timeout
        self.log_path = log_path or "host_stderr.log"
        self.headless = headless
        self.port = free_port()
        args = [exe]
        if cart:
            args += ["--cart", cart]
        args += ["--control", str(self.port)]
        if headless:
            args.append("--headless")  # 要"开窗给人看"的脚本必须能关掉它
        args += list(extra)

        self._log = open(self.log_path, "wb")
        self._proc = subprocess.Popen(
            args, stdout=subprocess.DEVNULL, stderr=self._log, cwd=os.getcwd()
        )
        self._sock: socket.socket | None = None
        self._reader = None
        self._next_id = 1
        self.exited_cleanly = False  # close() 里回填：quit 是否让它自己退了
        self._connect()

    # ---------------------------------------------------------------- 连接

    def _connect(self) -> None:
        """连上控制通道并吃掉握手事件（主动重试，不靠固定 sleep）。"""
        deadline = time.monotonic() + self.timeout
        while True:
            if self._proc.poll() is not None:
                raise HostError(f"宿主启动即退出（码 {self._proc.returncode}）")
            try:
                sock = socket.create_connection(("127.0.0.1", self.port), timeout=0.5)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise HostError("等待控制通道超时") from None
                time.sleep(0.05)
        sock.settimeout(self.timeout)
        self._sock = sock
        self._reader = sock.makefile("rb")
        hello = self._read_line()
        if hello is None or '"hello"' not in hello:
            raise HostError(f"没有收到握手事件：{hello!r}")

    def _read_line(self) -> str | None:
        assert self._reader is not None
        try:
            raw = self._reader.readline()
        except (TimeoutError, socket.timeout):
            raise HostError(f"主机 {self.timeout:g}s 内没有回包") from None
        if not raw:
            return None
        return raw.decode("utf-8", "replace").rstrip("\r\n")

    # ---------------------------------------------------------------- 协议

    def send(self, cmd: str, **args: Any) -> dict:
        """发一条命令并返回它的响应。主动事件（hello/cart.*）自动跳过。"""
        if self._sock is None:
            raise HostError("通道已关闭")
        command = {"id": self._next_id, "cmd": cmd, **args}
        self._next_id += 1
        self._sock.sendall((json.dumps(command, ensure_ascii=False) + "\n").encode("utf-8"))
        while True:
            line = self._read_line()
            if line is None:
                raise HostError("主机关闭了通道")
            if '"event"' in line:
                continue
            return json.loads(line)

    def state(self) -> dict:
        return self.send("state.query")

    def lines(self) -> list[str]:
        return self.send("screen.read").get("lines", [])

    def screen_text(self) -> str:
        return "\n".join(self.lines())

    def carts(self) -> list[dict]:
        return self.send("carts.scan").get("carts", [])

    # ---------------------------------------------------------------- 驱动

    def step(self, frames: int) -> dict:
        return self.send("time.step", frames=frames)

    def inject_key(self, name: str, frames: int = 1) -> dict:
        """只注入一次按键，**不推进帧**。

        这是"按下"的原语：实时（窗口）模式下画面由主机自己走，推进帧反而会
        把它冻成单步；需要精确步进的人用 key()，或自己接 step()。
        """
        return self.send("input.inject", key=name, frames=frames)

    def key(self, name: str, frames: int = 2) -> dict:
        """按一个键并推进若干帧（"按下"原语 + 步进）。

        默认 2 帧：按下是**边沿触发**，同一键连按时若只推进 1 帧，
        上一次的松键还没落地，下一次就不构成新的按下（光标会卡住）。
        """
        self.inject_key(name)
        return self.step(frames)

    def text(self, value: str, frames: int = 2) -> dict:
        """注入文本（与玩家敲键盘等价；`"\\b"` 是退格）。

        与 key() 一样默认推进帧：文本要**下一逻辑帧**才被界面读到，
        不推帧就去看画面只会看到旧内容。
        """
        self.send("input.text", text=value)
        return self.step(frames)

    def _cursor(self) -> int:
        cursor = int(self.state().get("cursor", -1))
        if cursor < 0:
            raise HostError(f"the current mode has no menu (cursor={cursor})")
        return cursor

    def walk_cursor(self, target: int, key: str = "down", limit: int = 64) -> int:
        """按光标走到目标行，返回最终光标。

        为什么不能数按键次数：菜单项一增减就会走错行，写死"最多按几次"同样脆。
        为什么两条轴都试：有些列表只认一组方向键——卡带架在"橱窗"样式下只认左右，
        "列表"样式下才认上下。工具不该假设哪条轴能动，试一下、不动就换。
        """
        cursor = self._cursor()
        axes = [key, "right" if key in ("down", "up") else "down"]
        for axis in axes:
            while cursor != target:
                before = cursor
                self.key(axis)
                cursor = self._cursor()
                if cursor == before:
                    break  # 这条轴不动，换下一条
                limit -= 1
                if limit <= 0:
                    return cursor
            if cursor == target:
                return cursor
        return cursor

    # ---------------------------------------------------------------- 收尾

    def stderr_text(self) -> str:
        """主机 stderr 全文。按路径读，所以 close() 之后调用也安全。"""
        if self._log and not self._log.closed:
            self._log.flush()
        try:
            with open(self.log_path, "rb") as handle:
                return handle.read().decode("utf-8", "replace")
        except OSError:
            return ""

    @property
    def pid(self) -> int:
        return self._proc.pid

    @property
    def exited(self) -> bool:
        return self._proc.poll() is not None

    def wait(self, timeout: float = 8.0) -> int | None:
        """等宿主自己退出；返回退出码，超时返回 None。"""
        try:
            return self._proc.wait(timeout=timeout)
        except subprocess.TimeoutExpired:
            return None

    def close(self) -> None:
        """尽力优雅退出，然后无条件确保进程消失。"""
        if self._sock is not None:
            try:
                self.send("quit")
            except (HostError, OSError, ValueError):
                pass
        if self._sock is not None:
            self._sock.close()
            self._sock = None
        self._reader = None
        try:
            # 走完 quit 的进程会自己退出；要动 kill 才死说明它没听话
            self._proc.wait(timeout=5)
            self.exited_cleanly = True
        except subprocess.TimeoutExpired:
            self._proc.kill()
            self._proc.wait(timeout=5)
            self.exited_cleanly = False
        self._log.close()

    def __enter__(self) -> "Host":
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()


def reporter(title: str) -> tuple[Any, Any]:
    """返回 (check, finish)：check 记账，finish 汇总并以退出码结束。"""

    class Report:
        def __init__(self) -> None:
            self.failures = 0

        def check(self, condition: object, what: str) -> None:
            if condition:
                print(f"  ok   {what}")
            else:
                print(f"  FAIL {what}")
                self.failures += 1

        def finish(self) -> int:
            print()
            if self.failures == 0:
                print(f"{title}: all checks passed")
                return 0
            print(f"{title}: {self.failures} check(s) FAILED")
            return 1

    report = Report()
    return report, report


def main_guard(fn: Any) -> None:
    """统一入口：把 HostError 变成清晰的报错 + 非 0 退出码。"""
    try:
        sys.exit(fn())
    except HostError as err:
        print(f"FATAL: {err}", file=sys.stderr)
        sys.exit(2)
    except KeyboardInterrupt:
        print("interrupted", file=sys.stderr)
        sys.exit(130)


# ---------------------------------------------------------------- 像素核对（门禁共用）
# 读像素的门禁（draw_smoke / gl_smoke）共用同一套采样原语：格子尺寸一律从
# "图像尺寸 ÷ 网格尺寸"推，绝不写死 16 —— 主题几何一改，写死的列号就全错。

#: 象限采样点（相对格子的比例）：左上 / 右上 / 左下 / 右下
QUADRANTS = ((0.25, 0.25), (0.75, 0.25), (0.25, 0.75), (0.75, 0.75))


def luminance(pixel: Sequence[float]) -> float:
    return 0.299 * pixel[0] + 0.587 * pixel[1] + 0.114 * pixel[2]


def patch_mean(image: Any, cx: float, cy: float, radius: int = 3) -> tuple[float, float, float]:
    """以 (cx, cy) 为中心取一小块的平均色：抗 CRT 扫描线的逐行明暗。"""
    total = [0.0, 0.0, 0.0]
    count = 0
    for y in range(max(0, int(cy - radius)), int(cy + radius) + 1):
        for x in range(max(0, int(cx - radius)), int(cx + radius) + 1):
            pixel = image.getpixel((x, y))
            total[0] += pixel[0]
            total[1] += pixel[1]
            total[2] += pixel[2]
            count += 1
    return (total[0] / count, total[1] / count, total[2] / count)


def cell_rect(col: int, row: int, shot: tuple[int, int], grid: tuple[int, int]):
    """整屏列/行 → 像素矩形（左, 上, 右, 下）。"""
    cw = shot[0] / grid[0]
    ch = shot[1] / grid[1]
    return (col * cw, row * ch, (col + 1) * cw, (row + 1) * ch)


def cell_quadrants(image: Any, rect: tuple[float, float, float, float]):
    """一格四个象限的平均色（顺序：左上、右上、左下、右下）。"""
    x0, y0, x1, y1 = rect
    w, h = x1 - x0, y1 - y0
    return [patch_mean(image, x0 + w * rx, y0 + h * ry) for rx, ry in QUADRANTS]

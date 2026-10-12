#!/usr/bin/env python3
"""PHOSPHOR 联机冒烟：同机起两个 `phosphor` 进程，验证 `phos.net` 的传输契约。

夹具卡带在 `tools/fixtures/net/`（dev-only，不随发行包）：一个开房（H）、一个加入（J，
先自动发现），核对：

* 宿主进入 hosting、客人进入 connected，双方都看到对方（对端列表 = 1）
* 发现生效（客人靠 `phos.net.discover` 找到房间并拿对端口）
* 消息双向送达（两边都收到对方的心跳）
* 对端 id 约定（主机 1、客人 2）
* 断开：客人退出后，宿主看到对端消失并收到 disconnected 事件

不需要图形环境（headless 也能联机）。用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/net_smoke.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from phos import Host, HostError, main_guard, reporter  # noqa: E402

CART = "../tools/fixtures/net"  # 相对构建目录（工作目录），dev-only 夹具


def debug(host: Host) -> dict:
    return host.state().get("debug") or {}


def run() -> int:
    report, _ = reporter("net smoke")
    try:
        a = Host(cart=CART, headless=True, timeout=30.0, extra=["--save-dir", "tests-out/net-a"])
        b = Host(cart=CART, headless=True, timeout=30.0, extra=["--save-dir", "tests-out/net-b"])
    except HostError as err:
        report.check(False, f"两个进程都能启动：{err}")
        return report.finish()

    try:
        a.step(2)
        b.step(2)

        # A 开房，等它绑定好监听，B 再加入
        a.key("h")
        a.step(5)
        b.key("j")

        connected = False
        for _ in range(120):
            a.step(10)
            b.step(10)
            da, db = debug(a), debug(b)
            if (da.get("connected") and db.get("connected")
                    and da.get("peer_count", 0) >= 1 and db.get("peer_count", 0) >= 1
                    and da.get("received", 0) > 0 and db.get("received", 0) > 0):
                connected = True
                break

        da, db = debug(a), debug(b)
        report.check(da.get("role") == "host", f"A 是主机（role={da.get('role')}）")
        report.check(db.get("role") == "client", f"B 是客人（role={db.get('role')}）")
        report.check(connected, "两端连上并互收心跳")
        report.check(da.get("self_id") == 1, f"主机对端 id = 1（实为 {da.get('self_id')}）")
        report.check(db.get("self_id") == 2, f"客人对端 id = 2（实为 {db.get('self_id')}）")
        report.check(da.get("peer_count") == 1, f"A 看到 1 个对端（实为 {da.get('peer_count')}）")
        report.check(db.get("peer_count") == 1, f"B 看到 1 个对端（实为 {db.get('peer_count')}）")
        report.check(db.get("join_discovered") == 1, "B 靠局域网发现找到房间")
        report.check(da.get("received", 0) > 0 and db.get("received", 0) > 0,
                     f"消息双向送达（A 收 {da.get('received')}、B 收 {db.get('received')}）")
        report.check(da.get("last_kind") == "beat" and db.get("last_kind") == "beat",
                     "收到的消息类型是卡带自定义的 kind")

        # B 退出：A 应看到对端消失并收到 disconnected 事件
        b.close()
        left = False
        for _ in range(40):
            a.step(10)
            da = debug(a)
            if da.get("peer_count") == 0 and da.get("disconnects", 0) >= 1:
                left = True
                break
        report.check(left, "客人退出后，宿主看到对端消失并收到 disconnected 事件")
    finally:
        try:
            a.close()
        except Exception:  # noqa: BLE001
            pass

    report.check(a.exited_cleanly, "宿主干净退出（未被强杀）")
    return report.finish()


if __name__ == "__main__":
    main_guard(run)

#!/usr/bin/env python3
"""PHOSPHOR 联机冒烟：同机起两个 `phosphor` 进程，验证 `phos.net` 的传输契约。

夹具卡带在 `tools/fixtures/net/`（dev-only，不随发行包）：一个开房（H）、一个加入（J，
先自动发现），核对：

* 宿主进入 hosting、客人进入 connected，双方都看到对方（对端列表 = 1）
* 发现生效（客人靠 `phos.net.discover` 找到房间并拿对端口）
* 发现去重（同机广播 + 回环各答一次，只该列出一个房间）
* `set_room({open})`：主机开局后置 false，搜索方据 `open` 判断能否加入
* 消息双向送达（两边都收到对方的心跳）
* 对端 id 约定（主机 1、客人 2）
* 断开：客人退出后，宿主看到对端消失并收到 disconnected 事件
* 三节点星型：客户端之间无 socket，靠主机转发；跨过心跳超时窗口后，客户端**不会**
  把"已知对端"误判掉线

不需要图形环境（headless 也能联机）。用法（工作目录必须是含 phosphor.exe 的构建目录）::

    cd build
    python ../tools/net_smoke.py
"""

from __future__ import annotations

import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from phos import Host, HostError, main_guard, reporter  # noqa: E402

# 夹具卡带是 dev-only（不随发行包同步进 build/），用**相对本脚本的绝对路径**定位：
# 早先写成相对构建目录（"../tools/fixtures/net"），一旦构建目录不在仓库根下（out-of-tree
# 构建）就解析不到 → 主机"启动即退出"。改成绝对路径后，构建目录放哪都稳
CART = str(Path(__file__).resolve().parent / "fixtures" / "net")


def debug(host: Host) -> dict:
    return host.state().get("debug") or {}


def check_three_nodes(report) -> None:
    """星型三节点：客户端之间没有 socket，消息只能靠主机转发。

    曾有缺陷：客户端会把从 peer_add 得知的"已知对端"也拿去发心跳，约 5 秒（kPeerTimeoutMs）
    后必然误判它掉线。这里起三个进程、跨过超时窗口，验证已知对端不再被误判。
    """
    hosts: list[Host] = []
    try:
        hosts = [
            Host(cart=CART, headless=True, timeout=30.0, extra=["--save-dir", "tests-out/net-3a"]),
            Host(cart=CART, headless=True, timeout=30.0, extra=["--save-dir", "tests-out/net-3b"]),
            Host(cart=CART, headless=True, timeout=30.0, extra=["--save-dir", "tests-out/net-3c"]),
        ]
        for h in hosts:
            h.step(2)
        hosts[0].key("h")
        hosts[0].step(8)
        hosts[1].key("j")
        hosts[2].key("j")

        full = False
        for _ in range(150):
            for h in hosts:
                h.step(6)
            if all(debug(h).get("peer_count", 0) >= 2 for h in hosts):
                full = True
                break
        report.check(full, "三节点星型：每端都看到另外两个对端")

        time.sleep(5.5)  # 跨过 kPeerTimeoutMs(5s)：已知对端本不该触发超时
        for _ in range(30):
            for h in hosts:
                h.step(6)
        db, dc = debug(hosts[1]), debug(hosts[2])
        report.check(db.get("disconnects", 0) == 0 and dc.get("disconnects", 0) == 0,
                     "客户端没有把已知对端误判掉线"
                     f"（B disconnects={db.get('disconnects')}, C disconnects={dc.get('disconnects')}）")
        report.check(db.get("peer_count", 0) >= 2 and dc.get("peer_count", 0) >= 2,
                     "跨过超时窗口后，客户端对端数仍为 2")
    except HostError as err:
        report.check(False, f"三节点用例启动失败：{err}")
    finally:
        for h in hosts:
            try:
                h.close()
            except Exception:  # noqa: BLE001
                pass


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

        # 发现去重：同机主机会同时收到广播查询与回环查询、各答一次；同一房间只该列一条
        b.key("d")
        b.step(30)
        report.check(debug(b).get("found_count") == 1,
                     f"发现去重：只列出一个房间（实为 {debug(b).get('found_count')}）")

        # set_room({open})：开局后置 false，搜索方据 open 提示"游戏中"并拒绝加入
        a.key("o")
        a.step(10)
        b.key("d")
        b.step(30)
        report.check(debug(b).get("found_open") == 0, "set_room(open=false) 后，发现结果 open=false")
        a.key("o")
        a.step(10)
        b.key("d")
        b.step(30)
        report.check(debug(b).get("found_open") == 1, "set_room(open=true) 后，发现结果 open=true")

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
    check_three_nodes(report)
    return report.finish()


if __name__ == "__main__":
    main_guard(run)

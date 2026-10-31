#!/usr/bin/env python3
"""性能预算报告：逐张出厂卡带测 update / draw / merge 的耗时分布。

不是门禁（机器负载会影响绝对值），而是回答"这个改动有没有让某张卡带突然变慢"：
默认跑全部出厂卡带，按 p95 update 排序打印，超过单帧预算的项标出来。

口径：
* headless + 控制通道单步驱动（不锁 60Hz、不受显示器影响）；
* 跳过前 30 帧（加载/首帧编译），每 3 帧采样一次，共 60 个样本；
* update/draw 取 state.query 的 cart.update_ms / cart.draw_ms（卡带 update/draw 的实测耗时），
  merge 取 merge_ms（未建层时为 0）。

用法（在含 phosphor.exe 的构建目录）：
    python ../tools/perf_budget.py                 # 全部出厂卡带
    python ../tools/perf_budget.py --cart snake    # 单张
    python ../tools/perf_budget.py --json          # 机器可读
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from phos import Host, main_guard, reporter  # noqa: E402

BUDGET_MS = 1000.0 / 60.0  # 单逻辑帧预算（60Hz）
WARN_RATIO = 0.5           # p95 超过预算一半就提示（留出余量给主机自身与渲染）
WARMUP_FRAMES = 30
SAMPLE_EVERY = 3
SAMPLES = 60


def percentile(values: list[float], ratio: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, round((len(ordered) - 1) * ratio)))
    return ordered[index]


def measure(cart: str) -> dict:
    samples = {"update": [], "draw": [], "merge": []}
    label = Path(cart).name
    with Host(cart=cart, headless=True, extra=("--seed", "1")) as host:
        host.step(WARMUP_FRAMES)
        for _ in range(SAMPLES):
            host.step(SAMPLE_EVERY)
            state = host.state()
            info = state.get("cart") or {}
            samples["update"].append(float(info.get("update_ms", 0.0)))
            samples["draw"].append(float(info.get("draw_ms", 0.0)))
            samples["merge"].append(float(state.get("merge_ms", 0.0)))
    result = {"cart": label}
    for key, values in samples.items():
        result[key] = {
            "p50": round(percentile(values, 0.50), 3),
            "p95": round(percentile(values, 0.95), 3),
            "max": round(max(values) if values else 0.0, 3),
        }
    result["update_peak"] = result["update"]["max"]
    return result


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 性能预算报告")
    parser.add_argument("--cart", help="只测一张（card id 或目录）；缺省跑全部出厂卡带")
    parser.add_argument("--json", action="store_true", help="输出 JSON")
    args = parser.parse_args()

    report, _ = reporter("perf budget")
    carts: list[str]
    if args.cart:
        carts = [args.cart]
    else:
        carts = sorted(str(p) for p in Path("carts").iterdir() if (p / "manifest.lua").is_file())
    if not carts:
        print("perf budget: 找不到卡带（请在构建目录运行）")
        return 1

    results = []
    for cart in carts:
        try:
            results.append(measure(cart))
        except Exception as error:  # noqa: BLE001 单卡失败不该毁掉整份报告
            print(f"  FAIL {cart}: {error}")
            continue

    results.sort(key=lambda item: item["update"]["p95"], reverse=True)
    warnings = []
    for item in results:
        if item["update"]["p95"] > BUDGET_MS * WARN_RATIO:
            warnings.append(item["cart"])

    if args.json:
        print(json.dumps({"budget_ms": round(BUDGET_MS, 3), "warnings": warnings,
                          "carts": results}, ensure_ascii=False, indent=1))
    else:
        print(f"{'cart':12} {'update p50':>10} {'p95':>7} {'max':>7} "
              f"{'draw p95':>8} {'merge p95':>9}")
        for item in results:
            print(f"{item['cart']:12} {item['update']['p50']:10.2f} {item['update']['p95']:7.2f} "
                  f"{item['update']['max']:7.2f} {item['draw']['p95']:8.2f} "
                  f"{item['merge']['p95']:9.2f}")
        print()
        print(f"单帧预算 {BUDGET_MS:.2f} ms；提示线 = 预算的 {int(WARN_RATIO * 100)}%")
        if warnings:
            print("超过提示线：" + ", ".join(warnings))
        else:
            print("全部卡带 p95 update 均在提示线内")
    report.check(bool(results), f"完成 {len(results)} 张卡带的采样")
    return report.finish()


if __name__ == "__main__":
    main_guard(main)
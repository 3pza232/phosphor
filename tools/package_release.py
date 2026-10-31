#!/usr/bin/env python3
"""发行打包：把构建目录收成一个可直接分发的 zip（含清单与校验）。

与 release_check 的分工：release_check 回答"能不能发"（版本/CHANGELOG/门禁/基线），
本脚本回答"发出去的东西长什么样"——只读收集构建目录里的运行包，压成
`dist/phosphor-<version>-win64.zip`，并在 zip 根写入 README.txt 与 MANIFEST.txt
（逐文件字节数 + SHA-256）。构建目录只读：本脚本不往里写任何东西。

收集是**白名单**而不是"全拷再排除"：
  - 根：`phosphor.exe`、`*.dll`（MinGW 静态链接时没有）
  - 目录：`carts/` `theme/` `devkit/` `mods/` `docs/`
于是 `tests/`、`saves/`、`config.json`、`recent.txt`、日志/临时物、`*.a`、CMake 产物、
开发脚本天然进不了包；写完 zip 后还会再核对一遍，确认没有这些名字混进来。

版本默认读 `src/core/version.hpp` 的 `kVersion`，并运行 `phosphor.exe --version` 对表；
两者不一致直接失败——发出去的包不能和构建产物对不上。

用法（仓库根或 tools/ 下均可）::

    python tools/package_release.py                              # dist/phosphor-<version>-win64.zip
    python tools/package_release.py --build build-dev            # 换构建目录
    python tools/package_release.py --out dist/x.zip --force     # 覆盖同名 zip
"""

from __future__ import annotations

import argparse
import hashlib
import re
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

HERE = Path(__file__).resolve().parent
REPO = HERE.parent

#: 收集白名单：根文件 + 内容树 + 仓库根的法律/说明文件
ROOT_FILES = ("phosphor.exe",)
REPO_FILES = ("LICENSE", "CHANGELOG.md", "README.md")
CONTENT_DIRS = ("carts", "theme", "devkit", "mods", "docs")
DLL_GLOB = "*.dll"

#: 明确不进包的东西（白名单天然排除；写完 zip 后再核对一遍，防止收集逻辑被改坏）
EXCLUDED = ("tests/", "saves/", "config.json", "recent.txt")

VERSION_RE = re.compile(r'kVersion\s*=\s*"([0-9]+\.[0-9]+\.[0-9]+)"')
EXE_VERSION_RE = re.compile(r"PHOSPHOR\s+([0-9]+\.[0-9]+\.[0-9]+)")


class PackageError(Exception):
    """打包前置条件或校验失败（消息直接给用户看）。"""


def human_size(size: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024:
            return f"{size:.1f} {unit}"
        size /= 1024
    return f"{size:.1f} TB"


def display(path: Path) -> str:
    try:
        return path.relative_to(REPO).as_posix()
    except ValueError:
        return str(path)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def source_version() -> str:
    """版本号唯一来源：src/core/version.hpp 的 kVersion。"""
    header = REPO / "src" / "core" / "version.hpp"
    match = VERSION_RE.search(header.read_text(encoding="utf-8", errors="replace"))
    if match is None:
        raise PackageError(f"在 {display(header)} 里找不到 kVersion")
    return match.group(1)


def built_version(exe: Path) -> str:
    """跑一次 --version：既取构建产物版本，也证明这个 exe 在本机可执行。"""
    with tempfile.TemporaryDirectory() as temp:
        try:
            proc = subprocess.run([str(exe), "--version"], cwd=temp, capture_output=True,
                                  text=True, encoding="utf-8", errors="replace", timeout=60,
                                  check=False)
        except (OSError, subprocess.TimeoutExpired) as err:
            raise PackageError(f"无法执行 {display(exe)}：{err}") from err
    match = EXE_VERSION_RE.search(proc.stdout)
    if proc.returncode != 0 or match is None:
        detail = (proc.stderr or proc.stdout).strip().splitlines()
        raise PackageError(f"{exe.name} --version 不可用（exit {proc.returncode}）："
                           f"{detail[0] if detail else '无输出'}")
    return match.group(1)


def collect(build: Path) -> list[tuple[Path, str]]:
    """返回 (源文件, zip 内相对路径)，按包内路径排序。"""
    items: list[tuple[Path, str]] = []
    for name in ROOT_FILES:
        source = build / name
        if not source.is_file():
            raise PackageError(f"构建目录缺少 {name}：{display(build)}（先构建再打包）")
        items.append((source, name))
    for dll in sorted(build.glob(DLL_GLOB)):
        items.append((dll, dll.name))
    for name in REPO_FILES:
        source = REPO / name
        if source.is_file():
            items.append((source, name))
    for name in CONTENT_DIRS:
        root = build / name
        if not root.is_dir():
            raise PackageError(f"构建目录缺少 {name}/：{display(build)}（assemble_package 会同步内容）")
        for path in sorted(root.rglob("*")):
            if path.is_file():
                items.append((path, f"{name}/{path.relative_to(root).as_posix()}"))
    return sorted(items, key=lambda item: item[1])


def manifest_text(version: str, items: list[tuple[Path, str]]) -> tuple[str, int]:
    lines = [f"# PHOSPHOR {version} win64 文件清单",
             "# SHA-256                                          字节数  相对路径"]
    total = 0
    for source, arcname in items:
        size = source.stat().st_size
        total += size
        lines.append(f"{sha256_of(source)}  {size:9d}  {arcname}")
    lines.append(f"# 合计：{len(items)} 个文件，{total} 字节（未压缩）")
    return "\n".join(lines) + "\n", total


def readme_text(version: str, count: int, total: int) -> str:
    return "\n".join([
        f"PHOSPHOR {version} —— 免安装运行包（win64）",
        "",
        "怎么玩",
        "  解压后双击 phosphor.exe。存档与设置生成在 exe 旁边（saves/、config.json），",
        "  整个目录可以拷到任意位置或 U 盘。",
        "",
        "版本与许可",
        "  CHANGELOG.md  本版可见变化",
        "  LICENSE       许可证",
        "",
        "内容",
        "  carts/    出厂卡带（卡带架扫描这里）",
        "  theme/    内容包：skin / palette / boot / shelf / sound / font / icon",
        "  devkit/   卡带模板、示例与 phos.lua 注解",
        "  mods/     覆盖层 Mod",
        "  docs/     玩家手册 / 卡带作者手册 / API 参考 / 格式与内容包",
        "",
        "包内容",
        f"  文件数：{count}（另加本 README.txt 与 MANIFEST.txt）",
        f"  解压后大小：{human_size(total)}",
        "  校验：MANIFEST.txt 逐文件给出字节数与 SHA-256，可用它核对解压结果。",
        "",
        "不含",
        "  tests/、saves/、config.json、recent.txt、日志与开发脚本——首次运行自动生成。",
        "",
    ])


def write_zip(out: Path, items: list[tuple[Path, str]], readme: str, manifest: str) -> None:
    with zipfile.ZipFile(out, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        archive.writestr("README.txt", readme)
        archive.writestr("MANIFEST.txt", manifest)
        for source, arcname in items:
            archive.write(source, arcname)


def verify_zip(out: Path, items: list[tuple[Path, str]]) -> None:
    with zipfile.ZipFile(out) as archive:
        bad = archive.testzip()
        names = set(archive.namelist())
    if bad is not None:
        raise PackageError(f"zip 内 {bad} 的 CRC 校验不通过")
    expected = {"README.txt", "MANIFEST.txt"} | {arcname for _, arcname in items}
    missing = expected - names
    if missing:
        raise PackageError(f"zip 缺少 {len(missing)} 个文件，例如 {sorted(missing)[0]}")
    leaks = [name for name in names if name.startswith(EXCLUDED)]
    if leaks:
        raise PackageError(f"zip 混进了不该发的 {len(leaks)} 个文件，例如 {sorted(leaks)[0]}")


def main() -> int:
    parser = argparse.ArgumentParser(description="PHOSPHOR 发行打包（zip + 清单）")
    parser.add_argument("--build", help="构建目录（默认仓库根下的 build/）")
    parser.add_argument("--version", help="版本号（默认读 src/core/version.hpp，并与 exe 对表）")
    parser.add_argument("--out", help="输出 zip 路径（默认 dist/phosphor-<version>-win64.zip）")
    parser.add_argument("--force", action="store_true", help="覆盖已存在的同名 zip")
    args = parser.parse_args()

    build = Path(args.build).resolve() if args.build else REPO / "build"
    version = args.version or source_version()
    out = Path(args.out).resolve() if args.out else REPO / "dist" / f"phosphor-{version}-win64.zip"
    if out.exists() and not args.force:
        raise PackageError(f"{display(out)} 已存在（拒绝覆盖；确认要换就加 --force）")
    if build in out.parents:
        raise PackageError(f"输出不能写进构建目录（只读收集）：{display(out)}")
    exe = build / "phosphor.exe"
    if not exe.is_file():
        raise PackageError(f"找不到 {display(exe)}（先构建，或用 --build 指定构建目录）")

    print(f"PHOSPHOR 打包：{display(build)} → {display(out)}\n")

    binary_version = built_version(exe)
    if binary_version != version:
        raise PackageError(f"构建产物版本 {binary_version} 与版本源 {version} 不一致：先重建再打包")
    print(f"  ok   phosphor.exe 可执行，版本 {version}（与 src/core/version.hpp 一致）")

    items = collect(build)
    dlls = sum(1 for _, arcname in items if arcname.endswith(".dll"))
    print(f"  ok   收集 {len(items)} 个文件（{dlls} 个 dll）")
    print(f"       排除 {' '.join(EXCLUDED)}，以及日志/临时物/*.a/CMake 产物/开发脚本（白名单收集）")

    manifest, total = manifest_text(version, items)
    print(f"  ok   清单 MANIFEST.txt：{len(items)} 条 SHA-256")

    out.parent.mkdir(parents=True, exist_ok=True)

    try:
        write_zip(out, items, readme_text(version, len(items), total), manifest)
        verify_zip(out, items)
    except (PackageError, OSError):
        out.unlink(missing_ok=True)
        raise

    zip_size = out.stat().st_size
    print(f"  ok   zip 完整性（CRC）通过：{len(items) + 2} 项")
    print()
    print(f"输出：{display(out)}")
    print(f"大小：{human_size(zip_size)}（压缩后 / {human_size(total)} 原始）")
    print(f"SHA-256：{sha256_of(out)}")
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except PackageError as err:
        print(f"FAIL {err}", file=sys.stderr)
        sys.exit(2)

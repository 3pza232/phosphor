#!/usr/bin/env python3
"""PHOSPHOR 依赖铁律门禁：机械核查 src/ 的 include 方向。

规则与 `docs/engine/architecture.md` 第一节逐条对应（那里要求"每条都写成可机械核查的形式"）：

    lua     sol2 / Lua 头只允许出现在 api/ cart/ pack/ devkit/
    gl      glad / OpenGL / GLFW 头只允许出现在 render/ 与 platform/window.cpp
    core    core/ 不得 include api/ cart/ pack/ shell/ agent/ net/（app.* 是组装点，见白名单）
    render  render/ 不得 include shell/ api/ cart/ pack/ agent/ net/
    shell   shell/ 不得 include cart/ pack/ agent/ net/

核查对象是 include 的**书写形式**：它回答"这个模块直接依赖了谁"，不解析宏、不跟 extern 头
的传递包含。已存在的违规收在 WHITELIST（逐条写明原因与 TODO），只放宽
"规则 + 文件 + include" 这一组；同一文件里新增的越界包含照旧判红。
白名单条目对应的违规消失后会提示删除。

用法（任意工作目录；仓库根按脚本位置定位）::

    python tools/check_includes.py        # 有违规 → 非 0 退出
    python tools/check_includes.py -v     # 另列出白名单放行项与原因
"""

from __future__ import annotations

import argparse
import fnmatch
import re
import sys
from pathlib import Path
from typing import Callable, NamedTuple

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "src"

INCLUDE_RE = re.compile(r'^\s*#\s*include\s*[<"]([^>"]+)[>"]')
SOURCE_SUFFIXES = frozenset({".cpp", ".hpp", ".h", ".inl"})

#: src/ 的一级目录即模块；include 写成 "<模块>/<文件>" 就是跨模块依赖
MODULES = frozenset(p.name for p in SRC.iterdir() if p.is_dir()) if SRC.is_dir() else frozenset()

LUA_DIRS = ("api/", "cart/", "pack/", "devkit/")
LUA_HEADERS = frozenset({"sol.hpp", "lua.hpp", "lua.h", "lauxlib.h", "lualib.h", "luaconf.h"})
GL_HOMES = ("render/",)
GL_FILES = frozenset({"platform/window.cpp"})
GL_HEADERS = frozenset({"glad.h"})
GL_PREFIXES = ("glad/", "GLFW/", "GL/")
CORE_FORBIDDEN = ("api", "cart", "pack", "shell", "agent", "net")
RENDER_FORBIDDEN = ("shell", "api", "cart", "pack", "agent", "net")
SHELL_FORBIDDEN = ("cart", "pack", "agent", "net")


class Rule(NamedTuple):
    key: str
    what: str
    violated: Callable[[str, str], bool]


def is_lua(header: str) -> bool:
    return header in LUA_HEADERS or header.startswith("sol/")


def is_gl(header: str) -> bool:
    return header in GL_HEADERS or header.startswith(GL_PREFIXES)


def hits(header: str, modules: tuple[str, ...]) -> bool:
    """include 的目标是否落在给定模块里（只看书写形式的第一段目录）。"""
    top = header.split("/", 1)[0]
    return top in MODULES and top in modules


def inside(rel: str, homes: str | tuple[str, ...]) -> bool:
    return rel.startswith(homes)


RULES = (
    Rule("lua", "sol2/Lua 头只允许出现在 api/ cart/ pack/ devkit/",
         lambda rel, header: is_lua(header) and not inside(rel, LUA_DIRS)),
    Rule("gl", "glad/GL/GLFW 头只允许出现在 render/ 与 platform/window.cpp",
         lambda rel, header: is_gl(header) and not inside(rel, GL_HOMES) and rel not in GL_FILES),
    Rule("core", "core/ 不得 include api/ cart/ pack/ shell/ agent/ net/",
         lambda rel, header: inside(rel, "core/") and hits(header, CORE_FORBIDDEN)),
    Rule("render", "render/ 不得 include shell/ api/ cart/ pack/ agent/ net/",
         lambda rel, header: inside(rel, "render/") and hits(header, RENDER_FORBIDDEN)),
    Rule("shell", "shell/ 不得 include cart/ pack/ agent/ net/",
         lambda rel, header: inside(rel, "shell/") and hits(header, SHELL_FORBIDDEN)),
)

#: 既存违规的例外：(规则 key, 源文件 pattern, include pattern, 原因与 TODO)，pattern 用 fnmatch。
#: 只放宽到这一组，不整文件/整目录豁免。
WHITELIST = (
    ("core", "core/app*", "*",
     "组装点例外：architecture.md 第一节第 1 条明订 core/app.* 必须知道所有层才能把它们"
     "接起来；core/ 其余单元仍受约束"),
    ("shell", "shell/shell.hpp", "cart/cartridge.hpp",
     "外壳持有 vector<CartInfo> 供卡带架显示，实际只用 CartInfo（cart_info.hpp），"
     "此处过度包含还连带拉起 sol2。TODO：收窄为 cart/cart_info.hpp；CartInfo 下沉 core 后彻底合规"),
    ("shell", "shell/shelf_view.hpp", "cart/cartridge.hpp",
     "同 shell.hpp：ShelfView 只读 CartInfo。TODO：收窄为 cart/cart_info.hpp"),
    ("shell", "shell/shelf_search.hpp", "cart/cart_info.hpp",
     "搜索匹配要读 CartInfo 的 id/name 字段；它是纯数据，但按分层仍属 cart/"),
    ("shell", "shell/tape_view.hpp", "cart/save_store.hpp",
     "只用 SaveStore 的三个容量常量算输入缓冲上限。TODO：常量移入 core，界面不再知道存档实现"),
)


class Allowance(NamedTuple):
    rel: str
    line: int
    header: str
    reason: str


def allowed_by(rule_key: str, rel: str, header: str) -> int | None:
    for index, (key, rel_pattern, header_pattern, _reason) in enumerate(WHITELIST):
        if (key == rule_key
                and fnmatch.fnmatchcase(rel, rel_pattern)
                and fnmatch.fnmatchcase(header, header_pattern)):
            return index
    return None


def main() -> int:
    parser = argparse.ArgumentParser(description="核查 src/ 的 include 方向（架构依赖铁律）")
    parser.add_argument("-v", "--verbose", action="store_true", help="列出白名单放行项与原因")
    args = parser.parse_args()

    if not SRC.is_dir():
        print(f"找不到源码目录：{SRC}", file=sys.stderr)
        return 2

    print("PHOSPHOR 依赖门禁：include 方向（对照 docs/engine/architecture.md 第一节）\n")

    violations: list[tuple[str, int, str, Rule]] = []
    allowances: list[Allowance] = []
    used: set[int] = set()
    files = 0
    includes = 0
    for path in sorted(SRC.rglob("*")):
        if path.suffix not in SOURCE_SUFFIXES:
            continue
        files += 1
        rel = path.relative_to(SRC).as_posix()
        text = path.read_text(encoding="utf-8-sig", errors="replace")
        for number, line in enumerate(text.splitlines(), 1):
            match = INCLUDE_RE.match(line)
            if match is None:
                continue
            includes += 1
            header = match.group(1)
            for rule in RULES:
                if not rule.violated(rel, header):
                    continue
                index = allowed_by(rule.key, rel, header)
                if index is None:
                    violations.append((rel, number, header, rule))
                else:
                    used.add(index)
                    allowances.append(Allowance(rel, number, header, WHITELIST[index][3]))

    for rel, number, header, rule in violations:
        print(f'  FAIL src/{rel}:{number}: include "{header}" — {rule.what}')
    if args.verbose:
        for entry in allowances:
            print(f'  allow src/{entry.rel}:{entry.line}: include "{entry.header}" — {entry.reason}')

    for index, (key, rel_pattern, header_pattern, _reason) in enumerate(WHITELIST):
        if index not in used:
            print(f"  警告：白名单条目已失效（对应违规已消失，请删除）：[{key}] "
                  f"{rel_pattern} → {header_pattern}")

    print()
    if violations:
        print(f"  白名单放行 {len(allowances)} 条（-v 看原因）")
        print(f"依赖门禁: {len(violations)} 处违规")
        return 1
    print(f"  ok   {files} 个文件 / {includes} 处 include：{len(RULES)} 条依赖规则全部通过")
    print(f"  白名单放行 {len(allowances)} 条（-v 看原因）")
    print("依赖门禁: 通过")
    return 0


if __name__ == "__main__":
    sys.exit(main())

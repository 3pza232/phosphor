# 发布检查

> 开发门禁是 `tools/run_checks.py`（每次提交跑）；这里是**发布前**的硬检查与人工项。
> 一条命令：`python tools/release_check.py`（在仓库根或 `build/` 下均可）。

## 自动检查（release_check.py）

- 构建产物存在（`build/phosphor.exe`、`build/phosphor_tests.exe`）。
- `--version` 可读，且当前版本出现在 `CHANGELOG.md`。
- 工作树干净（`--allow-dirty` 可跳过）。
- 14 项无头门禁、`--check-api`、`--check-packs --root package`、文本基线、像素基线。
- 性能预算只报告（机器负载会影响绝对值，不作为发布门槛）。

## 构建矩阵（人工/CI）

| 配置 | 命令 | 说明 |
|---|---|---|
| Release（发行） | `cmake --preset release && cmake --build --preset release` | 产物在 `build/`，可直接分发 |
| Dev（测试） | `cmake --preset dev` | 开测试目标、带调试信息 |
| Sanity（容器断言） | `cmake --preset sanity` | Release + PHOSPHOR_SANITY：容器边界断言/栈保护，慢 |
| 干净重建 | 删 `build/` 后重跑 release | 验证内容同步（carts/docs/theme/devkit/mods） |
| Debug（断言） | `cmake --preset debug && cmake --build --preset debug` | `build-debug/`：NDEBUG 关掉、assert 生效，跑一遍单测/门禁 |

发布目录必须包含：`phosphor.exe`、`carts/ theme/ devkit/ mods/ docs/`、`lib*.dll`（如有）；打包见下节。
仓库根的 `LICENSE` / `CHANGELOG.md` / `README.md` 由 `tools/package_release.py` 一并放进发行 zip。
CI 额外跑 `--gui` 门禁（gl/window），release_check 只跑无头（跨机稳定）。

## 打包（发行 zip）

把 `build/` 里的运行包收成一个可直接分发的 zip（只读收集，不改 `build/`；输出在 `dist/`）：

    python tools/package_release.py                           # dist/phosphor-<version>-win64.zip
    python tools/package_release.py --out dist/x.zip --force  # 换输出路径 / 覆盖同名 zip
    python tools/package_release.py --build build-dev         # 换构建目录

- 收：`phosphor.exe`、构建目录根的 `*.dll`（如有）、`carts/ theme/ devkit/ mods/ docs/`。
- 不收：`tests/`、`saves/`、`config.json`、`recent.txt`、日志/临时物、`*.a`、CMake 产物、开发脚本——白名单收集天然排除，写完 zip 还会再核对一遍。
- zip 根含 `README.txt`（玩法与包内容）与 `MANIFEST.txt`（逐文件字节数 + SHA-256）；脚本打印 zip 总大小与 SHA-256。
- 版本默认读 `src/core/version.hpp`，并跑 `phosphor.exe --version` 对表；不一致直接失败（避免发出旧构建）。
- 同名 zip 已存在时拒绝覆盖，`--force` 才覆盖。

发布时把脚本打印的 zip SHA-256 贴进 Release 说明，供下载者核对。

## 人工验收

1. 双击 exe（或从任意目录启动）：卡带架、主题、开机动画、音效/音乐、设置、F1 关于、F2 设置、
   `/` 搜索、F3 存档管理、F12 截图、磁带码、暂停/恢复。
2. 手柄（如接入）：方向/确认/取消/Start 与键盘一致；插拔不卡键。
3. 坏内容包：`--check-packs` 列出 error；删除/改坏 skin/sound 后启动有明确日志与回退，不崩。
4. 存档：v2 读写、槽位、旧 v1 档自动升级 + `.v1`、坏档只读、跨卡带拒绝。
5. 联机：`net_smoke.py` 两进程 + 发现；卡带 LAN 大厅手动一局。
6. 性能：`perf_budget.py` 全部卡带 p95 update 在提示线内；高密度塔防/弹幕手动观感。
7. 音质：高音量暂停/恢复/stop、master 突变、ducking、音乐状态查询无爆音/卡顿。

## 当前已知限制（发布说明需保留）

- 音频无 CI 设备/单测；流式采样、渲染三路径收口（FrameComposer）未完成。
- 像素 golden 非门禁（跨机字体差异）；JSON 解析保留宽松容错。
- towerdef 4096 字节/值上限在极后期可能逼近；`mods/towerdef-build-pause` 仍为整文件 fork。
- 设置模板/存档列表在极小屏或大量存档时需要滚动（后续）。

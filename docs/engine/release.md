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
| Dev（测试） | `cmake --preset dev` / `sanity` | 开测试目标、带调试信息 |
| 干净重建 | 删 `build/` 后重跑 release | 验证内容同步（carts/docs/theme/devkit/mods） |

发布目录必须包含：`phosphor.exe`、`carts/ theme/ devkit/ mods/ docs/`、`lib*.dll`（如有）。
CI 额外跑 `--gui` 门禁（gl/window），release_check 只跑无头（跨机稳定）。

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

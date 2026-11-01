# 验收清单（M0–M5）

> 本文件是 `docs/engine/roadmap.md` 的阶段验收视图：**每条结论都能落到命令或提交**。
> 详细缺陷证据见 `docs/engine/audit.md`；计划背景见 roadmap。最后更新：2026-11-01。

## 一键验收

在含构建产物的目录（`build/`）执行：

```sh
ninja -j16                                  # 构建
./phosphor_tests.exe                        # 143 用例 / 1,636 断言
python ../tools/run_checks.py --gui         # 14 项无头 + 2 项开窗门禁
./phosphor.exe --check-api                 # 150/150
./phosphor.exe --check-packs --root ../package   # 45 包 0 error / 0 warning
python ../tools/pixel_golden.py            # 10 场景像素基线（非门禁）
python ../tools/perf_budget.py             # 性能预算报告（非门禁）
```

当前基线：**14 门禁全绿、143 单测 / 1,636 断言、150/150 API、45 包 0/0、像素 10/10**。
性能预算（本机，headless）：12 张出厂卡带 p95 update 均 ≤ 3.18 ms（life 最高，预算 16.67 ms）。

## M0 止血与纠偏

- P0 全部关闭：C1/C2/C3/C4/C5/C6/C10/C11/C12/C13/C16、S5（头文件环）、K2（存档 v2）等，
  证据见 audit §3.1/§3.2。
- 门禁从 9 项扩到 14 项（includes/api/unit/control/draw/layer/ui/scene/toolkit/lint/packs/portable/cart/net），
  CI（Windows + MSYS2）构建 + 单测 + 门禁 + 性能/像素非门禁报告全绿。
- 文本 golden（shell 8 屏）与像素 golden（10 场景）成为后续所有迁移的对照物。

## M1 UI 内核

- `src/ui/` 组件层：element/layout/frame/theme/toast/screen_stack，声明式元素
  column/row/box/text/divider/spacer/list/stat/option/checkbox/field/bar/button/hint/table/grid/scroll。
- 布局：Box model、padding/margin/gap、grid cols、table 列宽/对齐、scroll 纵向/横向 + 视口裁剪 +
  焦点跟随 + 滚动条；按键重复（300ms + 3 帧/格）；焦点二维导航与模态捕获。
- 主题 token（颜色/字形/度量）与 `ui::ScreenStack`（push/pop/reset、模态标记、生命周期回调）。
- 契约：单测覆盖布局/焦点/滚动/嵌套/table/grid/field/IME；`ui_smoke.py` 进 run_checks；
  `pixel_golden.py` 10 场景非门禁留档。

## M2 外壳全量迁移

- 7 个外壳屏（boot/shelf/settings/paused/mods/tape/cart_error）由组件树绘制，Shell 退化为
  状态 + 数据 + 意图；`shell_golden.py` 8 个文本快照逐字节稳定。
- 迁移过程中发现并修复：压栈帧误关（scene_smoke 回归）、tape 坐标、字体/主题切换、搜索框 IME 等。
- 验收里"行数下降 ≥30%"与"2 套皮肤截图基线"未逐项量化——文本快照与像素基线承担了等价回归角色。

## M3 卡带声明式 UI + 场景栈

- `phos.ui.render`（元素/样式/焦点/事件/主题/`input=false`）、`phos.scene`（push/pop、modal、
  pause_world、audio_pause、生命周期）、`phos.ui.toast`、表格/网格/滚动/滚动条。
- 11 张旧卡带全部迁移 + 新增《视界线外》（12 张）：侧栏组件化、暂停换场景栈、排行榜换 `phos.score`、观测换 `phos.observe`、
  词表/格式化/存档走工具层；`--check-cart` 全部 0 error/0 warning。
- 场景栈：Cartridge 内的场景 push/pop 延后到安全点；卡带与外壳的输入/绘制边界由 HostContext 统一。

## M4 卡带工具层

- 存档 v2：`PHOSPHOR-SAVE 2` 容器（magic/版本/卡带 id/CRC32、原子写、旧档升级 + `.v1`、
  坏档只读、跨卡带拒绝）、值类型保真（文本/数字/布尔/表，深度 ≤8、非法值拒绝）、槽位 0..9。
- `phos.score`（TOP N/排序/截断/坏档容错）、`phos.observe`（函数字段/深度 4/单字段容错）、
  `phos.lang.shared`、`phos.text.score|clock|percent`、`phos.save` 表值。
- 静态检查：`--check-cart`（manifest/入口/隐式全局/screen.size/阻塞调用/观测声明）、
  `--check-packs`（六类内容包逐项 error/warn，退出码 2）。
- 联机：`discover_async`/`join_async`（不阻塞；`connect_failed` 带 reason），net_smoke 覆盖。

## M5 体验与子系统（核心完成，长期项持续）

已完成：
- 输入：全部已做——失焦释放、scroll 焦点跟随/滚动条、手柄、动作映射、按键重复参数化、**重绑定界面**（F4/config.input_bindings）。
- 音频：6ms 暂停/恢复/stop 淡出；声部优先级/抢占（48 + 8 尾巴）；三路总线（music/sfx/ui）；
  ducking；`music_state()`；主机事件音分档。
- 绘制/精灵：line/outline/circle（预裁剪/有界半径）+ Region 同名方法；sprite step/brightness/solid、
  UTF-8 字符键；table/Region 几何裁剪。
- 内容包：`--check-packs` 已进门禁（packs）。
- 工程：`perf_budget.py`/`pixel_golden.py`（非门禁）、run_checks `--json` + CI 门禁摘要。

长期 backlog（按 roadmap M5 的“持续、按季度排”，不阻塞本次目标）：
1. 音频：流式采样（大文件不整读）。
2. 渲染：`FrameView` 已统一 present/CPU 截图的组成决策（第一刀）；绘制列表与文本投影是下一步，
   需在像素 golden 下继续收口。
3. 绘制：粒子/转场原语。
4. 内容包：包预览（列表目前只有名字）；依赖/版本（`phos_api` 元数据）与热重载（F5）已做。
5. 契约：嵌套 scroll 滚动条同格覆盖的文档化；table 宽度“固定宽 + 自适应列吃余量”已钉住。
6. M6（生态/发行）明确不在本次目标内：只交付发行打包与发布检查。

## 已知残余风险

- 音频没有 CI 设备/单测：淡出/抢占/ducking/总线只能靠手动验收（步骤见各提交）。
- 像素 golden 不进 run_checks（跨机字体光栅化差异），由 CI 作为非门禁报告 + artifact 留档。
- JSON 解析仍有宽松容错（尾随逗号/裸控制字符），未按严格 RFC 8259 收紧；与控制通道/配置容错
  需一起决策。
- towerdef 的 4096 字节/值上限在极后期高密度局可能逼近（写失败与旧行为一致，不存盘不报错）；
  `mods/towerdef-build-pause` 仍为整文件 fork（默认关闭）。
- S1 已完成：BootSequence/TapeGlue 等已抽出，App 只剩组装根 + 主循环分派 + ImGui 调试台胶水。

## 完成判据

- [x] M0 P0 全关、14 门禁与 CI 绿
- [x] M1 UI 内核（含屏幕栈）与契约测试
- [x] M2 7 屏组件化 + 文本 golden 稳定
- [x] M3 声明式 UI/场景栈 + 11 卡迁移
- [x] M4 工具层（存档 v2/表值/槽位/score/observe/静态检查/异步联机）
- [x] M5 核心体验项（输入/音频/绘制/内容包/工程）；长期 backlog 见上，不阻塞本次目标
- [x] 验收文档化：本文件与 audit/roadmap 的最终对账

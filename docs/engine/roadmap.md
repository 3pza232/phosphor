# PHOSPHOR 演进路线图

> **定位**：引擎实现文档，不随发行包发布。现状与证据见 [audit.md](audit.md)；
> 本文件只回答"往哪走、按什么顺序走、怎么算走完了"。
>
> **一句话方向**：把主机从"一组手绘屏幕 + 一套绘制原语"升级为
> **"一套共享 UI 组件与场景模型 + 清晰边界 + 可执行门禁"**，
> 让外壳与卡带都只声明界面，让卡带作者只写玩法。

---

## 一、北极星与判断标准

**目标（按优先级）**

1. **界面只有一套**：外壳、卡带、内容包（卡带架样式、启动动画里的界面部分）都通过同一套
   组件描述界面；颜色/字形/度量来自同一套主题 token。
2. **卡带负担最小**：作者写玩法 + 声明式界面，不写排版、光标、滚动、弹窗、键位提示、
   存档编码、多语言查表。
3. **边界与真源**：每个子系统只有一个所有者、一个写入口、一条依赖方向；
   新增功能只改一处。
4. **可演进而非可重写**：旧卡带零改动继续运行；每次迁移都有文本/像素/契约基线兜底。

**判断标准（任何方向都按此排序）**

| 权重 | 维度 | 问题 |
|---|---|---|
| 1 | 影响面积 | 能删掉多少重复代码、覆盖多少屏/多少卡带 |
| 2 | 复用率 | 主机与卡带是否共用同一实现（而不是各写一遍） |
| 3 | 可验收 | 能否用单测/文本快照/像素基线/契约门禁证明"做完了且没回归" |
| 4 | 迁移成本 | 是否可逐屏切换、能否回滚、是否触碰确定性 |

**明确反对**：大爆炸重写、换引擎、为了"看起来专业"引入与字符网格不匹配的像素 GUI 框架。
现成的 Dear ImGui 只服务调试台（窗口、像素、非确定性），**不进入游戏界面路径**。

---

## 二、总体策略

五条工作流，A 先行为 B 清障，B 是主线，C/D 在其上落地，E 贯穿始终：

```
A 止血与边界（P0 / App / 真源 / 合成器）──► B UI 内核 ──► C UI 落地（外壳迁移 + 卡带 API + 场景）
                                              │
                                              ├──► D 卡带工具层（存档 v2 / 词表 / 观测 / lint）
                                              └──► E 工程治理与体验（CI / 基线 / 输入 / 音频 / 渲染统一）

A 必须先做（解除"UI 被耦合拖住"的风险）；B 是主线；C/D/E 在 B 的接口稳定后并行；
E 从 A 开始持续，不等其它阶段。
```

**兼容策略（贯穿所有阶段）**

- 旧 `phos.ui.*` 绘制函数与 `phos.screen/panel` 语义**不改、不删**；新能力只增。
- 新的声明式界面 API 以 `phos_api = 7` 门控；旧卡带（`phos_api ≤ 6`）路径逐字节不变。
- 外壳迁移是**内部重构**：对外行为由文本快照 + 像素基线 + 现有门禁（`window_smoke`、
  `agent_shell_demo`、`cart_smoke`）保证；逐屏切换、随时可回退。
- 迁移顺序从"读多写少"的屏开始（错误屏 → 设置 → 暂停 → Mod → 磁带码 → 卡带架），
  卡带架最后（它有内容包 painter 与搜索两个外部约束）。

---

## 三、阶段计划

### M0 止血与纠偏（1–2 周）

**目标**：把"会崩/会丢数据/会挂 agent"的问题先关掉，并把文档与实现拉回一致。

> **状态（2026-10-31）**：M0 基本完成。P0 已修 9 项（`C1 C2 C3 C4 C5 C10 C12 C13 C16`，
> 证据逐条见 `audit.md` §3.1）；**P0 已全部关闭**（C11 内容根随本轮修完，见 audit）。
> 绘制一致性按 `C7` 修复（`273d090`，`drawing.md` 已改为"两路同规则"）。CI 与基线见下表。

**交付**

| 项 | 内容 | 状态 |
|---|---|---|
| P0 修复 | `C1` boots 空表、`C2` 存档原子写、`C3` 配置原子写 + 转义、`C4` chunk name + traceback、`C5` 包脚本看门狗、`C6` `time.step` 在途回包取消语义、`C10` `Screen::blend` 边界、`C11` 内容根、`C12` 窗口退出码、`C13` JSON `\u` 转义、`C16` Lua `print` 重定向 | ✅ `C1 C2 C3 C4 C5 C6 C9 C10 C11 C12 C13 C16`、S5（头文件环已断）——**M0 的 P0 全部关闭**（证据见 `audit.md` §3.1/§3.2） |
| 合成器保真 | CPU 截图与 GL 对"续格/被覆盖格上的笔迹"给出一致结果，并加契约用例 | ✅ 已完成（`273d090`；`screen_image.cpp` 三条路径同 `pens` 趟，`drawing.md` 写明契约） |
| 文档纠偏 | 修正 `audit.md` §4 的 22 处漂移；在 `docs/engine/README.md` 登记本文件与体检文件 | ✅ 已完成（§4 逐条标"已修正 / 仍待代码修"；两份入口已加） |
| CI 骨架 | Windows（MinGW）+ Linux（GCC/Clang）构建 + `run_checks.py` + 单测；把 `--check-api` 与 include 方向纳入门禁；PR 必须绿 | ✅ 已完成（`.github/workflows/ci.yml`、`CMakePresets.json`；`run_checks.py` 无头 9 项含 `includes` / `api` / `ui`） |
| 基线先行 | 为外壳 7 个屏建立**文本快照**（`to_text()` 逐字节）；为 2 套皮肤建立截图基线 | ⚠ 文本快照 ✅（`tools/shell_golden.py` + `tests/golden/shell/`）；截图基线 ❌ |

**验收**：新增 6 个 P0 用例（boots 兜底、存档掉电模拟、配置转义、错误信息含文件、包脚本看门狗、`time.step` 取消）；
`run_checks.py` 与 CI 全绿；文本快照作为后续所有迁移的对照物。

**风险**：低。除 `C11` 内容根外都不改变外部行为。

### M1 UI 内核（3–4 周）

**目标**：建立 `src/ui/` —— 布局、控件、焦点、主题、裁剪、屏幕栈的**唯一实现**，
先用外壳两个屏做"真迁移"验证。

> **状态（2026-10-31）**：**主体已完成**。`src/ui/` 已落地（8 文件 1,310 行：
> `element` / `layout` / `frame` / `theme`——规划里的 widget/nav/screen 合并进
> element/layout/frame）；布局、控件 v1、焦点、主题 token、文本域已实装；
> **屏幕栈 `ScreenStack` 与 Modal 未做**（M3 一起补）。设置屏 + 错误屏已迁到组件树，
> `tools/shell_golden.py` 的文本快照守住迁移前后一致；单测 `tests/test_ui.cpp` 6 条
> （布局/焦点/滚动），`tools/ui_smoke.py` 已进 `run_checks`（9 项）。
> 剩余：Scroll/Grid/Toast、按键重复、屏幕栈、像素基线（Table 已补齐：`columns`/`rows`/`widths`/`col_align`，
> 表头下自动分隔线，列宽自适应并均摊余量）。

**交付**

| 项 | 内容 |
|---|---|
| 模块与新目录 | `src/ui/`：`context`（每帧构建、状态存储、事件）、`layout`、`widget`、`theme`（token）、`nav`（焦点/导航）、`screen`（屏/弹窗栈）、`widgets/*`；旧的 9 个绘制原语从 `core/ui.*` 移到 `ui/draw.*`（职责归位，include 全工程一次机械替换） |
| 布局 | Rect 代数（切分/内缩/对齐/权重）、`VBox/HBox/Grid/Scroll`、锚点（content/playfield/panel/层）、文本测量接入布局、溢出裁剪与省略策略 |
| 控件 v1 | `Label`、`Paragraph`、`Divider`、`Button`、`List`（光标/滚动/禁用/循环）、`StatRow`（标签+右对齐值）、`Table`（列对齐）、`OptionRow`（左右改值）、`Bar`、`Checkbox`、`TextField`（光标/IME/过滤/限长）、`Frame/Window`（不透明底板+标题+内容区）、`Footer/HintBar`、`Modal` |
| 焦点与输入 | 每屏焦点栈、顺序导航 + 二维导航、按键重复、确认/取消语义、模态捕获、消费语义（先焦点后全局）、`key_name` 自动提示 |
| 主题 | `ui::tokens`：颜色角色（`surface/panel/text/text_dim/accent/warning/danger/disabled/focus`）、字形集（边框/光标/滚动条）、度量（行高、内缩、间距）；来源 = skin（外壳）/ palette（卡带）派生 + 可选 `ui` 内容包覆盖 |
| 屏幕栈 | `ui::ScreenStack`：push/pop、模态、输入捕获、音频暂停钩子、每屏生命周期 |
| 契约测试 | 单测 ≥30（布局切分、焦点遍历、滚动夹紧、文本域编辑、模态陷阱、id 稳定）；`tools/ui_smoke.py` 契约 ≥10 项；外壳"错误屏 + 设置屏"迁移前后文本逐字节一致 |

**验收**：设置屏与错误屏由组件描述生成，`settings_view.cpp` 不再有手工坐标；
两项文本快照不变；单测与契约测试进 CI；绘制调用数不高于迁移前。

**风险**：中。控件契约一旦定错，M2 会返工——所以 M1 只做"外壳需要的 + 卡带侧栏需要的"，
其余控件放到 M3。

### M2 外壳全量迁移（2–3 周）

**目标**：外壳 7 屏全部由组件树描述，`Shell` 退化为"状态 + 数据 + 意图"，
不再持有任何版面常量。

> **状态（2026-10-31）**：**进行中**。设置屏与错误屏已完成迁移；暂停 / Mod / 磁带码 /
> 卡带架 / 开机自检正陆续接到组件树（另一位协作者迁移中），`paused` / `mods` 两屏的文本
> 基线待整合后由 Lead 重新生成。

**交付**

| 屏 | 迁移后（组件树） |
|---|---|
| 错误屏 | `Page` + `Title` + `Paragraph` + `HintBar` |
| 设置屏 | `Page` + `Section`×3 + `OptionRow/Stepper/VolumeRow` + 字体预览 `Frame+Paragraph` + `HintBar` |
| 暂停菜单 | `Modal` + `List` + `HintBar` |
| Mod 管理器 | `Modal` + `CheckList`（滚动/禁用/确认行） |
| 磁带码 | `Page` + `TextField`（hex/分页/滚动）+ `StatusLine` |
| 卡带架 | `Page` + `List/Grid`（内置样式）+ 搜索 `TextField` 浮层；内容包 painter 仍可接管内容区 |
| 开机自检 | 保留特效式绘制，但文字与光标用 `draw` 原语，不再自算位置 |

**同时清理**：`ShellLayout` 的 6 个常量并入 token 默认值；`settings_view/tape_view/shelf_view`
的版面常量删除；`shell.cpp` 每个屏的 update/draw 手写分支缩到"取事件 → 改状态"。

**验收**：7 屏文本快照全部一致；2 套皮肤截图基线一致；`agent_shell_demo.py` 17 项全过；
`shell.cpp + shell/*.cpp` 总行数下降 ≥30%；`state.query.cursor` 保留但改由焦点系统提供。

**风险**：中（交互回归）。逐屏合并、每屏一个提交、每屏都有快照对照；卡带架最后切。

### M3 卡带声明式 UI + 场景栈（3–4 周）

**目标**：把同一套组件暴露给 Lua（`phos.ui` v2 / `phos.scene`），让卡带不再手写界面；
至少迁移 3 张卡带作为样板。

> **状态（2026-10-31）**：**部分落地**。卡带侧 API 已发布：`phos.ui.render` + 查询
> （`focus/checked/set_checked/field_text/reset`）+ agent 接口（`state.query.ui`、
> `ui.list/focus/activate`），随 `phos_api = 7` / 0.9.0 发布；模板 `panel.lua` 已改用
> 声明式界面；样板卡带 `devkit/examples/ui/` 已加，`ui_smoke.py` 覆盖组件/焦点/事件。
> **未做**：`phos.scene` 场景栈与 Modal、3 张出厂卡带迁移、模板 `main.lua` 的"十条约定"
> 精简。验收里的"3 张卡带 UI 代码下降 ≥40%"尚不成立。

**交付**

- `phos.scene`：场景栈（`push/pop/top`）、`modal`、`pause_world`、`capture_input`、
  `audio_pause`、`on_enter/on_exit/draw/update`；替换 4 张卡带各自的屏幕状态机与 8 份暂停标志。
- `phos.ui` v2：`window/section/stat/table/list/option/checkbox/bar/field/hint/confirm/toast`，
  坐标可省略（由布局决定），锚点支持 `playfield/panel/layer`；每帧声明 + 引擎持有状态。
- 模板重写：`devkit/template/panel.lua` 从 44 行降到约 20 行；`main.lua` 的
  "十条约定"缩到"三条须知"（其余由组件保证）。
- 迁移样板：`snake`（全部 UI）、`runner`（面板+速度条+结束屏）、`towerdef`（最复杂侧栏）。
- 弃用与门控：新 API 记入 `phos_api = 7`；`devkit/phos.lua` 注解、`api-reference.md`、
  `--check-api` 同步（扩展为覆盖"是否有注解 + 是否注册"之外，再加"字段/签名"检查）。

**验收**：3 张卡带 UI 代码合计下降 ≥40%；`phos.ui.menu/frame` 在样板卡带中不再直接出现；
`cart_smoke.py` 对旧卡带逐字节不变；新卡带在 80x45 下不出现越界/重叠（`ui_smoke` 断言）；
`--check-api` 对 v2 全绿。

**风险**：中高（API 设计 + 旧卡带兼容）。原则：**只增不改**；v2 与旧原语共存；
样板迁移失败可只保留引擎能力、暂缓内容迁移。

> **内容迁移进度**：出厂卡带 `snake`、`runner` 已迁到新栈。
> snake：侧栏 `phos.ui.render`、排行榜 `phos.score`（删除自写 `scores.lua` 与逗号串编解码）、
> 观测 `phos.observe`、通用词 `phos.lang.shared`。
> runner：侧栏改为组件树（速度条用 `bar`、数值走 `text.score`）、**暂停浮窗改用场景栈**
> （`pause_world` 冻结世界、`audio_pause` 暂停音频、出栈自动恢复，删除 `paused` 标志与手写音频开关），
> 观测同样换 `phos.observe`。两卡 `--check-cart` 均 0 error/0 warning，cart/control 门禁全过。
> 迁移过程中发现并修复引擎问题：**压栈那一帧不该调用新场景的 update**（否则"同一个键开/关"
> 会被同一帧误关）；`scene_smoke` 已加回归。
> bricks：侧栏组件化（`stat` 行 + `phos.text.clock`）、最高分换 `phos.score{max=1}`
> （删除 `scores.lua`）、暂停换场景栈、观测换 `phos.observe`。三卡均 0 error/0 warning。
> tetris：侧栏统计组件化、"下一块"预览在预留 spacer 区里逐格绘、最高分换 `phos.score{max=1}`
> （删除 `scores.lua`）、暂停浮窗换场景栈（世界冻结/音频暂停）、观测换 `phos.observe`
> （棋盘逐行仍以字符串数组报出，agent 可直接定位每一格）。
> 四卡均 0 error/0 warning。下一张：`life` / `chomp`。

### M4 卡带工具层（3–4 周，可与 M3 部分并行）

**目标**：把"每张卡带都要重复写"的东西收进引擎：持久化、词表、格式化、观测、静态检查。

**交付**

| 能力 | 内容 | 直接删掉的重复 |
|---|---|---|
| 存档 v2 | `PHOSPHOR-SAVE 2` 容器 + **标量值类型保真**（文本/数字/布尔）**已完成**：CRC32、旧档升级 + `.v1` 备份、坏校验降级只读；结构化表、槽位、磁带码带 cart id 仍待做 | towerdef 约 220 行编解码；导入他卡存档 |
| 内置排行榜 | `phos.score.new{max, key}`：降序 TOP N、名次返回、`clear`、坏档/无存档降级、`score.top` 只读查询（已完成，`toolkit_smoke` 覆盖持久化） | 6 份最高分实现 |
| 共享词表/格式化 | `phos.lang.shared()`（18 词 zh/en）+ `text.score/clock/percent`（`core/format` 唯一实现，单测覆盖）；`money` 暂未做（留待按需） | 617 行文案表、24 处 pad |
| 观测 schema | `phos.observe{ score=..., units={...} }`：一次登记，`state.query` 稳定字段 | worms 约 200 行、towerdef/crawl 各约 60 行 |
| 键位提示 | `ui.hint` 自动取 `key_name` + 宽度裁剪 + 可重绑定 | 11 份键位提示块 |
| 卡带 lint | `--check-cart`（已完成）：manifest/入口、顶层隐式全局、`screen.size()` 误用、阻塞 `discover()`、`require` 缺模块、观测声明；`tools/cart_lint.py` 作为门禁（12 项之一） | K8 类缺陷 |

**验收**：`phos.save` v2 有掉电/损坏/迁移用例；三张样板卡带合计再降 ≥500 行；
`--check-cart` 已能报出隐式全局/可玩区误用/阻塞调用；出厂卡带与示例当前 0 error、0 warning（联机 discover 属已知 API 债，见 C14）。

### M5 体验与子系统（持续，按季度排）

按"用户能感知 + 支撑 UI"排序，每项独立可交付：

1. **系统功能**：帮助/关于页、存档管理（槽位/磁带码集中入口）、通知 OSD、截图快捷键、
   主题预览、设置分组与搜索。
2. **输入**：动作映射（`phos.input.action`）、重绑定界面、手柄（兑现文档承诺）、
   焦点丢失释放、按键重复参数化。
3. **渲染**：三条合成路径收成一条（`FrameComposer` → 绘制列表 + 文本投影），
   再谈渲染 IR 与批处理；先有**像素 golden**，再动合成顺序。
4. **音频**：声部优先级/抢占、停止淡出、ducking、音乐状态查询、流式采样、总线。
5. **绘制/精灵**：`line/box/ring` 几何、`sprite` 亮度/实心/多字节键、粒子与转场原语。
6. **内容包**：统一清单校验（`--check-packs`）、依赖与版本、UI 主题包、包预览、热重载。

### M6 生态（远期，不在本轮承诺）

MCP server 薄封装、联机大厅 UI、包签名/校验、Mod 补丁钩子（替代整文件 fork）、
Web 端卡带架/商店式分发、性能预算自动回归。

---

## 四、UI 框架设计规格（本轮核心）

> **落地差异（2026-10-31，以代码为准）**：本节是设计规格，实际实现做了三处精简——
> (1) 规划中的 `widget` / `nav` / `screen` 合并进 `element` / `layout` / `frame`，
> `ScreenStack` 与 `Modal` 尚未实现；(2) 旧 `core/ui` 的 9 个绘制函数**没有**搬到
> `ui/draw`，仍留在 core 作为底层原语；(3) 卡带 API 不是 4.9 的 `ui.panel(function…)`
> 草案，而是 `phos.ui.render(spec)` 的声明式表（实现见 `api/ui_render.cpp`，
> 字段表见 `api-reference.md`）。

### 4.1 目标与非目标

**目标**

- G1 同一实现服务外壳与卡带（视觉/交互天然一致）。
- G2 声明式：调用方描述"有什么"，引擎负责"放哪、怎么动、谁有焦点"。
- G3 可观测：控件树可被 agent 读取与激活（稳定 id/角色/标签/状态）。
- G4 可主题化：颜色/字形/度量来自 token；新增主题不改代码。
- G5 可测试：布局与焦点是纯函数，能用单测与文本快照覆盖。
- G6 增量兼容：旧 API 与旧卡带逐字节不变。

**非目标**

- 不做任意像素/半透明/鼠标优先的 GUI（保持字符网格与确定性）。
- 不做通用保留式控件对象（Lua 侧不持有控件句柄，避免状态同步与 GC 问题）。
- 不在本轮做布局动画引擎（过渡曲线只保留"滚动/出现"两种）。

### 4.2 分层与依赖

```
        shell/            （用 ui 描述界面，产生 Intent）
          │
        api/              （把 ui 暴露为 phos.ui / phos.scene）
          │
        ui/               布局 / 控件 / 焦点 / 主题 / 屏栈   ← 新层，只依赖 core
          │
        core/             Screen / Surface / Input / Text / Color
```

- `ui/` **不**依赖 shell/api/render；卡带侧绑定只做值与事件转换。
- 旧 `core/ui.*` 的 9 个绘制函数移入 `ui/draw.*`（同层，职责名实相符）；
  `ui::Style` 升级为 `ui::Tokens`，旧字段保留为别名以免一次性大改。
- `architecture.md` 的分层图同步更新（这是唯一允许的"文档随实现改"）。

### 4.3 模型：每帧声明 + 引擎持有状态

- 调用方每帧提交一棵控件树（`ui.begin/build/end`），控件**不跨帧持有指针**。
- 引擎按 `屏幕 id + 控件 id` 保存必须跨帧的状态：焦点、选中、滚动位置、滚动动画、
  文本域缓冲、展开/折叠。
- 每帧结束时返回事件列表：`activated(id)` / `changed(id, value)` / `confirmed(id)` /
  `cancelled(id)`。调用方只处理事件，不自己猜按键。
- **id 规则**：显式给（推荐，稳定、可观测）或由"父路径 + 类型 + 标签"自动派生；
  同一屏内重复 id 记一次警告并按派生 id 处理。id 是 agent 可观测性的基础，必须稳定。

理由：字符网格 UI 的状态很少（焦点/滚动/文本/选中），声明式能把"状态与绘制分离"，
避免 Lua 侧持有控件对象带来的生命周期与热重载问题；同时布局与命中测试集中在一处，
才能被单测覆盖。

### 4.4 布局

```
Rect{ x, y, w, h }        // 已有
Insets{ l, t, r, b }
split_row(rect, weights) / split_col(rect, heights)
align(rect, size, { h = "center", v = "end" })
anchor(rect, { "playfield" | "panel" | "content" | "layer:<name>" })
```

- 容器：`VBox`（可选间距/分隔线）、`HBox`、`Grid(cols)`、`Scroll`（裁剪 + 滚动条）。
- 文本进入布局：标题/正文按显示宽度测量并折行；溢出策略 `clip | ellipsis | wrap`，
  默认 `ellipsis`（与 `text.fit` 同语义，避免硬切）。
- 自适应：面板宽度变化、字号变化、语言切换后，布局下一帧自动重算；
  `Scroll` 与 `List` 的视口高度由布局给出，不再由卡带算。
- 所有坐标最终落到内容区局部坐标，再由 `Surface` 裁剪——**不在 UI 层另造一套裁剪**。

### 4.5 主题 token

```
Tokens {
  colors: surface, surface_alt, panel, text, text_dim, accent,
          border, border_focus, selection_bg, warning, danger, disabled
  glyphs: hline, vline, corner[4], cursor, bullet, scroll_thumb, scroll_track
  metrics: row_h, pad, gap, border_w, scrollbar_w, title_pad
}
```

- 外壳：`tokens_from_skin(skin)`；卡带：`tokens_from_palette(palette)`；
  缺省由内置 token 兜底——派生路径仍只有这两条（沿用 `ui::style_from_*` 的思路）。
- 新增可选内容包 `theme/ui/<id>/ui.lua`：只覆盖字形集与度量（颜色仍由 skin/palette 决定），
  于是"另一套边框/滚动条"是可替换内容，而不是改代码。
- 控件样式只有 6 态：normal / focus / selected / active / disabled / danger。
  任何控件不得自造颜色；`draw` 层仍接受显式颜色，供旧 API 与特效使用。

### 4.6 输入与焦点

- 屏幕有焦点栈；模态屏压栈即捕获输入，下层不收到任何键。
- 导航：默认按声明顺序（`Tab`/上下）；`List/Grid` 显式二维导航；
  `left/right` 在 `OptionRow/Bar/Stepper` 上改值，在 `List` 上交给父级。
- 语义键：`confirm`（Enter/A）、`cancel`（Esc/B）、`menu`（F2/`~` 等保留键不进控件），
  由 `ui::Keys` 统一映射——外壳与卡带各用一套"意图"，物理键只有一处映射。
- 按键重复：首次延迟与重复间隔进 token；`List` 长按连续移动。
- 消费语义：焦点控件先处理；未消费的键再交给屏幕级处理（例如 Esc 弹栈）；
  最后交给主机保留键。**没有任何一层可以直接读裸 GLFW 输入。**
- 键位提示由控件生成：`ui.hint` 取当前层可用的 confirm/cancel/左右动作与
  `input.key_name()`，宽度不够时自动省略。

### 4.7 控件清单与契约

| 控件 | 状态 | 事件 | 可观测字段 |
|---|---|---|---|
| Label / Paragraph | — | — | text |
| Divider | — | — | — |
| Button | normal/focus/disabled | activated | label, enabled |
| List | cursor, scroll, disabled rows | activated(index) | selected, count, scroll |
| Grid | cursor(x,y), scroll | activated(index) | selected, cols, count |
| StatRow | label, value, tone | — | label, value |
| Table | columns, rows, align | — | cols, rows |
| OptionRow | index, choices | changed(index) | label, value |
| Stepper / Bar | value, min/max | changed(value) | value |
| Checkbox / CheckList | checked[] | changed(id, bool) | checked |
| TextField | text, cursor, IME, scroll | changed(text), submitted | text, count |
| Frame / Window | title, opaque | — | title |
| Modal | title, focus trap | confirmed/cancelled | title |
| Footer / HintBar | hints | — | hints |
| Toast | text, ttl | — | text |

v1 只实现外壳与卡带侧栏所需（上表去掉 Grid/Table/Toast 也可）；Grid/Table/Toast 放 M3。

### 4.8 屏幕与场景栈

- `ui::Screen`：一屏的根（名为 stable id），持有焦点与滚动状态；`draw(ctx)` 构建控件树。
- `ui::ScreenStack`：`push/pop/replace`；模态 = 只让栈顶接收输入；
  切换时可选"冻结下层更新"与"暂停音频"两个钩子（对应 `phos.scene` 的 `pause_world/audio_pause`）。
- 外壳的 `ShellMode` 改为"栈 + 屏"：`settings` 变成可从暂停菜单压栈的一屏（解决当前
  "设置只能在卡带架打开"的限制），`mods/tape` 是模态屏，`cart_error` 是替换式屏。
- 卡带侧同名概念（`phos.scene`）由同一实现承接：卡带的暂停/背包/设置/结束屏
  不再各自维护 `screen = "menu"` 状态机。

### 4.9 卡带侧 API（草案）

```lua
-- 侧栏：声明式，坐标/光标/裁剪由引擎负责
function draw()
  local ui = phos.ui
  ui.panel(function(p)                      -- 锚定 panel 的 VBox
    p:title(phos.cart.info().name)
    p:divider()
    p:stat("SCORE", game.score)
    p:stat("BEST",  game.best, { tone = "accent" })
    p:bar(hp / max_hp, { label = "HP" })
    p:hint{ { "a", t.act }, { "start", t.pause } }   -- 自动取真实键名 + 裁剪
  end)
end

-- 暂停：场景栈 + 模态列表，事件而不是按键轮询
phos.scene.push("pause", {
  modal = true, pause_world = true, audio_pause = true,
  draw = function(ui)
    ui:window("pause", { w = 30, h = 9, title = t.paused })
    ui:list("items", {
      items = { t.resume, t.help, t.quit },
      disabled = { [3] = not game.can_quit },
      on_confirm = function(i)
        if i == 1 then phos.scene.pop() elseif i == 3 then quit() end
      end,
    })
    ui:hint()
  end,
})

-- 危险操作：确认框（默认焦点在"安全"一侧）
if phos.ui.confirm{ title = t.quit, body = t.quit_body,
                    yes = t.yes, no = t.no } then quit() end

-- 文本域：绘制光标/IME/限长都在引擎
local field = phos.input.field{ filter = "printable", max = 12, ime = true }
phos.ui.field{ "name", label = t.name, field = field, on_submit = start_game }
```

其余约定：

- 事件只在本帧有效（与 `input.pressed` 同心智），不跨帧保存事件表。
- `phos.ui.confirm{}` 是"一帧式"便捷用法（本帧内返回是否已确认）；需要跨帧等待的选择写成
  `phos.scene`。两者共用同一个模态栈，不各自抢输入。
- 所有界面文字走 `phos.lang`；控件不做翻译，只做排版。
- 控件错误（未知 id、非法尺寸、重复 id）写一次日志并降级，不抛错中断卡带。
- 旧 `phos.ui.frame/menu/...` 保留；新 API 不做同名覆盖。

### 4.10 外壳迁移映射（逐屏）

| 现文件 | 现状问题 | 迁移后 |
|---|---|---|
| `shell/settings_view.cpp` | 行表 + 手写列坐标 + 值格式化混在一起 | 声明 `Section`/`OptionRow`；值格式化移入 `ui` 的 row 构造器，数据仍来自 `SettingsContext` |
| `shell/shell.cpp` `draw_mods` | 手写勾选、滚动动画、截断、光标 | `Modal` + `CheckList`；滚动动画归 `Scroll` |
| `shell/shell.cpp` `draw_paused` | 手写矩形与菜单偏移 | `Modal` + `List` |
| `shell/tape_view.cpp` | 手写分页与输入区 | `Page` + `TextField`（分页 = `Paragraph` 滚动） |
| `shell/shelf_view.cpp` | 14 个布局魔数、自算邻位动画 | `Grid/List` + 内容包 painter 接口不变 |
| `shell/boot_view.cpp` | 手写逐行与光标闪烁 | `draw` 原语 + `Label`，行时序保留 |
| `shell/shell.cpp` `draw_bezel` | 皮肤几何直接画 | 保留（机身是内容/皮肤，不属于组件层） |

### 4.11 agent 可观测性

`state.query` 新增 `ui` 字段（有界面时）：

```json
{"ui": {
  "screen": "shelf",
  "focus": "shelf/list",
  "widgets": [
    {"id":"shelf/list","role":"list","label":"CARTS","state":{"selected":3,"count":11}},
    {"id":"shelf/search","role":"textfield","state":{"text":"","editing":false}}
  ]
}}
```

新增控制命令：`ui.list`（树/扁平表）、`ui.focus{id}`、`ui.activate{id}`（等价确认）、
`ui.text{id}`（读文本域）、`ui.type{text}`。语义与玩家按键一致：模态栈顶优先，
禁用控件拒绝激活并回错误。`state.query.cursor` 保留为"焦点控件下标"的兼容字段。

这是本项目的差异化优势：**agent 不必数按键，也无需 OCR**；同时强制控件 id 稳定，
反过来提升测试质量。

### 4.12 测试与基线

| 层 | 手段 | 覆盖 |
|---|---|---|
| 单元 | 纯函数测试 | 布局切分/内缩/权重、焦点遍历、滚动夹紧、文本域编辑、模态陷阱、id 稳定性、token 派生 |
| 文本快照 | `to_text()` 逐字节 | 外壳 7 屏 × 2 语言；卡带侧栏样板 |
| 像素基线 | `--screenshot` + 容差 | 外壳 7 屏 × 2 皮肤；卡带 3 张关键帧 |
| 交互契约 | `tools/ui_smoke.py`（控制通道注入） | 焦点移动/循环、禁用跳过、弹窗拦截、文本域输入、左右改值、Esc 逐层退栈 |
| 兼容回归 | 既有 9 项门禁 + `agent_shell_demo` | 旧卡带逐字节不变、外壳流程不变 |

### 4.13 性能预算

- 80x45 网格、控件树 ≤ 200 节点：布局 + 绘制 ≤ **0.3 ms/帧**（60Hz 下 <2% 预算）。
- 每帧堆分配次数 ≤ 8（控件/节点用帧内 arena；字符串只在变化时重建）。
- 绘制调用只经 `Surface`，不新增第二条写屏路径；不引入逐像素操作。
- 每次里程碑跑一次 10 分钟浸泡 + 现有 `state.query` 的 `update_ms/draw_ms` 对比。

### 4.14 兼容与迁移

1. `phos.ui` 旧函数保留（语义与默认底色规则都不动）。
2. 新 API 记入 `phos_api = 7`；文档给"旧写法 → 新写法"对照表。
3. 外壳迁移不涉及 `phos_api`；卡带迁移只在样板卡带进行，旧卡带不动。
4. 弃用流程：先在 `api-reference.md` 标"建议改用"，至少一个发行周期后才考虑移除；
   移除必须伴随代际提升与迁移说明。
5. `devkit/phos.lua` 与 `api-reference.md` 同步为门禁项（`--check-api` 扩展）。

---

## 五、其他工作流规格（摘要）

### 5.1 边界与真源（M0 启动，M2 前完成）

- `App` 迁出 `core/` → `src/app/`（`main_loop` / `cart_host` / `control` /
  `settings` / `observe`），`core/` 不再 include 上层；顺带移除 `core` 头里的 sol2。
- `HostContext` → `HostServices`（窄接口 + RAII `CartScope` 负责安装/卸载卡带句柄），
  删除 9 处手工清指针。
- 模式：单一状态机（`Mode` 枚举 + `transition()` + 不变量断言），
  `ShellMode` 变成 UI 屏标识；`state.query.mode` 由它生成。
- 选择：`Config`（持久化）→ `ContentLibrary`（索引）→ `Shell`（只读视图数据）；
  `Shell` 不再存名字/下标副本。
- 帧步进：一份 `advance_frame()` 供实时/单步/无头复用；`time.step` 的回包由它统一负责。
- 沙箱：一份 builder（白名单 + 看门狗 + 堆上限 + chunk name + traceback），
  卡带与全部包脚本共用。
- 全局可变态：Mod 表改由 `App` 持有并注入（`core/mods` 只留纯查表）；看门狗状态收进
  `Cartridge`；日志的帧号/级别改为显式参数或 `Log` 实例。与 `code-style.md` 的
  "不使用全局可变状态"对齐。

### 5.2 渲染合成器（M1 后并行，像素基线先行）

1. 先写"窗口 vs 截图 vs 文本"一致性契约（续格笔迹、缩放块、层叠），红→绿。
2. 再收成 `FrameComposer`：输入底图 + 层 + chrome，输出"绘制列表 + 文本投影"；
   GL / CPU 截图 / `to_text` 都消费它；每帧文本投影改为按需（`screen.read`/dump 时算）。
3. 最后谈 `FontAtlas / CellGeometry / CrtPipeline / GlBackend` 拆分与批处理；
   在此之前不动 GL 语义。

### 5.3 存档 v2（M4）

- 文件头：magic + version + cart id；正文：结构化键值（可嵌套表，JSON 文本）。
- 原子写：`saves/<id>.sav.tmp` → fsync → rename；失败保持旧档。
- 迁移：`manifest.lua` 可选 `migrate(save, from_version)`；无回调时按兼容策略降级。
- 磁带码：magic + cart id + CRC + base16；导入校验 cart id 不匹配即拒绝（除非显式 `force`）。
- 槽位：`phos.save.slot(n)`（默认 1 = 兼容旧路径）；`phos.score` 建在槽位 1 的保留键上。

### 5.4 音频（M5）

- 声部优先级与抢占（音乐 > 关键音效 > 氛围）；停止/暂停淡出（≥5 ms）消除爆音。
- 总线：music / sfx / ui 三路（现有两路 + UI 音）；`phos.audio.duck(...)`。
- 音乐状态：播放/乐段/循环点可查询（已有 `music` 字段，扩展为可等待事件）。
- 采样：流式（大文件不整读）；设备丢失重建。

### 5.5 输入（M5）

- `phos.input.action(name)`：动作 → 物理键映射，写在卡带/主机配置里；
  `ui` 的提示与重绑定界面都读它。
- 手柄：GLFW joystick/gamepad 映射到同一套虚拟键名；兑现文档承诺（或删掉文档里的"手柄"）。
- 焦点丢失：`glfwSetWindowFocusCallback` → `Input::release_all()`，避免切窗后按键卡住。

### 5.6 内容包与工具（M5/M6）

- 统一清单：所有包声明 `id/name/version/type/api`，`--check-packs` 校验；
  包之间可选 `requires`。
- `ui` 主题包（字形集/度量）；包预览（shelf 已有图标，skin 可在设置里预览）。
- 卡带工具：`--watch`（文件变化自动 `cart.reload`）、`--check-cart`（lint）、
  `tools/golden.py`（截图基线生成/比对）、`--replay <log>`（控制命令回放）。

### 5.7 工程治理（M0 起持续）

| 项 | 内容 |
|---|---|
| CI | Windows(MinGW) + Linux(GCC/Clang) 构建；`run_checks.py`；单测；文档门禁 |
| 格式化 | `.clang-format`（项目风格：4 空格、100 列、指针靠类型）+ `cmake --build` 前检查 |
| 静态分析 | `.clang-tidy`（bugprone/performance/modernize 子集）+ ASan/UBSan 任务（Linux） |
| Presets | `CMakePresets.json`：debug/release/sanity/asan，统一构建入口 |
| 覆盖率 | 单测覆盖率报告（目标：core ≥70%，ui ≥60%） |
| 基线 | 文本快照 + 像素基线纳入仓库与 CI |
| 文档门禁 | `--check-docs`：核对文档里的版本号/世代号/API 签名/文件清单；include 方向检查脚本 |
| 版本 | `CHANGELOG.md` + semver 政策；`extern/` 依赖清单（名称/版本/来源/许可证） |

### 5.8 协议、网络与绑定层（M0–M1）

这些是"agent 就是用户之一"的基础设施，和 UI 一样属于"所有人都在用、却没有统一实现"的部分。

- **JSON 只留一份**：writer/parser 共用同一实现（`\u` 与代理对、非有限数、深度/大小上限、
  可报告的解析错误），inspect / net / control 三个使用点统一。现有"命令参数不含非 ASCII"
  的假设（`core/json_lite.cpp:53-57`）必须删除——它已经让中文注入静默丢字。
- **控制通道重建**：复用 `platform/socket`；后台线程只收发，主线程只排空**有界**队列；
  回包走非阻塞有界队列（慢客户端丢弃并计数，不阻塞主线程）；hello/idle 超时、
  accept 错误上报；命令表（名称 → 参数校验 + 回包）替代 280 行 if 链；协议版本升 2、保留 v1。
- **联机非阻塞化**：`join`/`discover` 改异步 + 轮询事件（阻塞版保留为显式 `*_blocking` 并写明上限），
  `stop()` 先 `worker.join()` 再触碰连接表；握手/掉线超时、成功后清除错误、对端地址如实上报；
  wire format 与 `networking.md` 同源。
- **绑定层收口**：一份 parameterized binder（surface × 方法集：screen / panel / region / layer），
  消除 `host_api` / `ui_api` / `draw_region` 的三份重复；`sprite` 的 step 语义
  （缩放还是降采样）定稿并同步注解与文档。
- **Lua 输出**：`print` 重定向到主机日志（或删掉文档承诺）；`--dump-screen` 等机器可读
  输出保证只有一份，不被卡带输出污染。

---

## 六、顺序、并行与风险

### 时间轴（按单人主线 + 可并行的 AI/协作者估算）

| 周 | 主线 | 并行 |
|---|---|---|
| 1–2 | M0 止血 + CI + 文本快照 | 文档纠偏、`ui` 设计评审 |
| 3–6 | M1 UI 内核（布局→控件→焦点→主题）+ 两屏迁移 | 合成器一致性契约（5.2 第 1 步）；协议/网络收口（5.8） |
| 7–9 | M2 外壳全量迁移 + 快照对齐 | 输入动作映射（5.5） |
| 10–13 | M3 卡带 UI v2 + `phos.scene` + 3 张样板 | 存档 v2 设计与实现（5.3） |
| 14–17 | M4 卡带工具层 + lint + 文档 | 渲染合成器收口（5.2 第 2 步） |
| 18+ | M5 体验项按季度排期 | M6 生态评估 |

### 并行拆分原则

- 同一文件/同一模块只由一条工作流写；跨流改动先加接口再迁移。
- UI 内核（`src/ui/`）与渲染合成器（`src/render/`、`core/display`）写域不重叠，可并行。
- 每个里程碑合并前必须：全门禁绿 + 快照/基线通过 + 文档与注解同步。

### 风险登记

| 风险 | 影响 | 缓解 |
|---|---|---|
| 外壳迁移交互回归 | 玩家侧可见 | 逐屏切换 + 文本快照 + `agent_shell_demo` + 可回退绘制路径 |
| UI API 设计返工 | 卡带侧重复迁移 | M1 只做最小控件集；M3 前用 3 张样板卡带做设计验证，再冻结 v2 |
| 性能回退 | 60Hz 下卡顿 | 预算 + arena + 每次里程碑浸泡；布局纯函数无 I/O |
| 旧卡带兼容 | 生态信任 | 只增不改 + `phos_api` 门控 + `cart_smoke` 逐字节比对 |
| 范围膨胀 | 交付延期 | 每阶段有"不做清单"；M5 按项独立验收 |
| 文档再次漂移 | 规范失效 | 门禁化（`--check-api` 扩展、`--check-docs`、include 检查） |

---

## 七、验收指标（可度量）

| 指标 | 现状 | M2 后 | M4 后 |
|---|---|---|---|
| 卡带 UI 重复实现（侧栏头/列表/浮窗/设置/帮助/暂停/最高分） | 12/8/6/3/3/8/6 | 0（组件承担） | 0 |
| 卡带 UI 代码行数（panel+hud+浮层） | ≈2,500 | ≤1,500 | ≤1,000 |
| `phos.ui.menu/bar/text/divider` 卡带使用率 | 0 | 侧栏样板 100% 用组件 | 新卡带模板 100% |
| 外壳绘制调用 | 50（其中 6 处直接 `screen.put/print`） | 全部经组件 | — |
| `shell/` 总行数 | 2,084 | ≤1,450 | — |
| 单测数（C++） | 51 | ≥90（含 ui 布局/焦点） | ≥120 |
| 契约门禁 | 6 | 8（+ui、+shell 快照） | 10（+save、+lint） |
| 文档漂移 | 22 处 | 0（M0 修正 + 门禁守） | 0 |
| 外壳每帧 UI 耗时 | 未测 | ≤0.3 ms | ≤0.3 ms |
| 旧卡带兼容 | — | `cart_smoke` 逐字节不变 | 同左 |

---

## 八、本轮明确不做

- 不做鼠标优先的窗口系统、不做任意像素绘制、不做半透明格。
- 不重写 `Screen`/图层/绘制模型（只收口不变式与合成路径）。
- 不替换 Lua、渲染后端或平台层。
- 不做跨平台联机中继、加密、回滚同步（仍是卡带自选）。
- 不在 M3 前改动任何卡带内容（样板迁移除外）。

---

## 附录 A：缺陷 → 阶段映射

| 阶段 | 关闭的缺陷 |
|---|---|
| M0 | C1–C6、C9–C13、C16；C7（先统一为一条路径）；S5（一行前向声明）；E1 部分 |
| M1 | S1–S4、S6–S8、S11（与 5.1/5.8 同批）；C14、C15；U1 部分（两屏） |
| M2 | U1、U5、U6、U7（外壳侧）；E3（外壳基线） |
| M3 | U2–U4、U6、U7（卡带侧）；K1；`phos_api = 7` |
| M4 | K2–K5、K7、K8；E2 部分 |
| M5 | K6、C8 的按需投影、C7 的彻底收口、音频/输入/渲染缺口 |

## 附录 B：术语

- **原语（primitive）**：一次绘制调用（`put/print/fill/frame/bar`），无状态。
- **控件（widget）**：有角色、状态、事件与可观测字段的界面单元（`List`/`OptionRow`/…）。
- **屏幕（screen）**：一屏控件树 + 焦点 + 滚动状态的根；可压栈。
- **场景（scene）**：屏幕 + 更新/输入/音频策略（卡带侧 `phos.scene` 的载体）。
- **token**：主题里的颜色/字形/度量变量；控件只读 token，不写死颜色。
- **声明式界面**：每帧描述界面，引擎持有跨帧状态；与"保留式控件对象"相对。
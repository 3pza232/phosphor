# PHOSPHOR

**一台由字符构成的游戏机。**

卡带是几个 Lua 文件——写完存盘就能玩，不用编译；画面是纯文本字符网格，
人和 AI 都能直接读懂。

---

## 它是什么

| | |
|---|---|
| 形态 | 绿色免安装的单文件主机（`phosphor.exe`），双击即用 |
| 画面 | `80x45` 字符网格 + 显像管后处理（扫描线、孔径格栅、辉光、色调） |
| 卡带 | 一个文件夹或一个 `.phos` 单文件，丢进 `carts/` 就被扫到；Lua 沙箱，碰不到文件系统；网络只能走 `phos.net` |
| 外观 | 机台外壳、主题配色、启动动画、系统音效、字体全是**内容包**，都可替换或新增；界面语言内置中 / 英两套文案 |
| 界面 | 声明式界面（`phos.ui.render`）与场景栈：外壳与卡带共用同一套组件、焦点、主题与度量 |
| 卡带工具 | 引擎内建排行榜、声明式观测、共享词表、数值格式化、存档 v2（槽位）与静态检查（`--check-cart`） |
| 面向 agent | 画面即文本（无需截图与视觉模型）、带控制通道可注入输入与精确步进、卡带可自报玩法状态（`phos.observe`，兼容 `debug_state`），声明式界面可读出控件树（`state.query.ui`） |
| 联机 | 局域网联机内建：卡带可开房 / 加入 / 收发消息 / 自动发现（`phos.net`；发现 / 加入有异步 API，不阻塞游戏循环） |

## 快速开始

**玩**：解压后双击 `phosphor.exe`，方向键选卡带，`Enter` 进入；`Esc` 返回。
从桌面/别的目录启动也没关系：内容根按 **exe 所在目录**解析（`--root <目录>` 可显式指定）。
存档在 `saves/<卡带 id>.sav`，可用「磁带码」导出成一串文本带走。

**做一张卡带**：

```bash
phosphor --new carts/mygame --id mygame --name "My Game" --author "你"
phosphor --cart carts/mygame                    # 改完存盘直接跑，卡带不需要编译
phosphor --check-cart carts/mygame              # 静态检查（manifest/入口/常见错误写法）
phosphor --pack carts/mygame                    # 产出 dist/mygame.phos
```

`--new` 生成的是**空骨架**：`manifest.lua`（身份）、`main.lua`（入口）、`game.lua`（规则）、
`panel.lua`（右栏），需要你改的地方都标了「填」。

**让 agent 帮你做**：开控制通道，注入输入、精确步进、读屏判断——

```bash
phosphor --cart carts/mygame --control 7654 --headless
phosphor --check-api                            # 校验 API 注解与实现一致
```

## 从源码构建

```bash
cmake --preset release          # 直接生成 build/（发行形态；不产出测试目标）
cmake --build --preset release
# 等价的手动写法：mkdir build && cd build && cmake -G Ninja -DCMAKE_BUILD_TYPE=Release .. && ninja
```

依赖已随仓库放在 `extern/`（glfw / lua / miniz / sol2 / imgui / stb / miniaudio），
不需要额外安装。构建后 `build/` 就是可直接分发的运行包。

构建**默认不产出** `phosphor_tests`（纯逻辑单元测试）——`build/` 同时当发行目录用，
不该混进测试产物。要跑单元门禁就用 `dev` preset（产出独立目录 `build-dev/` 与测试目标）：

```bash
cmake --preset dev              # build-dev/：Release + phosphor_tests
cmake --build --preset dev
cd build-dev && python ../tools/unit_smoke.py   # 或 cd build-dev && ./phosphor_tests
```

**内容改哪里**：改卡带/主题/文档改 `package/` 与 `docs/` 下的源文件，构建时同步进 `build/`。
若运行目录里的同一份文件在上次同步之后被就地改过，构建会**跳过它并告警**（不会静默覆盖）——
要么把它拷回 `package/`，要么直接改 `package/` 再构建。

**排查内存类问题时**用自检构建：容器边界断言与栈保护让越界访问在**现场**停下并打印位置，
而不是过一会儿以"堆已损坏"的形式暴露在离元凶很远的地方。

```bash
cmake --preset sanity           # build-sanity/：自检构建，慢，只用于排查
```

**开发脚本**（`tools/`；除注明外都在含 `phosphor.exe` 的构建目录里跑）：

| 脚本 | 用途 | 跑法 |
|---|---|---|
| `portable_smoke.py` | 绿色免安装契约：在临时 CWD 启动构建产物，验证内容根按 exe 目录解析、`--check-api` 回退、`--root` 覆盖 | `python ../tools/portable_smoke.py` |
| `check_includes.py` | 依赖铁律门禁：核查 `src/` 的 include 方向（对照 `docs/engine/architecture.md` 第一节）；纯源码检查，不需要构建目录，任意目录可跑 | `python tools/check_includes.py` |
| `perf_budget.py` | 性能预算报告（非门禁）：逐张出厂卡带采样 update/draw/merge 的 p50/p95/max，按 p95 update 排序并提示超预算的一半 | `python ../tools/perf_budget.py` |
| `run_checks.py` | **一键跑全部门禁并汇总**：默认无头门禁 **13 项**（includes/api/unit/control/draw/layer/ui/scene/toolkit/lint/portable/cart/net），`--gui` 再加开窗门禁（gl/window）。测试逻辑仍在各自脚本里，它只管调度与汇总 | `python ../tools/run_checks.py [--gui]` |
| `unit_smoke.py` | 纯逻辑单元测试：跑 `phosphor_tests`（C++，源码在 `tests/`，当前 **114 个用例 / 1216 条断言**），覆盖颜色/文本/配置/色板/主题/存档/UI 布局与焦点等不依赖 GL·Lua 的核心——无窗口无显卡即可跑（需构建时 `-DPHOSPHOR_BUILD_TESTS=ON`，或 `cmake --preset dev`）。单跑时未启用则**跳过**；但 `run_checks.py` 的 `unit` 门禁会检查产物，**缺失即判失败**（跳过不算通过，免得掩盖红灯） | `python ../tools/unit_smoke.py` |
| `control_test.py` | 控制通道契约：握手 / 单步精确 / 读屏 / 注入 / 热重载 / 退出 | `python ../tools/control_test.py` |
| `window_smoke.py` | 窗口路径冒烟：菜单→开局→按键→单步 →**实时浸泡**→干净退出（确定性部分全走单步，只有最后几秒实时；需要图形环境） | `python ../tools/window_smoke.py [--seconds 3] [--cart carts/x]` |
| `cart_smoke.py` | 卡带冒烟：出厂卡带各跑一段，断言跑得完 / 不出错 / 有画面 / **同种子跑两遍逐字节一致**；不比对像素——画面本来就该随内容变 | `python ../tools/cart_smoke.py [--frames 3000] [--cart worms]` |
| `layer_smoke.py` | 图层契约：跑 devkit 的图层示例卡带，核对按 z 叠放、字形透出下层、浮窗盖住世界、整层显隐、按层读取；并核对没建层的卡带 `layers` 为空且 `merge_ms == 0` | `python ../tools/layer_smoke.py` |
| `draw_smoke.py` | 叠加与半格契约：跑 devkit 的叠加示例卡带，读像素核对"同格两笔的墨都在""`back_rect` 铺到字形之外""`plot` 的墨落在指定子位"，并核对叠画上限（需要 Pillow） | `python ../tools/draw_smoke.py` |
| `scene_smoke.py` | 场景栈契约：压栈 / 冻结世界 / 音频暂停 / 出栈恢复（卡带样板 `devkit/examples/scene`） | `python ../tools/scene_smoke.py` |
| `toolkit_smoke.py` | 卡带工具层契约：排行榜持久化、共享词表、数值格式化、存档槽位（样板 `devkit/examples/toolkit`） | `python ../tools/toolkit_smoke.py` |
| `cart_lint.py` | 卡带静态检查门禁：对出厂卡带与 devkit 示例跑 `--check-cart`（manifest / 入口 / 隐式全局 / `screen.size()` / 阻塞版 `discover()` 与 `join()` / 观测声明），错误即失败、警告列出跟踪 | `python ../tools/cart_lint.py` |
| `ui_smoke.py` | 声明式界面契约：跑 `devkit/examples/ui` 样板卡带，核对组件渲染、焦点顺序、事件语义（`index` / `checked` / `text`）与"侧栏 `input = false` 不抢按键"；agent 侧核对 `state.query.ui` 列表与按 id 激活 | `python ../tools/ui_smoke.py` |
| `shell_golden.py` | 外壳界面**文本基线**：驱动 7 个外壳屏，把 `screen.read` 结果与 `tests/golden/shell/` 逐字节比对；界面有意改变时用 `--write` 重生成（迁移/改布局前后都拿它对照） | `python ../tools/shell_golden.py [--write]` |
| `pixel_golden.py` | 画面**像素基线**（**非门禁**，Pillow）：headless 跑 3 个固定场景（snake/xiangqi 第 90 帧、卡带架第 264 帧，固定 seed、状态隔离到 `tests-out/pixel-golden/`），截图缩到 320×180 与 `tools/golden/pixel/` 比：MAD ≤ 2 且明显差异像素 ≤ 0.5% 通过；字体/驱动的跨机差异可能误报，故不进 `run_checks`，界面有意改变时用 `--update` 维护基线 | `python ../tools/pixel_golden.py [--update]` |
| `gl_smoke.py` | GL 渲染路像素门禁：开窗用 `frame.read` 读回真实帧，核对"不是全黑""同格两笔""半格""逐层叠画"——`screenshot` 走 CPU 光栅化，覆盖不到着色器与图层叠画（需要图形环境与 Pillow） | `python ../tools/gl_smoke.py` |
| `net_smoke.py` | 联机契约：同机起两个 `phosphor` 进程，一个开房一个加入（走 `phos.net` 与局域网发现），核对连接、对端列表、消息互通、断开事件（headless 即可，无需图形环境） | `python ../tools/net_smoke.py` |
| `agent_play.py` | 通用 agent 玩家：开真窗口、在卡带架上挑一张卡带、按卡带自报的 `debug_state()` 操控它玩（策略用 `--policy` 接自己的文件，流速用 `--speed` 设，默认实机流速） | `python ../tools/agent_play.py [--shelf-cart bricks] [--cart carts/x] [--steps 40] [--speed 1]` |
| `agent_shell_demo.py` | 端到端操控系统界面：设置 / 插拔卡 / 暂停 / 磁带码 | `python ../tools/agent_shell_demo.py` |
| `clean.py` | 清运行目录里的临时物（日志 / 截图 / 演示存档区 / 纯测试产物 `phosphor_tests`），不碰设置、存档与运行主机所需的构建产物 | `python ../tools/clean.py` |
| `make_icon.py` | 由 `theme/icon/phos_icon.jpg` 生成 exe 用的多尺寸 `.ico`（换 exe 图标时跑一次并把 `.ico` 提交；窗口图标不受影响）。路径按脚本位置解析，任意目录可跑，需 Pillow | `python tools/make_icon.py` |
| `phos.py` | 上面几个脚本共用的控制通道客户端库，不单独运行 | — |
| `sync_package.cmake` | 构建期把 `package/` 与 `docs/` 同步进构建目录（由 `assemble_package` 目标调用，规则与告警见文件头） | 随构建自动执行 |

## 持续集成

`.github/workflows/ci.yml` 在 Windows + MSYS2 MinGW64 上配置、构建、跑单元测试与 13 项无头门禁；
性能预算（`tools/perf_budget.py`）与像素基线（`tools/pixel_golden.py`）作为**非门禁**步骤运行：
前者附到 job summary 并留 artifact，方便对比某个改动是否让某张卡带突然变慢；后者失败时把
实际截图留档，供人工判断是回归还是跨机差异。

## 目录

| 目录 | 内容 |
|---|---|
| `src/` | 主机源码（C++17） |
| `package/` | 随包分发的内容：`carts/` 出厂卡带、`devkit/` 工具链与模板、`theme/` 内容包、`mods/` 覆盖层 |
| `docs/` | **文档**：根级 = 发行文档（玩家手册 / 卡带作者手册 / API 参考 / 格式与内容包 / agent 接口）；`docs/engine/` = 引擎实现文档 |
| `docs/engine/` | 引擎实现文档：分层 / 代码规范 / 绘制模型 / 图层 / 联机 / 现状体检 / 演进路线（**不随发行包发布**） |
| `tools/` | 开发脚本（自测、演示、构建期同步） |
| `tests/` | C++ 纯逻辑单元测试（`phosphor_tests` 目标；由 `run_checks.py` 的 unit 门禁调用） |
| `build/` | 构建产物，**同时就是可直接分发/试玩的运行目录**：`carts/ devkit/ theme/ mods/ saves/ docs/` 与 exe 同级，全部是真实文件（不含任何路径联接） |

## 文档

文档分**两层**：`docs/` 根级随发行包发布（给玩家与作者），`docs/engine/` 是引擎实现文档、只在开发仓库里（给引擎开发者）。

### 使用文档（随发行包发布）

| 你想 | 去看 |
|---|---|
| 玩：启动、操作、设置、存档与磁带码 | [`docs/playing.md`](docs/playing.md) |
| 做卡带：一分钟版上手 + 踩坑清单 | [`docs/devkit.md`](docs/devkit.md) |
| 查 API：每个 `phos.*` 调用 | [`docs/api-reference.md`](docs/api-reference.md) |
| manifest 字段、生命周期、沙箱 | [`docs/cart-format.md`](docs/cart-format.md) |
| 主题 / 皮肤 / 启动动画 / 音效 / 字体 / Mod | [`docs/content-packs.md`](docs/content-packs.md) |
| 脚本与 agent 接口 | [`docs/agent-interface.md`](docs/agent-interface.md) |

入口：[`docs/README.md`](docs/README.md)。

### 引擎开发文档（不随发行包发布，只有改 `src/` 时才需要）

| 你想 | 去看 |
|---|---|
| 分层、目录职责、依赖方向 | [`docs/engine/architecture.md`](docs/engine/architecture.md) |
| 代码风格与命名约定 | [`docs/engine/code-style.md`](docs/engine/code-style.md) |
| 绘制模型（格 / 半格 / 叠加 / 底色） | [`docs/engine/drawing.md`](docs/engine/drawing.md) |
| 图层系统（合成 / 排序 / 按层读） | [`docs/engine/layers.md`](docs/engine/layers.md) |
| 联机实现（传输 / 发现 / 线程） | [`docs/engine/networking.md`](docs/engine/networking.md) |
| 现状体检：优势、缺陷清单、文档漂移 | [`docs/engine/audit.md`](docs/engine/audit.md) |
| 演进路线：阶段计划、UI 框架规格、验收指标 | [`docs/engine/roadmap.md`](docs/engine/roadmap.md) |

入口：[`docs/engine/README.md`](docs/engine/README.md)。

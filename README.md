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
| 外观 | 机台外壳、主题配色、启动动画、系统音效、字体、界面语言全是**内容包**，都可替换或新增 |
| 面向 agent | 画面即文本（无需截图与视觉模型）、带控制通道可注入输入与精确步进、卡带可自报玩法状态 |
| 联机 | 局域网联机内建：卡带可开房 / 加入 / 收发消息 / 自动发现（`phos.net`，见 `docs/api-reference.md`） |

## 快速开始

**玩**：解压后双击 `phosphor.exe`，方向键选卡带，`Enter` 进入；`Esc` 返回。
存档在 `saves/<卡带 id>.sav`，可用「磁带码」导出成一串文本带走。

**做一张卡带**：

```bash
phosphor --new carts/mygame --id mygame --name "My Game" --author "你"
phosphor --cart carts/mygame                    # 改完存盘直接跑，卡带不需要编译
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
mkdir build
cd build
cmake -G Ninja -DCMAKE_BUILD_TYPE=Release ..
ninja -j8
```

依赖已随仓库放在 `extern/`（glfw / lua / miniz / sol2 / imgui / stb / miniaudio），
不需要额外安装。构建后 `build/` 就是可直接分发的运行包。

**内容改哪里**：改卡带/主题/文档改 `package/` 与 `docs/` 下的源文件，构建时同步进 `build/`。
若运行目录里的同一份文件在上次同步之后被就地改过，构建会**跳过它并告警**（不会静默覆盖）——
要么把它拷回 `package/`，要么直接改 `package/` 再构建。

**排查内存类问题时**用自检构建：容器边界断言与栈保护让越界访问在**现场**停下并打印位置，
而不是过一会儿以"堆已损坏"的形式暴露在离元凶很远的地方。

```bash
cmake -G Ninja -DPHOSPHOR_SANITY=ON ../    # 自检构建：慢，只用于排查
```

**开发脚本**（`tools/`；除注明外都在含 `phosphor.exe` 的构建目录里跑）：

| 脚本 | 用途 | 跑法 |
|---|---|---|
| `run_checks.py` | **一键跑全部门禁并汇总**：默认无头门禁（unit/control/draw/layer/cart/net），`--gui` 再加开窗门禁。测试逻辑仍在各自脚本里，它只管调度与汇总 | `python ../tools/run_checks.py [--gui]` |
| `unit_smoke.py` | 纯逻辑单元测试：跑 `phosphor_tests`（C++，源码在 `tests/`），覆盖颜色/文本/配置/色板/主题等不依赖 GL·Lua 的核心——无窗口无显卡即可跑 | `python ../tools/unit_smoke.py` |
| `control_test.py` | 控制通道契约：握手 / 单步精确 / 读屏 / 注入 / 热重载 / 退出 | `python ../tools/control_test.py` |
| `window_smoke.py` | 窗口路径冒烟：菜单→开局→按键→单步 →**实时浸泡**→干净退出（确定性部分全走单步，只有最后几秒实时；需要图形环境） | `python ../tools/window_smoke.py [--seconds 3] [--cart carts/x]` |
| `cart_smoke.py` | 卡带冒烟：出厂卡带各跑一段，断言跑得完 / 不出错 / 有画面 / **同种子跑两遍逐字节一致**；不比对像素——画面本来就该随内容变 | `python ../tools/cart_smoke.py [--frames 3000] [--cart worms]` |
| `layer_smoke.py` | 图层契约：跑 devkit 的图层示例卡带，核对按 z 叠放、字形透出下层、浮窗盖住世界、整层显隐、按层读取；并核对没建层的卡带 `layers` 为空且 `merge_ms == 0` | `python ../tools/layer_smoke.py` |
| `draw_smoke.py` | 叠加与半格契约：跑 devkit 的叠加示例卡带，读像素核对"同格两笔的墨都在""`back_rect` 铺到字形之外""`plot` 的墨落在指定子位"，并核对叠画上限（需要 Pillow） | `python ../tools/draw_smoke.py` |
| `gl_smoke.py` | GL 渲染路像素门禁：开窗用 `frame.read` 读回真实帧，核对"不是全黑""同格两笔""半格""逐层叠画"——`screenshot` 走 CPU 光栅化，覆盖不到着色器与图层叠画（需要图形环境与 Pillow） | `python ../tools/gl_smoke.py` |
| `net_smoke.py` | 联机契约：同机起两个 `phosphor` 进程，一个开房一个加入（走 `phos.net` 与局域网发现），核对连接、对端列表、消息互通、断开事件（headless 即可，无需图形环境） | `python ../tools/net_smoke.py` |
| `agent_play.py` | 通用 agent 玩家：开真窗口、在卡带架上挑一张卡带、按卡带自报的 `debug_state()` 操控它玩（策略用 `--policy` 接自己的文件，流速用 `--speed` 设，默认实机流速） | `python ../tools/agent_play.py [--shelf-cart bricks] [--cart carts/x] [--steps 40] [--speed 1]` |
| `agent_shell_demo.py` | 端到端操控系统界面：设置 / 插拔卡 / 暂停 / 磁带码 | `python ../tools/agent_shell_demo.py` |
| `clean.py` | 清运行目录里的临时物（日志 / 截图 / 演示存档区 / 纯测试产物 `phosphor_tests`），不碰设置、存档与运行主机所需的构建产物 | `python ../tools/clean.py` |
| `make_icon.py` | 由 `theme/icon/phos_icon.jpg` 生成 exe 用的多尺寸 `.ico`（换 exe 图标时跑一次并把 `.ico` 提交；窗口图标不受影响）。路径按脚本位置解析，任意目录可跑，需 Pillow | `python tools/make_icon.py` |
| `phos.py` | 上面几个脚本共用的控制通道客户端库，不单独运行 | — |
| `sync_package.cmake` | 构建期把 `package/` 与 `docs/` 同步进构建目录（由 `assemble_package` 目标调用，规则与告警见文件头） | 随构建自动执行 |

## 目录

| 目录 | 内容 |
|---|---|
| `src/` | 主机源码（C++17） |
| `package/` | 随包分发的内容：`carts/` 出厂卡带、`devkit/` 工具链与模板、`theme/` 内容包、`mods/` 覆盖层 |
| `docs/` | **使用文档**：玩家手册 / 卡带作者手册 / API 参考 / 格式与内容包 / agent 接口 |
| `design/` | 开发期设计文档与计划（不随发行包发布） |
| `tools/` | 开发脚本（自测、演示、构建期同步） |
| `tests/` | C++ 纯逻辑单元测试（`phosphor_tests` 目标；由 `run_checks.py` 的 unit 门禁调用） |
| `build/` | 构建产物，**同时就是可直接分发/试玩的运行目录**：`carts/ devkit/ theme/ mods/ saves/ docs/` 与 exe 同级，全部是真实文件（不含任何路径联接） |

## 文档

| 你想 | 去看 |
|---|---|
| 玩：启动、操作、设置、存档与磁带码 | [`docs/playing.md`](docs/playing.md) |
| 做卡带：五分钟上手 + 踩坑清单 | [`docs/devkit.md`](docs/devkit.md) |
| 查 API：每个 `phos.*` 调用 | [`docs/api-reference.md`](docs/api-reference.md) |
| manifest 字段、生命周期、沙箱 | [`docs/cart-format.md`](docs/cart-format.md) |
| 主题 / 皮肤 / 语言 / Mod | [`docs/content-packs.md`](docs/content-packs.md) |
| 脚本与 agent 接口 | [`docs/agent-interface.md`](docs/agent-interface.md) |

全部文档的入口：[`docs/README.md`](docs/README.md)。

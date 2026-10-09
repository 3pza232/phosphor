# PHOSPHOR

**一台字符构成的幻想游戏机。**

卡带是几个 Lua 文件——写完存盘就能玩，不用编译；画面是纯文本字符网格，
人和 AI 都能直接读懂。

---

## 它是什么

| | |
|---|---|
| 形态 | 绿色免安装的单文件主机（`phosphor.exe`），双击即用 |
| 画面 | `80x45` 字符网格 + 显像管后处理（扫描线、孔径格栅、辉光、滤镜色调） |
| 卡带 | 一个文件夹或一个 `.phos` 单文件，丢进 `carts/` 就被扫到；Lua 沙箱，碰不到文件系统与网络 |
| 外观 | 机台外壳、配色滤镜、启动动画、系统音效、字体、界面语言全是**内容包**，都可替换或新增 |
| 面向 agent | 画面即文本（无需截图与视觉模型）、带控制通道可注入输入与精确步进、卡带可自报玩法状态 |

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
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
```

依赖已随仓库放在 `extern/`（glfw / lua / miniz / sol2 / imgui / stb / miniaudio），
不需要额外安装。构建后 `build/` 就是可直接分发的运行包。

## 目录

| 目录 | 内容 |
|---|---|
| `src/` | 主机源码（C++17） |
| `package/` | 随包分发的内容：`carts/` 出厂卡带、`devkit/` 工具链与模板、`theme/` 内容包、`mods/` 覆盖层 |
| `docs/` | **使用文档**：玩家手册 / 卡带作者手册 / API 参考 / 格式与内容包 / agent 接口 |
| `design/` | 开发期设计文档与计划（不随发行包发布） |
| `tools/` | 开发脚本（自测、演示、构建期同步） |
| `build/` | 构建产物；运行包中 `carts/ docs/ theme/ mods/ devkit/` 是指向源码的联接 |

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

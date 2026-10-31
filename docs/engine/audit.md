# PHOSPHOR 引擎现状体检

> **定位**：引擎实现文档，不随发行包发布。本文件回答"现在是什么样、哪里不成立"，
> 后续计划见 [roadmap.md](roadmap.md)。
>
> **方法**：通读 `src/`（135 个 C++ 文件，20,119 行）、`docs/`（15 篇，4,983 行）、
> `package/`（卡带 17,694 行 Lua / 内容包 3,499 行）、`tests/`、`tools/`；
> 运行构建产物与全部门禁；结论一律带 `file:line`，可逐条复核。
> 声称"专业/规范"但不成立的条目，在这里一律按**缺陷**记，不按风格建议记。
>
> **第二轮更新（2026-10，UI 组件层落地后）**：已修条目在 §3.1 标 ✅ 并附证据；§3.3 的 UI
> 缺位已由 `src/ui/` 与 `phos.ui.render` 补上，仍缺的迁移与场景栈逐条保留；§4 的 22 处文档
> 漂移逐条标"已修正 / 仍待代码修"。**不要删旧条目**——清单的价值在于可追溯。

---

## 一、项目形态（量化）

| 维度 | 现状 |
|---|---|
| 引擎 | C++17 / OpenGL / GLFW / Lua(sol2)，135 文件 20,119 行 |
| 分层规模 | core 6,588 · ui 1,310 · render 1,467 · api 2,867 · shell 2,464 · cart 1,248 · net 901 · platform 885 · agent 854 · pack 864 · devkit 468 |
| 画面模型 | 80x45 内容区 + 皮肤外壳；格 / 半格 / 叠笔 / 独立底色 / 最多 6 层；CPU 与 GL 两条光栅路径；声明式界面（ui 层）叠在其上 |
| 卡带 | 目录或 `.phos`；Lua 沙箱（无 IO、无裸 socket）；看门狗 100 ms/调用（卡带 + 全部内容包脚本） |
| 内容包 | skin 11 · palette 11 · boot 16 · sound 8 · shelf 2 · font 1 套方案（另有 icon） |
| 卡带内容 | 11 张出厂卡带，17,694 行 Lua；最大 `worms/main.lua` 3,271 行 |
| 文档 | 发行文档 7 篇 + 引擎文档 8 篇（含本文件与 roadmap.md），4,983 行；双层（发行 / 引擎）分界清楚 |
| 测试 | `tests/` 75 个用例（1,473 行，含 UI 布局/焦点 6 条；外壳 UI 迁移用例整合中）；`tools/` 17 个 Python 脚本共 2,769 行，无头门禁 9 项全绿 |
| API 世代 | `kVersion = 0.9.0`，`kPhosApiVersion = 7`，`--check-api` 134/134 一致 |

一句话形态：**一台把"字符网格 + 内容包 + Lua 沙箱 + agent 控制通道"做得很扎实的字符主机；
第二轮已立起共享 UI 组件层与卡带声明式界面——"主机界面逐屏手绘、卡带界面逐卡复制"的
两个根因被移除，但外壳其余屏与出厂卡带的迁移仍在进行。**

---

## 二、已经成立的设计资产（后续演进不得推翻）

1. **绘制模型有唯一抽象**：`Screen` 是逻辑网格，渲染器/文本导出/截图都只是消费者；
   `Surface` 收口了"越界裁剪、宽字占格、省略底色"三件事（`core/surface.hpp:12-21`）。
   同一语义只有一份实现，这是全项目最值钱的结构。
2. **单一真源意识强**：内容区矩形只由皮肤几何算（`core/skin.hpp:56-61`）；
   面板宽度只有一个合法化点（`core/defaults.hpp:25`）；文本宽度只有一份（`core/text.hpp:14`）；
   产品名/版本只有一处（`core/version.hpp`）。
3. **分层骨架基本成立**：`sol2/lua` 只出现在 api/cart/pack/devkit；`glad/GL` 只出现在
   render/platform（实测 include，无第五处违规）。例外见 §3.2。
4. **绘制能力边界清楚**：半格、叠笔、独立底色、图层都是"引擎能力"而非卡带技巧，
   且各自有契约门禁（`tools/draw_smoke.py`、`tools/layer_smoke.py`）。
5. **agent 接口是差异化资产**：文本读屏零 OCR、单步确定性、输入注入与玩家同源、
   `debug_state()` 结构化遥测、协议带版本（`docs/agent-interface.md`）。
6. **内容包与 Mod 体系**：六类包共用"扫描 → 校验 → 回退"骨架，Mod 用显式覆盖表，
   坏包只降级不崩（`pack/content_library.cpp:42-73`）。
7. **卡带侧规则/渲染分离已成事实**：`game/world/board` 不读输入、不画屏、不出声；
   `main` 只做输入→意图与绘制；`panel` 只读渲染。这是新增 UI 层最好的落点。
8. **工程纪律可执行**：命名、include 顺序、文件职责、注释哲学都写成了规范，
   并且大多数文件确实遵守；门禁脚本能挡住绘制/图层/控制/联机/界面回归。
9. **界面只有一套实现**（第二轮新增）：`src/ui/` 的布局 / 控件 / 焦点 / 主题被外壳与卡带
   共用——设置屏与错误屏已迁到组件树，卡带侧 `phos.ui.render` 是同一实现的 Lua 绑定；
   `tools/shell_golden.py` 用逐字节文本基线守住外壳迁移前后的一致性。

---

## 三、缺陷清单

### 3.1 正确性与健壮性（P0：用户会看见）

| # | 现象 | 证据 | 影响 | 状态 |
|---|---|---|---|---|
| C1 | `packs_.boots[0]` 未判空 | 旧：`core/app.cpp:119`、`core/app_intent.cpp:99`；`pack/content_library.cpp:54-56` 对 boots 没有内置兜底 | 从错误工作目录启动（或删掉 boot 包）→ 未定义行为，直接崩；与"磁盘上一个包都没有也能开机"相反 | ✅ **已修复**：`pack/content_library.cpp:58` 空表时插内置项（`dir` 为空）；`core/app.cpp:350` 空 dir 不加载脚本、走内置自检动画；启动日志因此不再越界 |
| C2 | 存档先改内存再整文件覆盖写 | 旧：`cart/save_store.cpp:61-88`（`set/erase` 先 `data_` 后 `flush`）、`flush` 用 `trunc` | 写失败/掉电：读到的值与磁盘不一致；写到一半崩会连同旧档一起毁掉 | ✅ **已修复**：`cart/save_store.cpp:111-130` 写 `.tmp` → flush/close → rename，失败保留旧档；用例 `save_store_failed_write_keeps_old_value` |
| C3 | 配置写盘非原子，theme 字符串未转义 | 旧：`core/config.cpp:128-142`（直接拼 `"` + 值 + `"`，同路径截断） | 掉电丢设置；skin/boot 名带特殊字符即产出坏 JSON | ✅ **已修复**：`core/config.cpp:29-56` 原子写（tmp + rename）、`:164-186` 全部字符串走 `json::quote`；用例 `config_atomic_write_*` / `config_escapes_special_names` |
| C4 | 卡带错误无 chunk 名、无 traceback | 旧：`cart/cartridge.cpp:318,354` 未传 chunk name；全工程无 traceback | 多文件卡带的报错只有源码前缀 + 行号，难以定位 | ✅ **已修复**：入口/模块脚本以 `"@<id>/<path>"` 作 chunk 名（`cartridge.cpp:36-37,292-293`；`pack.cpp` 同理）；实测运行时错误输出含 `<id>/lib.lua:2` 与完整 `stack traceback` |
| C5 | 看门狗只护卡带 | 旧：只有 `cartridge.cpp:315` 挂 hook；`parse_manifest` 与 `pack/pack.cpp` 六类包脚本无 hook | manifest 里一个 `while true` 即可冻结启动/换卡 | ✅ **已修复**：`api/lua_guard`（指令计数钩子 + `BudgetScope`，100 ms/次）覆盖卡带入口、`manifest.lua`（`cartridge.cpp:34-35`）与全部内容包脚本（`pack.cpp:47-48` 及 6 处 `BudgetScope`） |
| C6 | `time.step` 的在途回包可被丢弃 | `core/app_control.cpp:452-458`：`time.resume` 直接清零 `step_request_id`、`pending_steps` | agent 端的同步点永远等不到回包（挂起）；违反 `agent-interface.md:126-127` | ❌ **仍待修** |
| C7 | 一帧由三条互不相同的合成路径产生 | `render/renderer.cpp:398-420`（GL 逐格/逐笔）；`render/screen_image.cpp`（CPU 截图）；`core/layered_screen.cpp`（文本投影） | 窗口里看得见的笔迹，在 `screenshot`/文本里消失 | ✅ **已修复**（273d090）：CPU 的底图 / 图层 / 主机 chrome 三条路径都按 GL 的 `pens` 趟画无字形槽格上的笔迹（`screen_image.cpp` 三处分支）；`drawing.md` 已改为"两路同规则" |
| C8 | 每帧做文本投影 | `core/app.cpp:223-228`：建层卡带每帧 `display_.base = display_.screen` 深拷贝 + `merge_over`，而渲染不读它 | 有层卡带每帧白付一次全屏拷贝与合并；`merge_ms` 测的就是这份浪费 | ❌ **仍待修**（已限定在 `layers.active()`，但每帧仍做） |
| C9 | 字体热重载失败回滚不完整 | `render/renderer.cpp:256` 打包成功后即改写 `fonts_`/`glyphs_`，随后 `:286-290` 的 `glGenTextures` 失败只回滚纹理 | 失败后 UV 与旧纹理错位，字形乱码且无法自愈 | ❌ **仍待修**（字体链装载失败已安全回退；GPU 侧失败路径未回滚） |
| C10 | `Screen::blend` 不校验宽字续格/被覆盖格 | `core/screen.cpp:188-205`：宽字笔迹拒绝；目标格 `cols == 0` 或 `scale == 0`（无字形槽）也拒绝 | 同一笔"返回成功却只在窗口可见" | ✅ **已修复**（273d090）：无字形槽的格上 `blend` 直接返回 false、日志只报一次；契约写进 `drawing.md` §3.1（叠笔只能落在有字形槽的格上） |
| C11 | 内容根 = 进程当前目录 | `pack/content_library.cpp:13-22`、`core/app.hpp` 的固定相对路径；无 `--root` | 从资源管理器/CI/快捷方式以别的目录启动 → 无内容；与"绿色免安装、双击即用"冲突 | ❌ **仍待修** |
| C12 | 窗口模式下 `--cart` 装载失败仍返回 0 | 旧：`core/app.cpp:495` 之后无失败返回，结尾恒 `return 0` | 脚本无法用退出码判断失败 | ✅ **已修复**：`core/app.cpp:417-420`（无头）与 `:498-501`（窗口）装载失败均 `return 2` |
| C13 | NDJSON 里的 `\uXXXX` 转义被丢弃 | 旧：`core/json_lite.cpp:53-57` 直接跳过四位 | 标准 JSON 客户端注入中文时字符消失 | ✅ **已修复**：`core/json_lite.cpp:102-154` 解 `\uXXXX` 并按代理对合并（非法/孤立代理报错）；用例 `json_unicode_*` |
| C14 | 联机的 `join`/`discover` 阻塞主线程 | `net/net.cpp:641`（TCP 连接超时 3 s）、`:740-787`（发现阻塞到 timeout） | 卡带在 `update` 里调用即超 100 ms 看门狗 | ❌ **仍待修**（文档已改为如实描述"有界阻塞"） |
| C15 | 控制通道缺乏活性与背压 | `agent/control_channel.cpp:176-177`（accept 失败即退出）、`:251`（backlog 1）、`:120-140`（回包持锁阻塞） | 通道"看起来开着、实际已死"；慢客户端拖住命令处理 | ❌ **仍待修** |
| C16 | Lua `print` 并未重定向到主机日志 | 旧：沙箱未替换 `print`；文档却声明重定向到日志/控制台 | 卡带打印污染 `--dump-screen`/脚本管道输出 | ✅ **已修复**：`api/lua_guard.cpp:30-43,72-77` 把 `print` 换成 `[cart]`/`[pack]` 前缀的 `log::info`（`cartridge.cpp:289`、`pack.cpp:48`）；不再写 stdout |

### 3.2 结构与边界（P1：让每个新功能都变贵）

> **第二轮状态**：以下 S1–S11 均未作为结构重构处理（UI 层是**新增**，没有反过来清理这些
> 债）；S11 因新组件层出现而**部分缓解**（新的 Lua 绑定只做值/事件转换），旧原语绑定仍在。

| # | 现象 | 证据 | 后果 |
|---|---|---|---|
| S1 | `App` 是 2,179 行 / 7 个 TU / 54 方法的上帝对象，且**住在最低层** `core/` | `core/app.hpp:3-20` 反向 include `cart/ pack/ shell/ agent/ net/ api/`，于是 core 头文件把 sol2 拉进整棵依赖树 | 任何接触 App 的 TU 都编译 Lua 宿主；"可替换子系统"实际上被 App 焊死 |
| S2 | 模式不是状态机 | `playing_/in_boot_/quit_`（`app.hpp:172-176`）与 `ShellMode` 由 5 个文件分别写 | 非法状态组合可表示；`state.query.mode` 不可信；弹窗/暂停类功能只能继续加布尔量 |
| S3 | 选择状态有 3~4 份副本 | `Config` 字符串、`ContentLibrary` 下标、`Shell` 自带名字/下标（`shell/shell.hpp:271-286`）、字体状态 4 处 | 每次改设置手工三方同步，17 处 `save_config_now()` 即其症状 |
| S4 | `HostContext` 是 15 个裸指针的手工生命周期 | `api/host_api.hpp:26-71`；`clear_host_cart()` 有 9 个手工调用点（`app.cpp:176,273,295,347,354` 等） | 新增子系统就要再加一处"记得清空"；错一次就是悬垂指针 |
| S5 | `cart` ↔ `api` 头文件环 | `cart/cartridge.hpp:3` include `api/host_api.hpp`，`api/host_api.hpp:3` include `cart/save_store.hpp` | 依赖方向与 `architecture.md:43-46` 相反；一行前向声明即可断开 |
| S6 | 三份帧步进、三份沙箱、三份本地化解析 | `app.cpp:442-448 / 546-551 / 554-560`；`cartridge.cpp:56-62,299-311` 与 `pack.cpp:33-43`；`cartridge.cpp:82-98`、`pack.cpp:47-60,287-296` | 三处已开始分叉（无头路径少一次 `complete_frame_read`）；策略分散，改一处漏两处 |
| S7 | `Screen` 过载 | `core/screen.hpp:22-190`：存储 + 宽字续格 + 缩放块 + 稀疏笔迹 + 子位累积 + alpha + 文本导出 | 每个新绘制特性都要改它并同时改三条消费路径；不变式从公共写入口漏出（C10） |
| S8 | 反向依赖 `pack → render` | `pack/pack.cpp:8` include `render/font.hpp`；`FontScheme` 定义在 `pack/pack.hpp:95-101` | 与 `architecture.md:127-129` 相反；字体方案想独立演进就会被 pack 拖住 |
| S9 | 全局可变状态 | `core/log.cpp:13-15`、`platform/window.cpp:23`、`core/mods.cpp:11-20`、`cartridge.cpp:24-25` | 与 `code-style.md:70` 冲突；不可重入，无法并行跑两台主机/两个测试 |
| S10 | 底层健壮性未收口 | `core/config.cpp:128-142`（非原子）、`core/json_lite.*`（转义/窄化，待补测试）、`platform/socket` 无 SIGPIPE 处理 | 设置/日志/联机在异常路径的失败方式不可预测 |
| S11 | Lua 绑定层重复而非抽象 | `api/host_api.cpp:82-132`（screen/panel）、`api/ui_api.cpp:129-195`（region）、`api/ui_api.cpp:37-116`（顶层 ui）、`api/draw_region.cpp:122-162`（frame/divider/bar/menu/body/sprite 各写一遍） | 一处语义修正要改三到四处；`sprite.step` 的"缩放/downsample"分歧就是这么来的（`core/ui.cpp:149` vs `api-reference.md:300`） |

### 3.3 UI 层（第二轮：组件层已立，迁移进行中）

**现状清单（2026-10 第二轮后）**：`src/ui/` 共 8 文件 1,310 行——`element`（元素种类 /
`Props` / `Node`）、`layout`（测量 / 排布 / 焦点收集）、`frame`（`run` 输入+事件、`paint`
写屏、按 screen id 的跨帧状态）、`theme`（颜色角色 / 字形集 / 度量）——只依赖 `core/`。
外壳的**设置屏与错误屏**已迁到组件树（`shell/settings_view.cpp` 只把数据填进 `ui::Node`）；
卡带侧 `phos.ui.render` 已随 API 世代 7 发布（`api/ui_render`，与外壳共用 `ui::Frame`）。
旧的 `core/ui` 原语（9 个无状态绘制函数 + `ui::Style`）仍作为底层保留；
**出厂卡带与外壳其余 5 屏尚未迁移**。

| # | 现象 | 证据 | 状态 |
|---|---|---|---|
| U1 | 外壳每一屏各自排版 | 设置 / 错误两屏已组件化；暂停 / Mod / 磁带码 / 卡带架 / 自检正陆续接到组件树（部分已用 `ui::Frame`，整合与基线重生成待完成）；旧版面常量仍在 | ⚠ **进行中**（设置 / 错误已完成） |
| U2 | 卡带几乎不用"组件" | 全 11 张卡带中 `phos.ui.render` 使用 0 次；旧原语 `ui.frame` 6 次、`ui.nav` 2 次；`panel.print` 192 次、屏幕/面板原始绘制调用 333 处 | ❌ **仍待修**（新 API 可用，卡带未迁） |
| U3 | 因此每张卡带复制界面 | 侧栏头 12 份、手写选择列表 8 份、不透明浮窗 6 份、设置/选项菜单 3 套、帮助屏 3 份、暂停处理 8 份、最高分持久化 6 份；文案表 54 张 / 617 行 | ❌ **仍待修** |
| U4 | UI 规模占比高但复用率为零 | 卡带 UI 代码 ≈2,500 / 17,694 行，其中 `panel.lua` 1,036 行 + `hud.lua` 294 行；主程序内浮层 ≈600 行 | ❌ **仍待修** |
| U5 | 规范与现实相反 | `code-style.md` 要求"界面绘制只用组件原语"，过去组件集不存在；现在 `src/ui` 已可满足，但内容集还没改用 | ⚠ **部分修复**（规范可执行，内容未迁） |
| U6 | agent 只能读"光标数" | 卡带声明式界面已暴露 `state.query.ui` 与 `ui.list/focus/activate`（控件 id/role/label/state）；外壳界面仍只有 `cursor` | ⚠ **部分修复**（卡带侧已可寻址；外壳未接） |
| U7 | 主题只有颜色 | `ui::Theme` 已含颜色角色（text/text_dim/accent/warning/danger/disabled/border_focus…）、边框 / 光标字形集、度量；可替换的 `ui` 内容包未做 | ⚠ **部分修复** |
| U8 | 绘制几何缺失 | 仍没有线 / 框 / 圆 / 环的独立 API；UI 组件只覆盖"界面常用件"（边框 / 进度条 / 分隔线），卡带仍各自逐格光栅化（`ballbattle/main.lua`、`towerdef/view.lua`） | ❌ **仍待修** |
| U9 | 文本框只有缓冲、没有控件 | `ui::Frame` 的 field 控件已做焦点 / 光标 / 过滤 / 按码点退格 / 限长；**声明式文本域尚未向主机请求 IME**（`Frame::ime_requested` 未接线），中文输入仍要等接线 | ⚠ **部分修复**（控件已立；IME 未接） |
| U10 | 精灵语义与文档不一致 | `ui::icon` 的 `step` 仍是**降采样步长**（`core/ui.cpp`），文档已按实现改写（`api-reference.md` 与 `devkit/phos.lua`）；绑定层仍硬编码亮度 1.0，语义统一未做 | ⚠ **文档已对齐、代码待统一** |
| U11 | 参数与单位校验缺失 | `ui::bar` 对 NaN 仍直接 `static_cast<int>`（`core/ui.cpp`）；`ui.sprite` 的宽高仍按字节算（`api/ui_api.cpp`） | ❌ **仍待修** |

### 3.4 卡带工具链与内容（P2：负担最终落在作者身上）

| # | 现象 | 证据 |
|---|---|---|
| K1 | 模板用 40 行"十条约定"解释绘制模型 | `devkit/template/main.lua:12-51`——学习成本被写进了骨架 |
| K2 | 存档是字符串 KV（键 ≤64、值 ≤4096、条目 ≤256），无结构/版本/槽位 | `cart/save_store.hpp`；代价是 towerdef 约 220 行 RLE 编解码 + 19 字段记录（`carts/towerdef/game.lua:567-888`） |
| K3 | Mod 只能整文件覆盖 | `mods/towerdef-build-pause/main.lua` 是 646 行整文件 fork（本体 617 行），只改约 10 行；mod 自己头部承认会腐烂 |
| K4 | 没有共享词表/格式化 | 11 张卡带各写 `SCORE/BEST/PAUSED/RESTART` 两列，617 行；没有 `phos.text.score/clock`，没有键位提示组件 |
| K5 | 没有结构化观测约定 | `debug_state()` 各卡手搓（worms 约 200 行、towerdef/crawl 各约 60 行），字段名无约束 |
| K6 | 层上限 6 已被用满 | worms 已用 6 层（`carts/worms/main.lua:532-537`）；再加"UI/调试覆盖层"就是错误 |
| K7 | `--check-api` 只比对"名字" | `devkit/api_check.cpp:159-171`：实装/注解的函数名与 `@field` 名一致即通过，无法发现语义漂移（`center_text` 忽略可玩区、`sprite` 丢亮度参数） |
| K8 | 卡带内仍允许隐式全局 | `carts/towerdef/main.lua:20` 的 `menu_rows`、`carts/worms/main.lua:1010` 的 `fire`；无 lint 拦截 |

> **第二轮状态**：K1 部分缓解（模板 `panel.lua` 已改用声明式界面；`main.lua` 仍是"十条约定"）；
> K2–K6、K8 仍在；K7 未变（`--check-api` 仍只校验名字与 `@field` 名，不校验语义）。

### 3.5 工程化（P2：让前面所有问题持续复发）

| # | 现象 | 证据 |
|---|---|---|
| E1 | 无 CI、无格式化、无静态分析、无 CMake preset | 仓库无 `.github/`、`.clang-format`、`.clang-tidy`、`CMakePresets.json` |
| E2 | 门禁强在"行为契约"，弱在"模型单元" | 6 项门禁全绿；但 51 个单测集中在颜色/文本/配置/色板/图层合并，`Screen` 宽字/缩放/孤儿格、`blend` 边界、存档耐久、模式迁移、包优先级都没有直接用例 |
| E3 | 无像素 golden 回归 | `gl_smoke.py` 只有少量断言（不是全黑/同格两笔）；外壳每屏的版面没有基线 |
| E4 | 无性能预算与基准 | 没有每帧绘制/合并/布局的阈值断言；`merge_ms` 只是观测 |
| E5 | 版本与依赖不可追溯 | `version.hpp` 同时兼任 CHANGELOG；`extern/` 第三方库版本无清单 |
| E6 | 文档漂移靠人眼 | 见 §4；没有把"数值/签名/规则"与代码比对的机械门禁（`--check-api` 只覆盖注解） |

> **第二轮状态**：E1 **部分修复**（`.github/workflows/ci.yml`、`CMakePresets.json`、
> `.editorconfig` 已加；`.clang-format` / `.clang-tidy` / 覆盖率仍未）；E2 **改善**
> （门禁 9 项、单测 75 条，新增 UI 布局/焦点、存档耐久、JSON 转义用例；模式迁移/包优先级
> 仍无用例）；E3 **部分**（`tools/shell_golden.py` + `tests/golden/shell/` 已建 9 屏文本基线，
> 像素基线仍未）；E4/E5 未变；E6 **部分**（`tools/check_includes.py` 机械核查 include 方向，
> "数值/签名"仍靠人眼）。

---

## 四、文档 ↔ 实现漂移（已逐条复核）

| 文档声称（修正前） | 实际 | 状态 |
|---|---|---|
| `architecture.md:300-301`：磁盘上一个内容包都没有也能开机 | boots 为空即 UB（§3.1 C1） | ✅ **已修正**；C1 已修（`content_library.cpp:58`、`app.cpp:350`） |
| `architecture.md:105`：CRT 有暗角/畸变 | 着色器只有扫描线/孔径格栅/辉光/亮度补偿/色调（`render/renderer.cpp:49-100`） | ✅ **已修正** |
| `architecture.md:127-129`：`pack/` 不向上依赖 `render/` | `pack/pack.cpp:9` include `render/font.hpp` | ✅ **文档已记为债务**（S8）；代码仍待改 |
| `architecture.md:43-46`：`cart/` 只可复用 `api/lua_value.hpp` | `cart/cartridge.hpp:3` include `api/host_api.hpp`（头文件环） | ✅ **文档已记为债务**（S5）；代码仍待改 |
| `architecture.md` 分层图（旧） | `core/app.hpp` 反向 include 全层；render ↔ core 互依 | ✅ **已修正**（本轮补 `ui` 层与组装点说明） |
| `architecture.md:315`：渲染后端按"可换 Vulkan"设计 | 接口是具体 `Renderer` + 内联 shader 字符串；无抽象缝 | ✅ **已修正**（改写为"目标，未做"） |
| `drawing.md:91`：GL 与 CPU 画的是同一张图 | 旧：续格/被覆盖格上的笔迹 GL 画、CPU 跳过（C7） | ✅ **已修正**；C7 已修（273d090），两路同规则 |
| `layers.md:66`：当前 API 世代 **5** | `core/version.hpp` 已到 **7** | ✅ **已修正**（世代 7） |
| `code-style.md:40`：可恢复错误返回 `std::expected` | 标准锁定 C++17，全工程无 `std::expected` | ✅ **已修正**（bool + err / optional） |
| `code-style.md:70`：不使用全局可变状态 | `core/log.cpp`、`platform/window.cpp`、`core/mods.cpp` 仍有 | ✅ **已修正**（改为"禁止新增 + 现存清单 + 迁移目标"） |
| `code-style.md:46-54`：注释不写改动史 | `version.hpp` 是发行日志；个别注释仍带改动史 | ✅ **已修正**（明确 version.hpp 是唯一例外；个别代码注释待清） |
| `api-reference.md`（旧）：键盘/手柄输入在此统一 | 无任何手柄/joystick 代码 | ✅ **已修正**（写明仅键盘 + agent 注入） |
| `devkit.md:258`：`debug_state` 支持"一层表" | `cartridge.cpp` 按深度 4 序列化 | ✅ **已修正** |
| `cart-format.md:79-80`：入口脚本缺失会显示为损坏卡带 | 扫描阶段只读 manifest；装载时才失败 | ✅ **已修正**（改成实际行为 + 打包器校验） |
| `content-packs.md:69`：包缺失"回退 + 日志警告" | skin/boot/sound/palette 选中缺失静默回退，只有 shelf 告警 | ✅ **文档已修正**；代码侧"补日志"仍待做 |
| `agent-interface.md:126-127`：`time.step` 推进完才回包 | `time.resume`/退出会丢弃在途回包（§3.1 C6） | ❌ **文档无误，仍待代码修** |
| `theme/boot/README.txt`：13 个动画、任意键跳过 | 实际 16 个包；跳过是 A/Esc（自检屏 Enter/Esc） | ✅ **已修正** |
| 代码注释引用"roadmap 第 8 条" | 原报告不存在（现 roadmap.md 也不是当时所指） | ❌ **代码注释仍待修**（`defaults.hpp`、`assets_api.cpp`、`audio.cpp`） |
| `api-reference.md:462`、`networking.md:97`：联机在后台线程、主线程不阻塞 | `join`/`discover` 在主线程有界阻塞（C14） | ✅ **文档已修正**（如实写明有界阻塞）；C14 仍待代码修 |
| `api-reference.md:611-612`：主机自带搜索框收不到中文 | `app.cpp:283` 在搜索编辑时置 `ime_wanted`，即**会**请求输入法 | ✅ **文档已修正**；`host_api.hpp` 注释仍待修 |
| `cart-format.md:119`：Lua `print` 重定向到主机日志 | 旧：未替换 `print`（§3.1 C16） | ✅ **已修正**；C16 已修（`lua_guard`） |
| `api-reference.md:300`：sprite 的 `step` 为缩放步长 | 实现是降采样（§3.3 U10） | ✅ **文档已按实现修正**；语义统一仍待代码（U10） |

## 五、能力缺口（对照"专业主机"）

| 领域 | 缺什么 | 被什么挡住 |
|---|---|---|
| UI | 已补：布局 / 容器 / 控件 / 焦点 / 主题 token / 文本域；仍缺：场景栈与弹窗栈、表格、Toast、模态输入捕获 | §3.3（出厂卡带与外壳其余 5 屏未迁） |
| 场景 | 屏幕/弹窗栈、模态输入捕获、暂停与音频联动 | 外壳 `ShellMode` + 卡带各自状态机 |
| 输入 | 动作映射、重绑定、手柄、焦点丢失释放、按键重复 | 只有裸键名（`core/input.hpp`） |
| 存档 | 结构化值、schema 版本/迁移、槽位、原子写、CRC | 字符串 KV + 非原子写 |
| 内容 | 包清单统一校验、依赖/版本、预览、UI 主题包、热重载 | 六类包各自解析；Mod 需重启 |
| 渲染 | 已补：三条路径画同一张图（C7）；仍缺：单一合成器、绘制 IR、批处理、像素 golden | 三套消费代码仍各写一遍 + 内联管线 |
| 音频 | 声部优先级/抢占、淡入淡出、ducking、流式、总线 | 现有混音器只有波形/包络/采样 |
| 工具 | watch 热重载、卡带 lint、截图基线工具、包校验 | devkit 只有 new/pack/check-api |
| 观测 | 已补：卡带声明式界面的控件树（`state.query.ui` + `ui.*`）；仍缺：外壳控件树、性能预算、崩溃报告 | 外壳仍靠 `cursor`；其余靠手搓 debug_state |
| 治理 | CI、格式化、静态分析、覆盖率、版本政策 | 无 |
| 协议 | 统一 JSON（`\u`/代理对/非有限数/上限）、非阻塞联机、控制通道超时/背压/明文错误码 | 两套 socket 栈、手拼 JSON、阻塞调用 |

---

## 六、结论：瓶颈不在"功能数量"

第二轮之后，结论要改写一半——**第 1 项已经动手并落地，第 2、3 项仍是主矛盾**：

1. **界面组件层已立**（`src/ui/` + `phos.ui.render`）：外壳与卡带共用同一套布局/焦点/主题，
   agent 能按 id 读控件树。剩下的不是"有没有"，而是**迁移**——外壳 5 屏、11 张出厂卡带
   仍走旧路径（§3.3 U1–U4），场景栈/模态/表格/Toast 还没做。
2. **边界与真源仍欠**（§3.2 S1–S11）：App 住在最低层、状态分散、HostContext 手工清指针、
   包/字体/卡带之间的三处反向依赖——UI 层是**新增**的，没有反过来清理这些债；不修它们，
   下一次迁移仍会被拖慢。
3. **工具与门禁仍欠**（§3.5 E2–E6）：include 门禁、9 项行为门禁、外壳文本基线已立；
   但**语义级**检查（数值/签名/规则）、像素基线、性能预算仍缺；文档漂移靠人眼的问题
   只是从"22 处"变成"有清单"。

因此后续方向不变、但顺序更清楚：
**先把 UI 层迁移跑完（M2/M3），同时清 §3.2 的边界债（M0 剩余项），
再用语义门禁与像素基线锁死（§3.5）。** 具体阶段、顺序与验收见 [roadmap.md](roadmap.md)。
# PHOSPHOR 引擎现状体检

> **定位**：引擎实现文档，不随发行包发布。本文件回答"现在是什么样、哪里不成立"，
> 后续计划见 [roadmap.md](roadmap.md)。
>
> **方法**：通读 `src/`（123 个 C++ 文件，17,350 行）、`docs/`（3,709 行）、
> `package/`（卡带 17,603 行 Lua / 内容包 3,499 行）、`tests/`、`tools/`；
> 运行构建产物与全部门禁；结论一律带 `file:line`，可逐条复核。
> 声称"专业/规范"但不成立的条目，在这里一律按**缺陷**记，不按风格建议记。

---

## 一、项目形态（量化）

| 维度 | 现状 |
|---|---|
| 引擎 | C++17 / OpenGL / GLFW / Lua(sol2)，123 文件 17,350 行 |
| 分层规模 | core 6,268 · render 1,450 · api 2,209 · shell 2,084 · cart 1,204 · net 899 · platform 879 · agent 846 · pack 845 · devkit 464 |
| 画面模型 | 80x45 内容区 + 皮肤外壳；格 / 半格 / 叠笔 / 独立底色 / 最多 6 层；CPU 与 GL 两条光栅路径 |
| 卡带 | 目录或 `.phos`；Lua 沙箱（无 IO、无裸 socket）；看门狗 100 ms/调用 |
| 内容包 | skin 11 · palette 11 · boot 16 · sound 8 · shelf 2 · font 1 套方案（另有 icon） |
| 卡带内容 | 11 张出厂卡带，17,603 行 Lua；最大 `worms/main.lua` 3,271 行 |
| 文档 | 发行文档 6 篇 + 引擎文档 7 篇（含本文件与 roadmap.md），3,709 行；双层（发行 / 引擎）分界清楚 |
| 测试 | `tests/` 51 个纯逻辑用例（861 行）；`tools/` 14 个脚本共 2,278 行，6 项门禁全绿 |
| API 世代 | `kVersion = 0.8.2`，`kPhosApiVersion = 6`，`--check-api` 128/128 一致 |

一句话形态：**一台把"字符网格 + 内容包 + Lua 沙箱 + agent 控制通道"做得很扎实的字符主机；
但"主机界面"仍是一组逐个手绘的屏幕，"卡带界面"仍是一堆逐卡复制的排版代码。**

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
   并且大多数文件确实遵守；门禁脚本能挡住绘制/图层/控制/联机回归。

---

## 三、缺陷清单

### 3.1 正确性与健壮性（P0：用户会看见）

| # | 现象 | 证据 | 影响 |
|---|---|---|---|
| C1 | `packs_.boots[0]` 未判空 | `core/app.cpp:119`、`core/app_intent.cpp:99`；`pack/content_library.cpp:54-56` 对 boots 没有内置兜底 | 从错误工作目录启动（或删掉 boot 包）→ 未定义行为，直接崩；与"磁盘上一个包都没有也能开机"（`architecture.md:300-301`）相反 |
| C2 | 存档先改内存再整文件覆盖写 | `cart/save_store.cpp:61-88`（`set/erase` 先 `data_` 后 `flush`）、`flush` 用 `trunc` | 写失败/掉电：读到的值与磁盘不一致；写到一半崩会连同旧档一起毁掉 |
| C3 | 配置写盘非原子，theme 字符串未转义 | `core/config.cpp:128-142`（直接拼 `"` + 值 + `"`，同路径截断） | 掉电丢设置；skin/boot 名带特殊字符即产出坏 JSON；无备份可回退 |
| C4 | 卡带错误无 chunk 名、无 traceback | `cart/cartridge.cpp:318,354` 未传 chunk name；全工程无 traceback | 多文件卡带的报错只有源码前缀 + 行号，难以定位；与"面向卡带作者"的目标不符 |
| C5 | 看门狗只护卡带 | 只有 `cartridge.cpp:315` 挂 hook；`parse_manifest`（`cartridge.cpp:56-62`）与 `pack/pack.cpp` 六类包脚本无 hook | manifest 里一个 `while true` 即可冻结启动/换卡；违反"主机永不因内容而死" |
| C6 | `time.step` 的在途回包可被丢弃 | `core/app_control.cpp:452-458`：`time.resume` 直接清零 `step_request_id`、`pending_steps` | agent 端的同步点永远等不到回包（挂起）；违反 `agent-interface.md:126-127` |
| C7 | 一帧由三条互不相同的合成路径产生 | GL 逐层画（会画续格/被覆盖格的笔迹，`render/renderer.cpp:398-405`）；CPU 截图先跳过这些格（`render/screen_image.cpp:209,227`）；文本投影又一份（`core/layered_screen.cpp`） | 窗口里看得见的笔迹，在 `screenshot`/文本里消失；`drawing.md:91`"两条路画同一张图"不成立 |
| C8 | 每帧无条件做文本投影 | `core/app.cpp:220-229`：深拷贝整屏 + 合并全部层，而注释与代码都说明渲染不读它 | 有层卡带每帧白付一次全屏拷贝与合并；`merge_ms` 测的就是这份浪费 |
| C9 | 字体热重载失败回滚不完整 | `render/renderer.cpp:232-245` 恢复旧纹理，但 `build_font_atlas` 在 `glGenTextures/glTexImage2D` 失败分支（`:286-293`）前已改写 `glyphs_` | 失败后 UV 与旧纹理错位，字形乱码且无法自愈 |
| C10 | `Screen::blend` 不校验宽字续格/被覆盖格 | `core/screen.cpp:190-203` 只校验半角与越界；两处渲染对这类格的处理不同（见 C7） | 同一笔"返回成功却只在窗口可见"，且会污染续格记账 |
| C11 | 内容根 = 进程当前目录 | `pack/content_library.cpp:13-22`、`core/app.hpp:145-152`、`devkit` 路径 | 从资源管理器/CI/快捷方式以别的目录启动 → 无内容（并触发 C1）；与"绿色免安装、双击即用"的发行形态冲突 |
| C12 | 窗口模式下 `--cart` 装载失败仍返回 0 | `core/app.cpp:495` 之后无失败返回，结尾 `:623` 恒 `return 0` | 脚本无法用退出码判断失败；`agent-interface.md:58` 的约定只在无头路径成立 |
| C13 | NDJSON 里的 `\uXXXX` 转义被丢弃 | `core/json_lite.cpp:53-57`（注释写明"命令参数不含非 ASCII"，直接跳过四位） | 标准 JSON 客户端注入中文 `input.text`/昵称时字符消失；协议面向任意语言调用（`agent-interface.md:124`）却只支持裸 UTF-8 |
| C14 | 联机的 `join`/`discover` 阻塞主线程 | `net/net.cpp:641`（TCP 连接超时 3 s）、`:740-787`（发现阻塞到 timeout，参数可到 5 s） | 违反 `api-reference.md:462`"运行在后台线程，主线程只入队/取队"；卡带在 `update` 里调用即超 100 ms 看门狗（worms 已在用） |
| C15 | 控制通道缺乏活性与背压 | `agent/control_channel.cpp:176-177`（accept 失败即退出后台线程，无上报）、`:251`（backlog 1）、`:120-140`（回包可阻塞 200 ms，持队列锁路径） | 通道"看起来开着、实际已死"；慢客户端会拖住命令处理；无 idle/hello 超时 |
| C16 | Lua `print` 并未重定向到主机日志 | 沙箱未替换 `print`；文档却声明"重定向到主机日志/控制台"（`cart-format.md:119`） | 卡带打印直接写 stdout，污染 `--dump-screen`/脚本管道输出；与"面向 agent 的干净数据流"冲突 |

### 3.2 结构与边界（P1：让每个新功能都变贵）

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

### 3.3 UI 层（本次要解决的核心问题）

**现状清单**：`core/ui` 共 257 行，只有 9 个**无状态**绘制函数
（`fill/print/print_centered/divider/frame/bar/menu/text_block/icon`）与一个 `navigate`
（`core/ui.hpp:39-66`）。此外只有 5 个平铺颜色（`ui::Style`）；没有布局、容器、控件状态、
焦点、裁剪栈、禁用/选中态、字形集、度量、弹窗栈、文本框控件。
卡带侧 `phos.ui`（`api/ui_api.cpp`）是这套原语的薄绑定 + `region` 裁剪矩形。

| # | 现象 | 证据 |
|---|---|---|
| U1 | 外壳每一屏各自排版 | 设置行手写坐标（`shell/settings_view.cpp:123-151`）；Mod 管理器手写勾选列表 + 自定义滚动动画（`shell/shell.cpp:707-745`）；磁带码分页/输入手写（`shell/tape_view.cpp`）；开机自检逐行打字（`shell/boot_view.cpp`）；卡带架轮播 14 个本模块布局常量（`shell/shelf_view.cpp:10-30`）。`ShellLayout` 只有 6 个常量（`shell/layout.hpp:9-17`），撑不起"统一布局" |
| U2 | 卡带几乎不用"组件" | 全 11 张卡带中 `phos.ui.menu` / `ui.bar` / `ui.text` / `ui.divider` 使用次数为 **0**；`ui.frame` 6 次、`ui.nav` 2 次；`panel.print` 192 次、屏幕/面板原始绘制调用 333 处 |
| U3 | 因此每张卡带复制界面 | 侧栏头 12 份、手写选择列表 8 份、不透明浮窗 6 份、设置/选项菜单 3 套、帮助屏 3 份、暂停处理 8 份、最高分持久化 6 份（`bricks/scores.lua` 与 `tetris/scores.lua` 字节相同）；文案表 54 张 / 617 行；`text.fit` 60 处、`text.pad` 24 处 |
| U4 | UI 规模占比高但复用率为零 | 卡带 UI 代码 ≈2,500 / 17,603 行（14%），其中 `panel.lua` 1,036 行 + `hud.lua` 294 行；主程序内浮层 ≈600 行 |
| U5 | 规范与现实相反 | `code-style.md:79-82` 要求"界面绘制只用 core/ui 原语，不允许任何模块手搓边框、光标、进度条"，但原语集里没有可复用的组件，内容集因此每一处都在手搓 |
| U6 | agent 只能读"光标数" | `state.query` 只有 `cursor`（菜单行号）；没有控件树/角色/标签/状态；agent 必须数按键次数（`agent-interface.md:289-291`） |
| U7 | 主题只有颜色 | `Skin` 6 色 + `ui::Style` 5 色；无焦点/选中/危险/禁用语义色，无边框字形集、间距与控件度量 |
| U8 | 绘制几何缺失 | 没有线/框/圆/环的 API；卡带各自逐格光栅化（`ballbattle/main.lua:104-123`、`towerdef/view.lua:23-45`），既是代码也是帧时间 |
| U9 | 文本框只有缓冲、没有控件 | `core/text_input` 只做过滤/退格/限长，不画光标、不处理焦点；`api/text_field.hpp` 是裸缓冲；worms 自己画昵称框 |
| U10 | 精灵语义与文档不一致 | `ui::icon` 的 `step` 是**降采样步长**（`core/ui.cpp:149-151`），文档写成"缩放步长"（`api-reference.md:300`）；且绑定层硬编码亮度 1.0（`api/ui_api.cpp:114-115`），内容包只能自己重写精灵 | 卡带/内容包对"放大"的直觉与实现相反；shelf 包因此重实现一份图标绘制 |
| U11 | 参数与单位校验缺失 | `ui::bar` 对 NaN 直接 `static_cast<int>`（`core/ui.cpp:92-102`，浮点→整型是 UB）；`ui.sprite` 的宽高按**字节**算（`api/ui_api.cpp:107-111`），中文精灵的几何会偏 | 卡带传入异常数值/非 ASCII 字符画时，行为未定义或布局错位，且没有错误回给作者 |

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

### 3.5 工程化（P2：让前面所有问题持续复发）

| # | 现象 | 证据 |
|---|---|---|
| E1 | 无 CI、无格式化、无静态分析、无 CMake preset | 仓库无 `.github/`、`.clang-format`、`.clang-tidy`、`CMakePresets.json` |
| E2 | 门禁强在"行为契约"，弱在"模型单元" | 6 项门禁全绿；但 51 个单测集中在颜色/文本/配置/色板/图层合并，`Screen` 宽字/缩放/孤儿格、`blend` 边界、存档耐久、模式迁移、包优先级都没有直接用例 |
| E3 | 无像素 golden 回归 | `gl_smoke.py` 只有少量断言（不是全黑/同格两笔）；外壳每屏的版面没有基线 |
| E4 | 无性能预算与基准 | 没有每帧绘制/合并/布局的阈值断言；`merge_ms` 只是观测 |
| E5 | 版本与依赖不可追溯 | `version.hpp` 同时兼任 CHANGELOG；`extern/` 第三方库版本无清单 |
| E6 | 文档漂移靠人眼 | 见 §4；没有把"数值/签名/规则"与代码比对的机械门禁（`--check-api` 只覆盖注解） |

---

## 四、文档 ↔ 实现漂移（已逐条复核）

| 文档声称 | 实际 |
|---|---|
| `architecture.md:300-301`：磁盘上一个内容包都没有也能开机 | boots 为空即 UB（§3.1 C1） |
| `architecture.md:105`：CRT 有暗角/畸变 | 着色器只有扫描线/孔径格栅/辉光/亮度补偿/色调（`render/renderer.cpp:58-95`） |
| `architecture.md:127-129`：`pack/` 不向上依赖 `render/` | `pack/pack.cpp:8` include `render/font.hpp` |
| `architecture.md:43-46`：`cart/` 只可复用 `api/lua_value.hpp` | `cart/cartridge.hpp:3` include `api/host_api.hpp`（头文件环） |
| `architecture.md:9-24` 分层图：core 在 api/cart/pack/shell 之下、render 在 core 之下 | `core/app.hpp` 反向 include 全层；`render/` 反向 include `core/` |
| `architecture.md:315`：渲染后端按"可换 Vulkan"设计 | 接口就是 `Renderer::draw(const Screen&)` + 内联 shader 字符串；无抽象缝 |
| `drawing.md:91`：GL 与 CPU 画的是同一张图 | 续格/被覆盖格上的笔迹 GL 画、CPU 跳过（§3.1 C7） |
| `layers.md:66`：当前 API 世代 **5** | `core/version.hpp:28` 是 **6** |
| `code-style.md:40`：可恢复错误返回 `std::expected` | 标准锁定 C++17（`:67`），全工程无 `std::expected` |
| `code-style.md:70`：不使用全局可变状态 | `core/log.cpp:13-15`、`platform/window.cpp:23`、`core/mods.cpp:11-20` |
| `code-style.md:46-54`：注释不写改动史 | `version.hpp:9-14` 是发行日志；多处注释记录"原先是 bug" |
| `api-reference.md:518-519`：键盘/手柄输入在此统一 | 无任何手柄/joystick 代码（`window.cpp` 只有 GLFW 键盘） |
| `devkit.md:258`：`debug_state` 支持"一层表" | `cart/cartridge.cpp:390` 明确按深度 4 序列化 |
| `cart-format.md:79-80`：入口脚本缺失会显示为损坏卡带 | `cart/cart_scanner.cpp:27-39` 只读 manifest，不校验 entry 文件存在 |
| `content-packs.md:69`：包缺失"回退 + 日志警告" | skin/boot/sound/palette 静默回退（`pack/content_library.cpp:52,56,61`），只有 shelf 告警 |
| `agent-interface.md:126-127`：`time.step` 推进完才回包 | `time.resume`/退出会丢弃在途回包（§3.1 C6） |
| `theme/boot/README.txt`：列出 13 个启动动画、任意键跳过 | 实际 16 个包（`sonar/clockwork/calligraphy` 未列）；`content-packs.md:179` 写"A 或 Esc 跳过" |
| `defaults.hpp:19`、`assets_api.cpp:57`、`audio.cpp:433`：引用"roadmap 第 8 条" | 该文档不存在（本次新建 roadmap.md 也不是原引用对象） |
| `api-reference.md:462`、`networking.md:97`：联机在后台线程、主线程不阻塞 | `join`/`discover` 在主线程阻塞（`net/net.cpp:641,740-787`，§3.1 C14） |
| `api-reference.md:611-612`：主机自带搜索框收不到中文 | `app.cpp:283` 在搜索编辑时置 `ime_wanted`，即**会**请求输入法；与 `agent-interface.md:155` 自相矛盾 |
| `cart-format.md:119`：Lua `print` 重定向到主机日志 | 未替换 `print`（§3.1 C16） |
| `api-reference.md:300`：sprite 的 `step` 为缩放步长 | 实现是降采样（`core/ui.cpp:149`），§3.3 U10 |

---

## 五、能力缺口（对照"专业主机"）

| 领域 | 缺什么 | 被什么挡住 |
|---|---|---|
| UI | 布局/容器/控件/焦点/主题 token/弹窗栈/文本域/表格/滚动条 | §3.3（原语集不含组件） |
| 场景 | 屏幕/弹窗栈、模态输入捕获、暂停与音频联动 | 外壳 `ShellMode` + 卡带各自状态机 |
| 输入 | 动作映射、重绑定、手柄、焦点丢失释放、按键重复 | 只有裸键名（`core/input.hpp`） |
| 存档 | 结构化值、schema 版本/迁移、槽位、原子写、CRC | 字符串 KV + 非原子写 |
| 内容 | 包清单统一校验、依赖/版本、预览、UI 主题包、热重载 | 六类包各自解析；Mod 需重启 |
| 渲染 | 单一合成器、绘制 IR、批处理、像素 golden | 三条合成路径 + 内联管线 |
| 音频 | 声部优先级/抢占、淡入淡出、ducking、流式、总线 | 现有混音器只有波形/包络/采样 |
| 工具 | watch 热重载、卡带 lint、截图基线工具、包校验 | devkit 只有 new/pack/check-api |
| 观测 | 控件树、性能预算、崩溃报告 | `cursor` + 手搓 debug_state |
| 治理 | CI、格式化、静态分析、覆盖率、版本政策 | 无 |
| 协议 | 统一 JSON（`\u`/代理对/非有限数/上限）、非阻塞联机、控制通道超时/背压/明文错误码 | 两套 socket 栈、手拼 JSON、阻塞调用 |

---

## 六、结论：瓶颈不在"功能数量"

项目的问题不是"少做了几个系统"，而是**三处结构性缺位**，它们让每个新增功能都变贵：

1. **缺一层把绘制原语组织成界面的东西。** 规范已经写了"界面必须调组件"，但组件层不存在；
   于是外壳与卡带都在手写排版/光标/滚动/弹窗。这是"不够专业"最直接、可量化的一处
   （§3.3：卡带 UI 14% 代码、复用率 <1%）。
2. **缺边界与真源。** App 住在最低层、状态分散成 3~4 份、HostContext 手工清指针、
   一帧三条合成路径——这些不修，UI 层也会被拖进同一团耦合里。
3. **缺工具与门禁。** 文档是靠人守的，漂移已到 22 处；UI/存档/模式这些新东西如果没有
   契约测试与像素基线，迁移一次就会回归一次。

因此后续方向的第一优先级不是"多加几个系统"，而是：
**先立 UI 组件层与场景模型（§3.3），同时清掉会绊住它的边界债（§3.1/§3.2），
再用契约与基线把它们锁死（§3.5）。** 具体阶段、顺序与验收见 [roadmap.md](roadmap.md)。
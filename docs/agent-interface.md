# 给脚本与 agent 的接口

PHOSPHOR 的画面是**纯文本字符网格**：脚本不需要截图、不需要视觉模型就能"看见"
完整画面，这是它适合被自动化与 AI 代劳的根本原因。

这篇讲三层接口——**命令行（批处理）→ 控制通道（交互）→ 确定性模式（可复现）**
——外加"让卡带自己交出玩法状态"的约定。写卡带用到的工具链见
[devkit.md](devkit.md)，每个 API 调用见 [api-reference.md](api-reference.md)。

---

## 一、设计原则

1. **文本进，文本/JSON 出**：所有接口对无头环境友好，可被任意语言调用
2. **与人力平权**：agent 能做的每件事，人类也能做（反之不必成立）
3. **只读与注入**：agent 接口只观察状态与注入输入，不产生游戏逻辑副作用
4. **协议带版本**：`hello` 事件携带协议版本，向后兼容演进
5. **默认安全**：控制通道只监听 `127.0.0.1`，且需显式开启
6. **零外部依赖**：宿主自带极简 JSON 读写（仅覆盖本协议所需），
   不引入第三方解析库；代价是**命令对象必须是扁平对象**（嵌套值被忽略）

## 二、命令行接口

```
phosphor [选项]

运行：
  --cart <path>          启动后直接加载卡带（目录或 .phos 单文件）
  --headless             不创建窗口、不打开音频设备，纯逻辑运行
  --frames <N>           运行 N 个逻辑帧后退出（无控制通道且未指定时默认 60 帧）
  --dump-screen          退出时把屏幕网格以文本打印到 stdout
  --dump-every <N>       每 N 帧打印一次屏幕（流式观察）
  --screenshot <path>    退出时把画面写成 PNG（CPU 光栅化，无头同样可用）
  --save-dir <dir>       卡带存档的落点（默认 saves/；机台配置 config.json 固定挨着 exe）
  --seed <n>             固定随机种子

确定性输入由**控制通道**承担（`input.inject` + `time.step`）：不需要额外文件，
agent 能看着状态一步步来；`--seed` 负责随机数可复现。

交互（agent 调试）：
  --control <port>       开启控制通道（本地 TCP，NDJSON），见第三节
  --log <file>           主机日志落盘：每条带墙钟时间与逻辑帧号，见第三节末

DevKit：
  --scan <dir>           列出目录下的卡带（--json 输出机器可读格式）
  --pack <dir> [--out f] 将卡带目录打包为 .phos，并校验 manifest 与入口脚本
  --new <dir> [--id s] [--name s] [--author s]
                        从 devkit/template 生成卡带骨架（id 缺省用目录名，name 缺省用 id）
  --check-api            校验 devkit/phos.lua 注解与实装是否一致（含字段级）
  --json                 机器可读输出使用 JSON 格式

其它：
  --version              打印版本号（唯一权威来源 core/version.hpp）后退出
  --help, -h             打印用法
```

退出码约定：`0` 正常；`1` 参数错误；`2` 卡带/打包校验失败；`3` 主机内部错误。

> **stdout 用法提示**：程序是 GUI 子系统（双击不弹黑框），从终端直接运行时
> 会附加父控制台，输出顺序受终端影响；**机器读取请使用管道/重定向**
> （此时不会附加控制台，stdout 是干净的数据流）。
>
> **PowerShell 提示**：GUI 子系统的程序在 PowerShell 里**不会被自动等待** ——
> 直接 `./phosphor.exe ...` 之后读到的 `$LASTEXITCODE` 可能是上一条命令的。
> 需要退出码请用 `Start-Process -Wait -PassThru`（读 `$p.ExitCode`），
> 或在命令后加管道（`| Out-String`）强制等待。

典型批处理工作流：

```bash
# 写完卡带 → 跑 300 帧 → 读屏幕 → 判断是否符合预期
phosphor --cart carts/snake --headless --frames 300 --seed 42 --dump-screen

# 要"脚本化输入"就用控制通道（input.inject + time.step），不必另造文件格式


# 视觉留档：文字读屏之外，还要一张能看的图（无头也能出）
phosphor --cart carts/snake --headless --frames 120 --screenshot shots/f120.png

# 打包 + 校验
phosphor --pack carts/snake --json
```

> **优先用文本读屏**：字符屏幕本身是纯文本，`screen.read` / `--dump-screen`
> 拿到的是零误差的"视觉"状态，足以支撑绝大多数判断与断言。
> PNG 用于需要给人看、或要做像素级视觉回归的场合。


## 三、控制通道

本地 TCP（`127.0.0.1:<port>`），协议为 **NDJSON**：每条消息是一行独立 JSON。

### 消息格式

```jsonc
// 主机在客户端连接后立刻推送（握手）
{ "event": "hello", "protocol": 1, "port": 7654 }

// 请求（命令对象为扁平结构）
{ "id": 1, "cmd": "screen.read" }

// 成功响应（payload 字段与 id/ok 同级展开）
{ "id": 1, "ok": true, "width": 84, "height": 51, "frame": 132, "lines": [ ... ] }

// 失败响应
{ "id": 1, "ok": false, "error": "unknown command: bogus" }

// 主动事件（无 id）
{ "event": "cart.loaded", "id": "snake", "path": "carts/snake" }
```

### 方法表（已实装）

| 命令 | 参数 | 说明 |
|------|------|------|
| `ping` | — | 连通性探测 |
| `state.query` | `path?` | 主机与卡带状态（字段见下方「state.query 字段表」）；带 `path` 时另返回卡带 Lua 全局值（点分路径），卡带定义 `debug_state()` 时另返回其内容（见下节） |
| `screen.read` | `layer?` | 当前屏幕网格：`layer`（读的是哪一份）/`width`/`height`/`frame` + `lines`（逐行文本数组）。不带 `layer` 读**合并结果**（= 整屏，与以前一致）；`layer = "screen"` 读的也是合并后的整屏，只是把"我读的是整屏"明说出来；带层名读该层自己的内容（内容区局部坐标）。**底层没有"合并前"的单独读法**——层是就地合并进底层的；"只想看世界"请让卡带把层隐起来（`layers` 里能看到，或卡带自己给开关） |
| `screenshot` | `path` | 当前画面写成 PNG（**CPU 光栅化**，无头可用；含扫描线/色调等后处理），返回像素尺寸 |
| `frame.read` | `path?` | 读回**当前帧缓冲的真实像素**（`glReadPixels`，含着色器与逐层叠画）——与 CPU 的 `screenshot` 互补，是 GL 渲染路唯一的像素出口。**仅窗口路径可用**（无头报错）。返回 `width`/`height`/`lit_ratio`（亮像素占比）/`mean_luma`；带 `path` 时另写一张 PNG（行序翻转成与 `screenshot` 同向，可直接对照）。`tools/gl_smoke.py` 用它核对"不是全黑""同格两笔""半格""逐层叠画" |
| `carts.scan` | — | 扫描 `carts/` 目录，返回卡带列表（含 `error`） |
| `input.inject` | `key`, `down`(bool)，可选 `frames` | 注入虚拟键（可用键名见 [api-reference.md](api-reference.md) 的「phos.input」一节）；`frames` 表示按住 N 个逻辑帧后自动释放。命令本身**立即回包**，实时与单步模式下都一样。`key` 也可为主机保留键 `escape`（见下节） |
| `input.text` | `text` | 注入一段文本（UTF-8，可含中文），与玩家敲键盘等价。**只在下一逻辑帧可见**（文本是按帧的，下一帧自动清空） |
| `input.clear` | — | 释放全部注入按键 |
| `time.step` | `frames`(默认 1) | 进入单步模式并推进 N 个逻辑帧，**推进完毕后**才回包（确定性同步点）。窗口模式下同样精确：推进只由本命令驱动，与显示器刷新节奏无关 |
| `time.resume` | — | 退出单步模式，恢复实时推进 |
| `save.export` | — | 当前卡带的磁带码（十六进制文本） |
| `save.import` | `code` | 用磁带码恢复当前卡带的存档（整份替换），返回条目数 |
| `cart.load` | `path` | 加载卡带（目录或 `.phos`） |
| `cart.reload` | — | 热重载当前卡带（改完代码立即生效） |
| `cart.eject` | — | 弹出卡带，回到系统界面 |
| `debug.set` | `name`, `value`, `group?` | 设置卡带注册的可调参数（`phos.debug.number`）当前值——与调试台同一处落地。名字**随界面语言变**，须用 `state.query.debug_params` 里报出的那个；重名参数（如每件武器的"伤害"）要带 `group`（同 `state.query.debug_params` 的字段）消歧，否则回 `ambiguous name` |
| `quit` | — | 关闭主机进程 |

### `state.query` 字段表

`state.query` 的响应是一个扁平对象，按下表读；`id` / `ok` 之外全部同级展开。

| 字段 | 含义 |
|------|------|
| `frame` | 逻辑帧号 |
| `mode` | 当前模式（含 `TAPE` 磁带码界面） |
| `playing` | 是否正在玩某张卡带 |
| `stepping` / `pending_steps` | 是否单步模式 / 还欠几帧（见「时间语义」） |
| `video` / `control_port` | 运行形态（`window` / `headless`）/ 控制端口（0 = 未开） |
| `grid_w` / `grid_h` | **整屏网格**尺寸（默认 84×51，随皮肤几何；`screen.read` 读的是它） |
| `content_w` / `content_h` | **内容区**尺寸（恒 80×45，卡带只面对它） |
| `panel_w` | 侧栏面板宽度（0 = 无面板） |
| `skin` / `palette` / `boot` / `sound` / `font` | 生效的皮肤 / 色板 / 启动动画 / 音效包 / 字体方案（**id**，稳定标识）。`palette` 由主题（skin）声明派生，非用户可切换项 |
| `font_size` | 当前**字号 = 单元格像素边长**（12~24，默认 16）：整机字符与行距随之缩放。用户设了就用它；否则跟随字体方案 `font.lua` 声明的 `size`；再否则出厂默认 16 |
| `ime` | 本帧是否有输入框在请求中文输入法：卡带 `phos.input.field({ime=true})` 的框被 `feed`、或卡带架搜索正在输入时为 `true`。主机据此开关系统输入法（仅 Windows 实际生效） |
| `packs` | 各类型可选清单：`skin` / `palette` / `boot` / `sound` 是**显示名**数组（屏幕上画的就是它，当前取包文件夹名），`*_ids` 是与之一一对应的**稳定 id**；字体只有 `font`（字体方案的标识本身就是 id）。要比对状态值或记住某一项**用 id**（显示名可能重名或随包改名，id 不会） |
| `language` | 界面语言（`zh` / `en`） |
| `cursor` | 菜单光标行号（`-1` = 当前模式没有菜单） |
| `shelf` | 卡带架顺序（卡带 id 数组，最近打开优先）；`cursor` 就是它的下标——"数到第几张再插卡"因此可编程 |
| `crt_level` | 显像管档位 |
| `fps` / `render_fps` | 画面刷新率档位（30/60/120/180）/ 主机实测刷新率。逻辑帧率恒为 60Hz，所以档位只改刷新率与 CPU 占用、不改游戏速度 |
| `music_volume` / `sfx_volume` | 两路音量（0~100） |
| `audio` / `voices` / `dropped` | 音频是否就绪 / 活跃声部数 / 请求队列丢弃数 |
| `music` | `{ on, section, index, count }`：是否在播 / 当前乐段名 / 曲序位置 / 曲序总数 |
| `cart` | 卡带元信息与开销：`id` / `name` / `version` / `author` / `path` / `sidebar_w`；`update_ms` / `draw_ms`（最近一帧）、`update_peak_ms` / `draw_peak_ms`（约 1 秒窗口峰值，查偶发卡顿看这个）、`lua_mem_kb`（Lua 堆）。未插卡时为 `null` |
| `merge_ms` | 图层合成耗时（**卡带没建层时恒为 0**） |
| `layers` | 该卡带的图层清单（名称 / z / 可见性，z 升序；空数组 = 没建层） |
| `debug_params` | 卡带注册的可调参数（`phos.debug.number/integer/toggle`）当前值：`[{name, group, kind, value}, ...]`（`kind` = `number`/`integer`/`boolean`；空数组 = 没注册）。`name` **随界面语言变**（写入时必须用它）；`group` 是分组路径串（如 `"武器/火箭筒"`，顶层为空串）——重名时用来消歧。人用调试台拖，agent 用这个读、`debug.set` 写 |
| `held_keys` | 当前按住的虚拟键名数组 |
| `save` | 存档概况 `{ available, entries }` |
| `seed` / `host_time` | 本次随机种子 / 卡带眼里的运行秒数 |
| `last_error` | 最近一次卡带错误（**命令失败本身即时以 `error` 回包，不写入这里**） |
| `path` / `value` | 仅当请求带 `path` 时：所查路径与其 Lua 值（不可序列化的值表示为 `{"__type": "…"}`） |
| `debug` | 仅当卡带定义 `debug_state()` 时：它返回的内容 |

### 事件

| 事件 | 载荷 | 时机 |
|------|------|------|
| `hello` | `protocol`, `port` | 客户端连接后立即推送 |
| `cart.loaded` | `id`, `path` | 卡带装载成功 |
| `cart.ejected` | — | 卡带弹出 |
| `cart.error` | `message` | 卡带出错（主机已安全停止该卡带） |

### 时间语义

- 默认**实时模式**：逻辑帧按 60Hz 推进（无头模式下带节流，不会空转吃满 CPU）
- 发出第一个 `time.step` 后进入**单步模式**：逻辑帧只在收到 `time.step` 时推进，
  且每次回包代表"这 N 帧已经跑完"。agent 因此可以写出完全确定的
  "注入输入 → 推进 N 帧 → 读屏幕" 循环
- `time.resume` 恢复实时；窗口模式下切回实时不会补跑积压帧（避免画面跳变）

### 客户端示例（PowerShell）

```powershell
$p = Start-Process ./phosphor.exe -ArgumentList "--cart carts/snake --control 7654 --headless" -PassThru -NoNewWindow
Start-Sleep -Milliseconds 900
$c = New-Object System.Net.Sockets.TcpClient("127.0.0.1", 7654)
$w = New-Object System.IO.StreamWriter($c.GetStream()); $w.AutoFlush = $true
$r = New-Object System.IO.StreamReader($c.GetStream())

$w.WriteLine('{"id":1,"cmd":"time.step","frames":60}')   # 精确推进 60 帧
$r.ReadLine()                                            # -> {"id":1,"ok":true,"frame":60,...}
$w.WriteLine('{"id":2,"cmd":"screen.read"}')
$r.ReadLine()                                            # -> 屏幕各行文本
$w.WriteLine('{"id":3,"cmd":"quit"}')
```

> 参考实现：`tools/control_test.py`——本仓库的回归脚本，
> 覆盖握手、状态查询、单步确定性、读屏、注入输入、热重载、扫描与退出码；
> `tools/window_smoke.py` 覆盖**窗口路径**（开窗跑时钟、菜单→开局、按键、`time.step` 精确性）；
> `tools/cart_smoke.py` 覆盖**卡带运行**：出厂卡带跑得完、不出错、有画面，且同种子跑两遍
> 逐字节一致（不比对像素——画面本来就该随卡带内容变），另有一段**驱动局**把卡带真玩起来；
> `tools/draw_smoke.py` 覆盖**绘制契约**：读像素核对同格两笔、只写底色与子位落笔。
> `tools/gl_smoke.py` 覆盖 **GL 渲染路**：开窗用 `frame.read` 读回真实帧，核对不是全黑、
> 同格两笔、半格与逐层叠画（CPU 的 `screenshot` 覆盖不到着色器与图层叠画）。
> 完整应用见：`agent_play.py`（开窗挑一张卡带玩起来，任意卡带都行）、
> `agent_shell_demo.py`（操作系统界面）。各脚本的跑法见仓库 README 的"开发脚本"表。

### 让它玩起来：agent 操控闭环

控制通道设计上就允许 agent **自己玩游戏**，而不是只做旁观式测试：

```
起主机(headless + --control)
   ↓
state.query / screen.read        读画面与状态
   ↓
决策（规则、搜索、或模型推理）
   ↓
input.inject 注入按键  →  time.step 精确推进若干帧
   ↓
循环直到目标达成（得分、通关、复现 bug）
```

两条读状态的路径，按卡带的配合程度选：

| 方式 | 适用 | 说明 |
|------|------|------|
| `screen.read` | 任何卡带 | 字符屏幕本身就是纯文本，零 OCR、零视觉模型；代价是要自己解析 |
| `state.query` 的 `debug` | 卡带声明了 `debug_state()` | 直接拿到玩法状态（坐标、分数、血量…），最省事；卡带报了 `(x, y)` 就用它，别去读画面反推地形 |

`state.query` 还支持按路径读卡带全局变量：

```jsonc
{"id":1,"cmd":"state.query","path":"math.pi"}      → {"value":3.14159}
{"id":2,"cmd":"state.query","path":"debug_state"}  → {"value":{"__type":"function"}}
{"id":3,"cmd":"state.query","path":"cfg.level"}    → {"value":3}
```

不可序列化的值（函数 / userdata）以 `{"__type":"…"}` 表达，不存在的路径返回 `null`。

> 完整可跑的实例：`tools/agent_play.py`——通用玩家，**不认识任何具体卡带**：
> 开窗 → 在卡带架上选一张 → 每轮读 `state.query` 里的 `debug_state()` 决定按哪个键 →
> `input.inject` + `time.step` 推进。按键来源按优先级取：`--policy` 指定的策略文件
> （`choose(state) -> 键名`）、卡带自报的 `debug.next_key`、`--keys` 给的序列，
> 都没有才在键池里随便按。想让 agent"玩得好"，写的是策略文件，不是改这个脚本。

### 操控主机本身：`escape` 是主机保留键

agent 能玩游戏还不够——它还应当能**操作整台机器**（进设置、插卡、暂停、关机），
与玩家按键能力完全对齐。唯一曾是缺口的是 Esc：它是主机保留键，
原先只由窗口层产生，无头模式下 agent 按不出来。

现在 `escape` 可直接注入，语义与玩家按键一致：

| 当前状态 | 注入 `escape` 的效果 |
|----------|---------------------|
| 正在玩游戏 | 暂停（呼出暂停菜单） |
| 暂停菜单 | 继续游戏 |
| 设置界面 | 返回卡带架 |
| 卡带架 | **关机**（进程退出）；但**搜索框正在输入时例外**——那时只清空搜索并收起输入框 |
| 开机自检中 | 跳过动画进入卡带架 |

配合虚拟键，agent 就能走完整条系统流程：

| 操作 | 注入 |
|------|------|
| 打开设置 | 主机保留键 `settings`（物理 F2） |
| 卡带架搜索 | 虚拟键 `f` 开关输入框（框内 `Esc` 只清空搜索）；查询串用 `input.text` 注入，输入即模糊筛选 |
| 上下选择 / 左右改值 | `up`/`down`、`left`/`right` |
| 确认 | `start`（物理 Enter） |
| 返回上一层 / 暂停 / 关机 | `escape`（物理 Esc） |
| 从卡带架插卡 | `start` |
| 暂停菜单里拔卡 | `down`（走到"拔出卡带"那一行）+ `start` |

> 主机界面**只认 `start` 与 `escape`**（外加保留键 `settings`）：`a`/`x`/`select`
> 这些虚拟手柄键留给卡带，主机界面按下去不会有反应——这是刻意的，
> 免得"卡带里按 A 确认、主机里按 A 关机"这种撞车。菜单光标位置可读回
> （`state.query` 的 `cursor` 字段），所以走到某一行**不要靠数按键次数**：
> 菜单项一增减，数出来的次数就全错。

> 完整实例：`tools/agent_shell_demo.py`——依次走完
> 开机 → 卡带架 → 设置（读值/改值/还原）→ 返回 → 插卡 → 暂停 → 拔卡 → 关机，
> 每一步都断言（17 项），并在结束前还原自己改过的设置、核对 `config.json` 未被留下痕迹。
>


### 让人看见：窗口模式下的 agent 操作

控制通道在**窗口模式**下同样可用（`--control` 与默认的 GUI 运行并不冲突）。
于是有两种用法，用同一个通道：

| 用法 | 命令 | 特点 |
|------|------|------|
| 无人值守 | `--headless --control <port>` | 无窗口、无声音、最省资源；CI / 批量测试用这个 |
| 人是观众 | `--control <port>`（不加 `--headless`） | 开真窗口、**有声音**，人能看到 agent 的操作 |

窗口标题会写明"谁在操作"，人和 agent 都能据此确认：

```
PHOSPHOR                              人自己在玩
PHOSPHOR - agent :7731 [live]         agent 接管，实时推进（画面连续走）
PHOSPHOR - agent :7731 [stepping]     agent 接管，单步推进（画面只在 time.step 时前进）
```

`state.query` 也给了同样的信息，便于 agent 自己确认"我是在操作一个可见的窗口吗"：

| 字段 | 含义 |
|------|------|
| `video` | `"window"` / `"headless"` |
| `control_port` | 控制通道端口（0 = 未开） |

要点：

- **实时 vs 单步**：实时模式下 agent 注入按键后画面连续推进，最适合"给人看"；
  单步模式下画面只在 `time.step` 时前进，适合需要精确复现的调试。
  按需在两者之间切换，标题会同步变化。
- **注入与实际键盘共享同一条输入路径**，所以人也可以同时用键盘参与；
  谁按的都一样（卡带无从分辨）。
- 窗口模式下音频设备是开着的，音效/音乐都会响——演示时这一半临场感来自它。

> 完整实例：`tools/agent_play.py --shelf-cart worms`——开窗、在卡带架上逐张试插
> 直到选中指定的卡带、读卡带遥测操控它玩，最后干净退出；标题里的 `[stepping]`
> 说明画面只在 `time.step` 时前进。

### 日志落盘：`--log <file>`

`--log` 把主机日志写到文件，每条形如：

```
2026-10-09 05:15:12.930 [f253    ] INFO  control #2 input.inject
2026-10-09 05:15:12.945 [f257    ] INFO  setting skin=neon-husk
2026-10-09 05:15:12.960 [f259    ] INFO  cart loaded: id=snake name=SNAKE ...
```

- **墙钟时间 + 逻辑帧号**：agent 的每条命令与主机事件落在同一条时间线上，
  事后可以逐帧复盘"第 253 帧到底发生了什么"。
- 记什么：启动参数与环境、控制通道开关、**每条控制命令**、卡带装卸与脚本错误、
  设置项变更、暂停/恢复/关机、测试结果、`phos.sys.log()` 的卡带日志。
- `info` 只进文件（不刷屏）；`warn`/`error` 同时打到 stderr，所以不指定 `--log` 时行为与以往一致。
- 崩溃/强杀也不丢日志：每条都即时 flush。

## 四、确定性模式

`--seed <n>` 与"控制通道注入 + 单步"共同构成可复现运行：

- `phos.sys.random` 完全由种子驱动
- `input.inject` 在指定逻辑帧注入输入；`time.step` 让帧数与真实时间脱钩
- 同一卡带 + 同一种子 + 同一输入序列 ⇒ 必然产出同一画面序列

这是 agent 自动化测试的地基：**测试报告可复现，bug 可回放**。


## 五、与 MCP 的关系

本接口刻意保持"纯文本原语"。将来封装 MCP server 时，
每个 MCP tool 只是对本章命令的一一薄封装，无协议改造负担。
**不在主机内直接实现 MCP**——主机保持协议无关。

## 六、常见组合（照抄即可）

自测与排查时最常用的几手（每条命令的字段定义见本章各节）：

```jsonc
{"id":1,"cmd":"state.query"}                              // 主机 + 卡带状态
{"id":2,"cmd":"screen.read"}                              // 整屏文本，零误差
{"id":3,"cmd":"input.inject","key":"right","frames":5}    // 按住 right 五帧
{"id":4,"cmd":"time.step","frames":60}                    // 精确推进六十帧后回包
{"id":5,"cmd":"save.export"}                              // 导出存档（磁带码）
{"id":6,"cmd":"screenshot","path":"shots/mid.png"}        // 随时取一张 PNG
{"id":7,"cmd":"cart.reload"}                              // 改完代码热重载
{"id":8,"cmd":"quit"}
```

一次典型的闭环：**改代码 → `cart.reload` → `input.inject` → `time.step` →
`screen.read` → 判断 → 再改**。只要卡带实现了 `debug_state()`，
`state.query` 里就带着玩法状态，判断这一步不必去解析画面。

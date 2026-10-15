# 做一张卡带

这篇是**卡带作者手册**（人类和 agent 都适用）：从建骨架到打包发布的全过程，
以及几条常见出错点。全部工具随发行包分发在 `devkit/` 下，装主机就能用。

想先跑起来看一眼：见 [从零做一张卡带](#从零做一张卡带)。

---

## 一分钟版

```bash
phosphor --new mygame --id mygame --name "My Game" --author "你"   # 只给名字：建到 carts/ 下
phosphor --cart carts/mygame                       # 改完存盘直接跑，卡带不需要编译
phosphor --pack carts/mygame                       # 产出 dist/mygame.phos
```

要改的东西在 `manifest.lua`（身份）与 `main.lua`（入口，标了「填」）。
规则写成模块放 `game.lua`，右栏内容放 `panel.lua`。

## 从零做一张卡带

**1. 建骨架**

```bash
phosphor --new carts/mygame --id mygame --name "My Game" --author "你"
```

从 `devkit/template/` 复制一份到目标目录，并把 `__ID__` / `__NAME__` / `__AUTHOR__`
换成你给的值（标题缺省与 id 相同，作者缺省是 `you`）。替换值按 Lua 字符串转义，
所以标题里带引号也写不出坏 manifest；目标目录已存在时拒绝覆盖。

**2. 起名与身份**——全在 `manifest.lua`：`id` / `name` / `desc`（后两者均可双语）/ `version`、
是否要右栏（`sidebar = { w = 18 }`）、是否要存档（`save = true`）、
目标接口世代（`phos_api`：图层写 `2`，墨迹 / 半格 / 独立底色写 `3`，联机 `phos.net` 写 `4`，主题携带色板（`phos.color.*` 随主题）写 `5`，同屏多字号（`put`/`print` 的 `scale`）写 `6`；
旧主机便会在卡带架上明确拒绝它，而不是运行到那一行才失败——见 [cart-format.md](cart-format.md) 的「版本兼容」）。
字段逐个说明见 [cart-format.md](cart-format.md)。

**3. 写玩法**——模板已经把缝摆好：
规则长在 `game.lua`（不读键盘、不画东西、不发声音），
输入与画法留在 `main.lua`。需要更多模块就 `require("music")` 这样加文件。

**4. 一边写一边跑**

```bash
phosphor --cart carts/mygame                                    # 开窗口试玩
phosphor --cart carts/mygame --headless --frames 300 --dump-screen   # 无头看一眼画面文本
```

**改卡带不需要"构建"**：卡带是 Lua 脚本，主机不编译它——直接在 `carts/` 里改，存盘再跑就是新的。
（在开发仓库里，主题 / 模板 / 文档这类内容目录由构建时同步到运行目录；发行包里直接改即可。）

**5. 打包分发**

```bash
phosphor --pack carts/mygame                # dist/mygame.phos
phosphor --pack carts/mygame --out out.phos # 指定输出
phosphor --pack carts/mygame --json         # 机器可读结果
```

打包器以**运行时同一套逻辑**探测卡带（读 `manifest.lua`、校验 `id` 与 `entry`），
校验不过就不产出文件并返回退出码 `2`；目录内容以稳定顺序压入 zip 容器
（同样输入产生同样输出）。目录卡带与 `.phos` 单文件由读取层统一处理，
所以**打包不改行为**：先跑目录、再跑单文件，画面一致。

## 模板填空表

`--new` 生成的就是这个模板。它刻意保持"空"——不演示任何玩法，只把骨架摆好，
并把需要你改的地方标了「填」。五个文件各管一件事：

| 文件 | 你要改什么 |
|------|-----------|
| `manifest.lua` | 身份：`id` / `name` / `desc`（均可双语）/ `version`；`sidebar = { w = 18 }` 决定右栏宽度（删掉这行 = 无右栏，也可运行时 `phos.panel.resize(w)`）；`save = true` 才有 `phos.save.*`；`entry` 指向入口；用了图层（`phos.layer`）写 `phos_api = 2`，墨迹 / 半格 / 独立底色（`blend` / `plot` / `back` 等）写 `3`，局域网联机（`phos.net`）写 `4`，主题携带色板（`phos.color.*` 随主题）写 `5`，同屏多字号（`put`/`print` 的 `scale`）写 `6` |
| `main.lua` | 入口三件事：装配模块、把输入翻成"意图"、把状态画出来。「填」集中在文案表 `Text`、`init`、`update`、`draw`、`debug_state` |
| `game.lua` | 玩法规则。不读键盘、不画东西、不发声音；要出声就 `return` 一张事件表 |
| `panel.lua` | 右栏内容。坐标是面板局部的；定宽文案一律过 `phos.text.fit(text, pw - 2)` |
| `README.txt` | 该改哪里的速查（随卡带走，给接手的人看） |
| `assets/` | 可选：分语言文本示例（`motd.zh.txt` / `motd.en.txt`，取不到回落 `motd.txt`） |

## 几条常见出错点

**1. 画面以可玩区为准**

```lua
local px, py, pw, ph = phos.screen.playfield()   -- 已扣掉右栏
```

`phos.screen.size()` 恒为 `80x45`，它**包含右栏覆盖的那几列**：照它从 0 画到 w，
右边就有几列藏在面板后面，玩家只看到"东西突然冒出来"。右栏宽度可以在运行时改
（`phos.panel.resize`），所以 `playfield()` 是函数：每次绘制取一次。

**2. 定宽位置的文案要自己裁**

```lua
phos.panel.print(1, y, phos.text.fit(text, pw - 2))
```

主机在右侧是硬切，会留下"[↑/A] 跳：按住更"这种半句话；`phos.text.fit` 超宽时截断
并补省略号，宽度按显示宽度算（全角字符不会被切成半个）。分区、小地图、状态条用
`phos.ui.region(...)`：它自带裁剪，越界不画。

要对齐的定宽字段（"标签 + 取值"那一列）用 `phos.text.pad` / `phos.text.pad_left`：
它们按**显示宽度**补空格，中英混排也能对齐。`string.format` 的 `%-Ns` 是按**字节**补的，
汉字会被算成 3 字节，同一列在中文下齐、在英文下不对齐。

**3. 键位提示写键盘上真实的键**

`phos.input.key_name("a")` 给出实际按键名。主机没有手柄，写按钮名时提示与实际键位不一致。

**4. 文字宽度的单位是"列"，不是字节**

`#"中文"` 是 6 不是 4。排版、居中对齐、定宽字段一律用 `phos.text.width()` 量。

**5. 用 `phos.screen.put` 画实心块，用 `phos.ui.sprite` 画字符画**

`ui.sprite` 的颜色映射键是**单字节**字符：`{ ["#"] = color }` 可以，
`{ ["█"] = color }` 查不到表、会退化成风格色（于是"主角"和障碍物同色）。
要实心像素块就直接 `phos.screen.put(x, y, "█", color)`。

**6. 位置从数据推**

出生点、水果落点这类坐标一旦写死，改一次地图就会落在墙里或掉出画面。
从地图数据里推（或加载时按"最近的合法格"算）可避免这类 bug。

**7. 压在底图上的文字：不给底色就是"透明底"**

`phos.screen.print(x, y, text, fg, bg)` 省略 `bg` 时**只写字、不动那一格的背景** ——
这正是"字压在山体上不留色块"要的效果。反过来，若这块地方必须不透底（浮窗标题、
血量读数这类），就得**显式给色**，否则脚下换成水、斜坡或天空时就会露出"空洞"。

**另一组**是 `screen` 的 `fill` / `blit` / `clear`、`screen` 与 `panel` 的 `back` / `back_rect`、
`panel.blit`：它们是"整块搬运或清一块地方"，省略底色按**激活色板的 `black`** 算（随主题变）。
两个例外：`panel.fill` / `panel.clear` 省略 = **主题面板色**（`skin.panel`）；
`ui.region` 的 `put` / `print` / `fill` / `blit` / `clear` **全部保留背景**（透明底）。
两组规则各含哪些调用，以 API 参考里的表为准。

**8. 巡逻类 AI 的死角**

"不许掉头"加上一张有死路的图，会让敌人集体卡在角落里不动；
不进只有一个出口的格子、被逼住时允许掉头可避免这种卡死。

**9. 玩家可见文案的中英两列与 `phos.lang`**

```lua
-- 整屏文案：两列，新增语言只需再加一列
local Text = {
  zh = { over = "游戏结束", restart = "按 %s 重开" },
  en = { over = "GAME OVER", restart = "press %s to restart" },
}

local t = phos.lang.dict(Text)        -- 每帧取一次：设置里切了语言，下一帧就跟上
phos.ui.center_text(mid, t.over)

-- 单条（武器名、状态文案这类"一条一对"的记录）
local name = phos.lang.pick({ zh = "普通炮弹", en = "SHELL" })
```

`dict` / `pick` 都是**缺 en 回落中文**，漏翻不会露出空串。**写死中文的卡带在英文主机上
会原样显示中文**——即适配未完成。排版见上一条：中英宽度不同，对齐用 `phos.text.pad`。

## 配色：一律用主题色板

**卡带的颜色一律取自主题色板。**

```lua
local C, S = phos.color, phos.screen

S.clear()                              -- 清屏底 = 色板的 black（不是写死的黑）
S.print(x, y, "HP", C.green)           -- 用色板绿
S.put(x, y, "@", C.yellow, C.black)    -- 要实底时也取色板色
phos.screen.fill(x, y, w, h, " ", C.black)   -- 省略底色 = 色板 black
```

- `phos.color` 的 12 个常量（`black/white/gray/dark_gray/red/green/blue/yellow/cyan/magenta/orange/purple`）
  **取自当前主题声明的色板**——换主题就整体变色。写死 `{ 6, 8, 20 }` 这类 RGB 后，
  背景色不随主题变，与其它界面各自呈现不同颜色。
- 选色按语义：用 `C.cyan` 当"玩家"、`C.red` 当"敌人"、`C.dark_gray` 当弱化的网格线，
  而非按肉眼观感写死 RGB。
- `phos.color.rgb` 用于**确实需要与主题无关的固定色**（特殊特效、按数值连续变化的色），
  这类色出现在点缀上；**大面积底色 / 文字 / 网格用色板色**。
- "省略底色是什么意思"分两组：`put` / `print` 省略 = **保留该格原底**（透明，
  字压在世界/机身上不留色块），`fill` / `clear` / `blit` / `back*` 省略 = **写色板的 black**。
  完整表见 [api-reference.md](api-reference.md) 的 `phos.screen` 一节。

> 检查：`grep rgb package/carts/<你的id>/*.lua`——命中项即代码里的固定色。

## 多文件卡带

卡带可用 `require` 拆成模块：

```lua
local Game  = require("game")      -- game.lua
local Music = require("music")     -- music.lua
local Panel = require("ui.panel")  -- ui/panel.lua
```

同目录（含子目录）的 `.lua` 打包时会一起收进卡带。拆分不只是"文件别太长"：
换掉 `music.lua` 就换了曲、换掉 `game.lua` 就换了玩法，互不影响——这既是可读性，
也是覆盖层 mod 能替换单个模块的前提。想读一个真实的多文件卡带，看 `carts/snake/`；
想读**分层**写法，看 `carts/tetris/`（井 / 下落块 / 特效 / 浮窗四层）与
`carts/worms/`（按**类别**分六层：特效 / 瞄准线 / 角色 / 雨雪天气 / 读数 / 浮窗 ——
一张大卡带怎么把每类东西放进各自那一层）；
`devkit/examples/inks/`（同一格叠两笔、只写底色、子位落笔、叠画上限）。

## 编辑器补全

`devkit/phos.lua` 是用 EmmyLua / Lua Language Server 注解写的**完整 API 签名表**。
在卡带工程旁放一个 `.luarc.json`：

```json
{
  "workspace.library": ["../devkit/phos.lua"],
  "runtime.version": "Lua 5.4"
}
```

之后 `phos.ui.` 一敲就有补全与参数提示。注解文件与
[api-reference.md](api-reference.md) 是同一份规范的两个面向：前者给编辑器，后者给人，
**改 API 时两者同步更新**（`--check-api` 可核对）。

## 自动化与 agent

人类试玩用窗口，脚本与 CI 用控制通道：

```bash
phosphor --cart carts/mygame --control 7654 --headless
```

连上 `127.0.0.1:7654` 后按 NDJSON 收发（协议全集见
[agent-interface.md](agent-interface.md)）：

```jsonc
{"id":1,"cmd":"state.query"}                                  // 主机 + 卡带状态
{"id":2,"cmd":"input.inject","key":"right","frames":5}        // 注入按键（按住 N 帧）
{"id":3,"cmd":"time.step","frames":60}                        // 精确推进 60 帧后回包
{"id":4,"cmd":"screen.read"}                                  // 读屏幕各行文本
{"id":5,"cmd":"cart.reload"}                                  // 改完代码热重载
{"id":6,"cmd":"quit"}
```

一种循环（这就是"AI 自己造卡带并验证"的闭环）：

```
改代码 → cart.reload → input.inject → time.step → screen.read → 判断 → 再改
```

卡带把玩法状态交出来后，agent 不必从字符画面反推：在卡带里定义

```lua
function debug_state()
  return { score = score, alive = alive,
           -- 坐标一律给全 (x, y)：只给 x 会逼 agent 去读画面反推地形
           head_x = ..., head_y = ..., food_x = ..., food_y = ... }
  -- 有多只实体（敌人、子弹、单位）时写成数组，一条实体一张表
end
```

主机在 `state.query` 时会把它一并带上。值支持 number / string / boolean 与一层表。

一次性验证可以用更轻的方式：

```bash
phosphor --cart carts/mygame --headless --frames 300 --seed 42 --dump-screen
```

要看画面时用 `--screenshot`（CPU 光栅化，不需要显卡，无头同样出图）：

```bash
phosphor --cart carts/mygame --headless --frames 120 --screenshot shots/f120.png
# 尺寸 = 网格(84x51) x 字号(默认 16px)；随主题（skin）几何与字号设置变化
```

文本画面 `screen.read` / `--dump-screen` 是零误差的，
PNG 用于"给人看"与像素级回归。

## 工程习惯：卡带自带自己的工具与痕迹

运行目录（`build/`）就是**发行包的形态**。写卡带时的开发产物——测试脚本、
日志、截图、报告、临时存档——放在这张卡带自己的文件夹里（`carts/mygame/dev/`）：

    carts/mygame/
    ├── manifest.lua  main.lua  game.lua  panel.lua …    # 卡带本体
    └── dev/                                             # 开发产物（不随卡带分发）
        ├── DESIGN.md    # 设计规格：数值与规则的唯一来源
        ├── play.py      # 控制通道测试脚本
        ├── run.log      # 运行日志
        └── shots/       # 截图

- **设计规格 `DESIGN.md` 也放这里**（不放在卡带根）：它是给作者看的规则与数值来源，
  不是玩家内容，自然归于"不随卡带分发"的 `dev/`。
- 主机运行时**只认 `.lua`**（`manifest.lua` + `entry` 与它们 `require` 的模块），
  `dev/` 之类的额外文件被忽略，不影响加载与运行。
- 但 **`--pack` 会把卡带目录整个打进 `.phos`**（只跳过嵌套的 `.phos`），`dev/` 也在其中，
  除非打包前移走或删掉。
- 测试通过 `--save-dir` / `--config` 指到 `dev/` 下的临时目录，即可不写入运行目录的
  `saves/` 与 `config.json`。

一句话：**一张卡带 = 一个自洽的文件夹**——代码、工具、痕迹都在里面；运行目录里只有卡带与
出厂内容。

### 两种目录，两种身份

同一个 `dev/` 概念，在两个场景下落到不同地方——**别混**：

| 场景 | 卡带本体 | `dev/` | 为什么这样 |
|---|---|---|---|
| **引擎开发仓库**（改 `src/`、跑 `cmake`） | `package/carts/<id>/`（真源） | `package/carts/<id>/dev/` | 构建只把**非 `dev`** 的内容同步进 `build/`，`build/` 永远保持"干净发行态" |
| **发行包**（只有 `phosphor.exe` 与 `build/`） | `build/carts/<id>/`（就地） | `build/carts/<id>/dev/` | 没有源码树，一切都在运行目录里；`--new` 生成的骨架就自带一个 `dev/` |

所有命令都**相对当前工作目录**：`--new` 落在 `carts/<名字>`、模板取自 `devkit/template`、
卡带架扫 `carts/`、存档写 `saves/`、配置读 `config.json`——**没有一个假设引擎源码在目录之外**，
发行目录完全自给自足。于是引擎开发时 `build/carts/*/` 里看不到 `dev/`（那份留在 `package/`），
而用户在发行目录里建的卡带，`dev/` 就在 `build/carts/*/` 里。两者不冲突。

## 保持注解不漂移

`devkit/phos.lua` 与实装会各自过时，一条命令就能查出漂移：

```bash
phosphor --check-api          # 比对 devkit/phos.lua（退出码 2 = 有出入）
phosphor --check-api --json
```

它做双向比对（函数与子表），并对 `---@field` 再做单向核对：

| 差异 | 含义 |
|------|------|
| 实装但未注解 | 新加的 API 未写进 `phos.lua` |
| 注解但未实装 | 文档注解了实现里没有的 API |
| 注解了不存在的字段 | `---@field` 注解的字段实现里没有 |

**改了 API 后运行 `--check-api`**，用于核对注解与实现是否漂移。

## 常见问题排查

| 现象 | 查看 |
|------|------|
| 卡带没出现在卡带架上 | 目录里有没有 `manifest.lua`（或是不是 `.phos`）；用 `phosphor --scan carts` 看主机认到了什么、报了什么 |
| 退出码 `1` | 命令行参数写错了，`--help` 是权威列表 |
| 退出码 `2` | 卡带装载/校验失败（manifest 缺字段、入口脚本不存在、打包校验不过） |
| 退出码 `3` | 主机内部错误，可用 `--log host.log` 记录日志 |
| 改了卡带没生效 | 改动未作用到运行中的那份（开发仓库里内容目录由构建时从源码同步而来，存盘即生效） |
| 字体/语言不对 | 那是设置项与主题的事，见 [content-packs.md](content-packs.md) |

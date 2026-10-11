# 做一张卡带

这篇是**卡带作者手册**（人类和 agent 都适用）：从建骨架到打包发布的全过程，
以及最容易踩的几条线。全部工具随发行包分发在 `devkit/` 下，装主机就能用。

只想先跑起来看一眼？跳到 [从零做一张卡带](#从零做一张卡带)。

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

**2. 起名与身份**——全在 `manifest.lua`：`id` / `name` / `desc`（双语）/ `version`、
是否要右栏（`sidebar = { w = 18 }`）、是否要存档（`save = true`）、
目标接口世代（`phos_api`：用到图层写 `2`，用到墨迹 / 半格 / 独立底色写 `3`；旧主机便会
在卡带架上明确拒绝它，而不是运行到那一行才失败——见 [cart-format.md](cart-format.md) 的「版本兼容」）。
字段逐个说明见 [cart-format.md](cart-format.md)。

**3. 写玩法**——模板已经把缝摆好：
规则长在 `game.lua`（不读键盘、不画东西、不发声音），
输入与画法留在 `main.lua`。需要更多模块就 `require("music")` 这样加文件。

**4. 一边写一边跑**

```bash
phosphor --cart carts/mygame                                    # 开窗口试玩
phosphor --cart carts/mygame --headless --frames 300 --dump-screen   # 无头看一眼画面文本
```

**改卡带不需要重新构建**：卡带就在 `carts/` 里，存盘再跑就是新的——卡带是 Lua 脚本，
主机从不编译它。只有两种情况才需要跑 `cmake --build`：改了主机 C++，
或者改了 `package/` 里的内容（主题 / 模板 / 文档，构建会把它们同步到发行目录）。

**5. 打包分发**

```bash
phosphor --pack carts/mygame                # dist/mygame.phos
phosphor --pack carts/mygame --out out.phos # 指定输出
phosphor --pack carts/mygame --json         # 机器可读结果
```

打包器以**运行时同一套逻辑**探测卡带（读 `manifest.lua`、校验 `id` 与 `entry`），
校验不过就不产出文件并返回退出码 `2`；目录内容以稳定顺序压入 zip 容器
（同样输入产生同样输出）。目录卡带与 `.phos` 单文件由读取层统一处理，
所以**打包不改行为**：先跑目录、再跑单文件，画面应当一致。

## 模板填空表

`--new` 生成的就是这个模板。它刻意保持"空"——不演示任何玩法，只把骨架摆好，
并把需要你改的地方标了「填」。五个文件各管一件事：

| 文件 | 你要改什么 |
|------|-----------|
| `manifest.lua` | 身份：`id` / `name` / `desc`（双语）/ `version`；`sidebar = { w = 18 }` 决定右栏宽度（删掉这行 = 无右栏，也可运行时 `phos.panel.resize(w)`）；`save = true` 才有 `phos.save.*`；`entry` 指向入口；用了图层（`phos.layer`）写 `phos_api = 2`，用了墨迹 / 半格 / 独立底色（`blend` / `plot` / `back` 等）写 `3` |
| `main.lua` | 入口三件事：装配模块、把输入翻成"意图"、把状态画出来。「填」集中在文案表 `Text`、`init`、`update`、`draw`、`debug_state` |
| `game.lua` | 玩法规则。不读键盘、不画东西、不发声音；要出声就 `return` 一张事件表 |
| `panel.lua` | 右栏内容。坐标是面板局部的；定宽文案一律过 `phos.text.fit(text, pw - 2)` |
| `README.txt` | 该改哪里的速查（随卡带走，给接手的人看） |
| `assets/` | 可选：分语言文本示例（`motd.zh.txt` / `motd.en.txt`，取不到回落 `motd.txt`） |

## 最容易踩的几条线

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
汉字会被算成 3 字节，同一列在中文下齐、在英文下就歪。

**3. 键位提示写键盘上真实的键**

`phos.input.key_name("a")` 给出实际按键名。主机没有手柄，写按钮名等于在提示里说谎。

**4. 文字宽度的单位是"列"，不是字节**

`#"中文"` 是 6 不是 4。排版、居中对齐、定宽字段一律用 `phos.text.width()` 量。

**5. 用 `phos.screen.put` 画实心块，用 `phos.ui.sprite` 画字符画**

`ui.sprite` 的颜色映射键是**单字节**字符：`{ ["#"] = color }` 可以，
`{ ["█"] = color }` 查不到表、会退化成风格色（于是"主角"和障碍物同色）。
要实心像素块就直接 `phos.screen.put(x, y, "█", color)`。

**6. 位置要按数据推，不要写死**

出生点、水果落点这类坐标一旦写死，改一次地图就会落在墙里或掉出画面。
从地图数据里推（或加载时按"最近的合法格"算），这类 bug 才不会再出现。

**7. 压在底图上的文字：不给底色就是"透明底"**

`phos.screen.print(x, y, text, fg, bg)` 省略 `bg` 时**只写字、不动那一格的背景** ——
这正是"字压在山体上不留色块"要的效果。反过来，若这块地方必须不透底（浮窗标题、
血量读数这类），就得**显式给色**，否则脚下换成水、斜坡或天空时就会露出"空洞"。

**另一组**是 `fill` / `blit` / `clear`（`screen` / `panel` 的，以及 `ui.region.clear`）：
它们是"整块搬运或清一块地方"，省略底色按**黑**算——清屏若也按"保留背景"来，就变成什么都不做。
`ui.region` 的 `put` / `print` / `fill` / `blit` 属于"保留背景"那一组，别把它的 `clear` 混进去。
两组规则各含哪些调用，以 API 参考里的表为准。

**8. 巡逻类 AI 要防死角**

"不许掉头"加上一张有死路的图，会让敌人集体卡在角落里不动。
让 AI 不进只有一个出口的格子，并且被逼住时允许掉头。

**9. 写给玩家看的字要有中英两列，取值交给 `phos.lang`**

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
会原样显示中文**——这是最常见的"适配没做完"。排版别忘上一条：中英宽度不同，
要对齐就用 `phos.text.pad`。

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
`devkit/examples/inks/`（同一格叠两笔、只写底色、子位落笔、叠画上限 —— 见 `design/draw-api.md`）。

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
**改 API 时两者要同步**（`--check-api` 会替你盯着）。

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

推荐循环（这就是"AI 自己造卡带并验证"的闭环）：

```
改代码 → cart.reload → input.inject → time.step → screen.read → 判断 → 再改
```

**把玩法状态交出来**，agent 就不必从字符画面反推：在卡带里定义

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
# 1344x816 = 84x51 格 x 16px；尺寸随主题（skin）几何变化
```

能用文字就用文字：`screen.read` / `--dump-screen` 是零误差的文本画面，
PNG 留给"给人看"与像素级回归。

## 保持注解不漂移

`devkit/phos.lua` 与实装会各自过时，一条命令就能查出漂移：

```bash
phosphor --check-api          # 比对 devkit/phos.lua（退出码 2 = 有出入）
phosphor --check-api --json
```

它做双向比对（函数与子表），并对 `---@field` 再做单向核对：

| 差异 | 含义 |
|------|------|
| 实装但未注解 | 新加的 API 忘了写进 `phos.lua` |
| 注解但未实装 | 文档承诺了不存在的东西 |
| 注解了不存在的字段 | `---@field` 承诺的字段实现里没有 |

**改了 API 就跑一次**，这是防止注解与实现漂移成本最低的手段。

## 出问题时先看这里

| 现象 | 先查 |
|------|------|
| 卡带没出现在卡带架上 | 目录里有没有 `manifest.lua`（或是不是 `.phos`）；用 `phosphor --scan carts` 看主机认到了什么、报了什么 |
| 退出码 `1` | 命令行参数写错了，`--help` 是权威列表 |
| 退出码 `2` | 卡带装载/校验失败（manifest 缺字段、入口脚本不存在、打包校验不过） |
| 退出码 `3` | 主机内部错误，带上 `--log host.log` 的日志反馈 |
| 改了卡带没生效 | 确认改的是运行中的那份（开发仓库里内容目录由构建时从源码同步而来，存盘即生效） |
| 字体/语言不对 | 那是设置项与主题的事，见 [content-packs.md](content-packs.md) |

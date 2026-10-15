# 卡带格式：manifest / 生命周期 / 沙箱

卡带是 PHOSPHOR 的游戏载体：开发期是一个目录，分发时打包成 `.phos` 单文件
（zip 容器）。这篇讲**写卡带必须知道的格式部分**——`manifest.lua` 每个字段、
三个入口的调用时机、卡带能做与不能做的事。本文件是格式的权威定义。

想直接开工就去 [devkit.md](devkit.md)（五分钟上手）；每个 API 调用查
[api-reference.md](api-reference.md)。

- 主机永不因卡带而崩：不符合本规范的卡带会被拒绝加载并说明原因，不会崩溃

---

## 一、包内结构

```
snake.phos  （zip 容器）
├── manifest.lua        # 必须：卡带身份证与运行需求
├── main.lua            # 必须：游戏入口
└── assets/             # 可选：卡带自带资源（文本画、音频、数据）
    ├── title.txt
    └── hit.wav
```

约束：

- 包内路径一律使用 `/`，大小写敏感
- 包内不允许可执行文件与动态库；卡带的一切行为只能通过 Lua 与 `phos.*` API 表达

**打包**：开发期直接用目录形态（`--cart <dir>`），分发前用 DevKit 打包：

```bash
phosphor --pack <cart-dir> [--out <file>]     # 校验 manifest 与入口，产出 dist/<id>.phos
phosphor --new <dir> [--id <id>] [--name <标题>] [--author <你>]
                                              # 从模板生成骨架（创建时即命名）
                                              # 其余身份字段（作者/简介/图标/侧栏/存档）都在 manifest.lua 里改
```

打包器与运行时共用同一套校验逻辑，且目录/单文件两种形态行为一致（见 devkit.md）。

## 二、manifest.lua

沙箱执行（无 IO 能力），必须返回一个表：

```lua
return {
  -- 必须字段 --
  id       = "snake",            -- 小写字母/数字/连字符；它同时是目录名、<id>.phos 与存档名
  name     = "SNAKE.EXE",        -- 显示名。也可写 { zh = "贪吃蛇", en = "SNAKE" } 双语
  version  = "1.0.0",
  entry    = "main.lua",         -- 入口脚本

  -- 可选字段 --
  author   = "you",
  -- name / desc 支持**双语**：写字符串 = 中英同文；写表 = 各语言一份（缺 en 回落 zh），
  -- 卡带架与标题按机器的界面语言取。（游戏内与侧栏自己的文案不在 manifest，
  -- 用 Lua 侧的 phos.lang，见 api-reference.md）
  desc     = { zh = "在终端里觅食的蛇。", en = "A snake hunting in the terminal." },
  sidebar  = { w = 16 },         -- 右侧栏面板宽度（0~32，缺省无侧栏）
  save     = true,               -- 是否需要存档空间（声明后 phos.save 可用）
  phos_api = 1,                  -- 目标 API 版本（当前世代 1~6，见「九、版本兼容」）

  -- 像素图标（卡带架展示；'.' 与空格为透明）
  icon = {
    "     ####    ",
    "    ######   ",
  },
  icon_colors = { ["#"] = { 80, 255, 120 } },
}
```

### 侧栏面板（sidebar）

声明 `sidebar.w` 后，屏幕右侧留出 w 列作为**面板区**（另加 1 列主机绘制的分隔线），
卡带通过 `phos.panel.*` API 以面板局部坐标作画（见 api-reference.md）。
面板内容完全由卡带决定：计分类游戏放分数记录，RPG 放地图，格斗游戏放血条图鉴。
主游戏区作画时避开面板区及其左侧一列分隔线。

主机校验规则：缺 `id`/`entry`、`entry` 指向的脚本不存在、`phos_api` 高于主机支持的世代
→ 拒绝加载，在卡带架中显示为"损坏卡带"并附原因。
内容区尺寸由主机固定（80×45），manifest **不需要**声明 `screen`。

## 三、生命周期

卡带脚本被加载进独立沙箱（独立 `lua_State`，卡带间互不可见），
主机按以下约定调用三个全局函数：

```lua
-- 插入卡带后调用一次。此时屏幕已就绪，存档句柄已打开。
function init()
end

-- 每个逻辑帧调用。dt 为距上一帧的秒数（固定步长）。
-- 输入查询只在本函数内有效。
function update(dt)
end

-- 每个**逻辑帧**调用一次（与 update 同频；画面刷新率是另一回事，见 state.query.fps）。
-- 只允许作画（phos.screen.*），在此修改游戏状态属于未定义行为。
function draw()
end
```

- 三个函数都是可选的，缺失则跳过（一张只写 `draw` 的卡带也是合法的静态画）
- 任一函数抛出 Lua 错误 → 主机捕获 → 显示卡带错误画面 → 用户可返回卡带架
- **单次调用有 100ms 上限（看门狗）**：`init`/`update`/`draw` 以及装载与 `require`
  任一步超过 100ms，就按"卡带出错"处理（安全拔卡 + 错误屏）。所以
  `while true do end` 这类失控**不会**冻结整机；它也不产生延时：
  正常一帧约几毫秒（满屏 3600 格逐格重绘实测约 1ms）
- 卡带无法主动退出到系统菜单，由用户按 Esc 决定（游戏机礼仪：主机权大于卡带权）

## 四、沙箱环境

卡带可用的标准库白名单：

| 可用 | 说明 |
|------|------|
| `math` `string` `table` `utf8` | 完整可用 |
| `print` | 重定向到主机日志/控制台 |
| `pcall` `xpcall` `error` `assert` `type` 等基础函数 | 可用 |
| `os.*` | **不可用**（沙箱未开 `os` 库）；需要时间用 `phos.sys.time()` |
| **`os.exit` `os.remove` `io.*` `load` 等** | **不可用**（文件与系统访问被禁止） |
| `require` | 可用，但被重定义为**包内模块加载**（只能读本包 `.lua`，见第五节） |

`load` / `dofile` / `loadfile` 在 `manifest.lua` 与内容包（皮肤 / 色板 / 开机动画 / 音效）
脚本里**同样不可用**——它们是不可信输入，且 manifest 在扫描卡带目录时就会被执行。
卡带 `id` 由**主机强制校验**（小写字母 / 数字 / 连字符，1..64）：它要拼进存档路径
`saves/<id>.sav` 与 `<id>.phos`，放任任意字符就能越出存档目录、或冒用别的卡带的存档。

卡带的一切对外表达只有三条路：`phos.*` API、`phos.save` 存档、`phos.net` 联机。
**没有原始套接字**——网络只能经 `phos.net`（开房 / 加入 / 收发 / 发现，见 api-reference.md），
沙箱拿不到任何底层网络能力。

## 五、多文件卡带（require）

卡带可以拆成多个 `.lua` 模块，用 `require` 加载——**模块名映射包内路径**：

```lua
local Music  = require("music")            -- music.lua
local Game   = require("game")             -- game.lua
local P      = require("ui.panel")         -- ui/panel.lua
local Tool   = require("lib/util/init")    -- lib/util/init.lua
```

- 每个模块只在首次 require 时执行一次，返回值被缓存
- 模块返回表即可作为接口；无返回值视为加载成功（返回 true）
- 只能读**本包内**的文件，越界路径一律拒绝（与资源访问同一套规则）
- 一种卡带内部结构（以 SNAKE 为例）：

```
snake/
├── manifest.lua
├── main.lua       -- 入口：装配模块与生命周期粘合
├── music.lua      -- 曲式化记谱（patterns + order）
├── sfx.lua        -- 音效
├── game.lua       -- 玩法状态机（不感知音频/存档）
├── panel.lua      -- 侧栏渲染
└── scores.lua     -- 存档与历史分数
```

> 拆分的意义不只是"文件别太长"：`game.lua` 不引用音频、`sfx.lua` 不引用存档，
> 各模块只依赖自己需要的东西——这既是可读性，也是 **mod 可单独替换**的前提
> （替换 `music.lua` 即可换曲，无需触碰玩法）。

## 六、卡带的音乐与音效

音乐音效**属于卡带**，随卡带包分发：

- **文本记谱音乐**：用 `phos.audio.music{...}` 定义多轨音序，
  长曲子用 `patterns` + `order` 作曲式（如 SNAKE 的 `music.lua`：4 个乐段、18 项曲序 ≈ 两分钟循环），
  无需二进制素材，纯文本、可读、可被 `mods/` 覆盖
- **采样音效**（可选）：`assets/*.wav | mp3 | flac`，用 `phos.audio.sample("assets/x.wav")` 加载播放
- **合成音效**（最轻）：`phos.audio.beep(...)` / `phos.audio.note("C4")` / `phos.audio.perc("K")`

主机在换卡与拔卡时自动停止卡带音乐；音频设备不可用时全部调用静默降级。

## 七、资源访问

```lua
local title = phos.assets.text("assets/title.txt")   -- 读取包内文本
local img   = phos.assets.rows("assets/map.txt")     -- 按行迭代
```

> 已实装。`phos.assets.*` 读取的是**包内文件**（目录卡带与 `.phos` 单文件同样可用），
> 路径相对包根，`..` 越界会被拒绝；缺失时返回 `nil`/`false`/`0` 而不抛错。
> 例见 `package/carts/life/assets/patterns.txt`（图案库）与 `phos.audio.sample()`（音频）。

- 只能读本包内的文件，路径越界（`..`）一律拒绝
- 覆盖层 Mod 生效时，读到的是 mod 替换后的内容（卡带无感知，见 content-packs.md）

## 八、存档

声明 `save = true` 后获得一块私有存档空间（仅本卡带 `id` 可访问）：

```lua
phos.save.available()            -- 存档是否可用
phos.save.write("hiscore", "9800")
local s = phos.save.read("hiscore")   -- 不存在返回 nil
phos.save.erase("hiscore")
phos.save.export()               -- 磁带码（十六进制文本）
phos.save.import(code)           -- 从磁带码恢复（整份替换）；非法返回 false
```

- 物理形态：`saves/<卡带id>.sav`（文本键值对），**写入即落盘**
- 键长 ≤ 64（不含 `=` 与换行）、值长 ≤ 4096、条目数 ≤ 256；越界写入被拒绝
- **磁带码**：`export()` 得到可复制的十六进制文本，`import()` 从它恢复——跨机器传档的
  复古载体。导入是**整份替换**，且先全量校验再落地（非法码不动现有存档）
- 主机侧也可读写当前卡带的磁带码（控制通道 `save.export` / `save.import`），
  因此没有内置文本输入的卡带同样可以完成传档

### 可选：向 agent 暴露玩法状态

卡带可以定义一个全局函数 `debug_state()`，返回一张表；主机在控制通道的
`state.query` 里会把它一并带上。表内可含 number / string / boolean、数组与嵌套表
（主机按**深度 4** 序列化，纯数组会写成真正的 JSON 数组）：

```lua
function debug_state()
  return {
    score = score, alive = alive, level = level,
    -- 逐实体的状态写成数组、一条实体一张表：agent 拿到的是结构化坐标，
    -- 不必去解析拼接出来的字符串
    units = { { x = 12, y = 34, hp = 100 }, { x = 56, y = 78, hp = 40 } },
  }
end
```

- 好处：自动化测试与 agent 直接读状态，**不必从字符画面反推**；
  不定义也完全不影响卡带运行（它只是可选的观测面）
- **报坐标时给全 `(x, y)`**：只给 x 时，agent 想算"炮弹落在哪"，
  需要读画面反推地形高度，既慢又不准；带上脚下那一列的地面高度则更完整
- 与侧栏面板一样，这是"卡带愿意展示什么"的决定，主机不强制

## 九、版本兼容

- `phos_api` 字段声明目标 API 版本；主机对旧版本 API 保持向后兼容
- 主机遇到更高 `phos_api` 的卡带 → 提示"此卡带需要更新版本的 PHOSPHOR"，拒绝加载
- 当前世代：**1 = 基础接口；2 = 可选图层（`phos.layer`）与 `phos.text.ink_box` /
  `phos.input.duration` / `phos.input.keys` / `phos.sys.frame`；3 = 墨迹叠加
  （`phos.screen.blend`）、半格绘制（`plot` / `quadrant` / `cell_of`）与独立底色
  （`back` / `back_rect`，及各自的区域版）；4 = 局域网联机（`phos.net`）；
  5 = 主题携带内容色板（`phos.color.*` 与默认前景/背景随主题变）；
  6 = 同屏多字号（`put` / `print` 的可选末参 `scale`）**。
  声明到所用接口的那一代：声明更高会在卡带架上被明确拒绝，更低则在运行到那一行时才失败。
  不用新接口的卡带声明 `1` 时，兼容的主机版本范围更大

## 十、分层（可选能力）

想让"世界 / HUD / 浮窗"各自独立、互不擦除时，用 `phos.layer`（见
`docs/api-reference.md` 的 `phos.layer` 一节）。这是**可选**能力：不建层的卡带走的
仍是原来的单层路径，主机连一次合成都不会做，也不需要为它改写。

三个可读的样板：`package/devkit/examples/layers/`（最小演示：世界 / HUD / 浮窗三层）、
`package/carts/tetris/`（井与已落定方块走底层，下落中的方块 / 特效 / 浮窗各占一层；
`fx` 层只写字形，所以压在世界上仍透得出来）与 `package/carts/worms/`（按**类别**分六层：
特效 / 瞄准线 / 角色 / 雨雪天气 / 读数 / 浮窗）。

图层是**按像素**叠的：层的字形只占自己的笔画，笔画之外透出下层，所以雨滴能落在山体那一格上
而与地形同格共存（见 `docs/api-reference.md` 的 `phos.layer` 一节）。屏幕**文本**视图仍是
一格一个字形，取最上面那层。

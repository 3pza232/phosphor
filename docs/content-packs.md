# 内容包：主题 / 皮肤 / 语言 / Mod

主机里能看到、听到的东西——机台外壳、配色与显像管质感、启动动画、系统音效、字体、
界面语言——全部是**内容包**，都可以被替换或新增。卡带之外，万物皆 Pack。

这篇讲：有哪几类包、一个包长什么样、怎么做一个自己的包；以及**玩家侧怎么切换它们**
（设置里的那些开关对应哪些文件）。

> 只是想换个外观？在设置里直接改就够了（见 [playing.md](playing.md)）。
> 本文是给"想改文件本身、或做一份自己的包"的人看的。

---

## 一、内容包类型

| 类型 | 目录 | 它控制什么 |
|------|------|-----------|
| `skin` | `theme/skin/<名称>/` | 机台外壳：边框字符画、屏幕区位置、灯珠与装饰锚点 |
| `boot` | `theme/boot/<名称>/` | 启动动画（一段每帧作画的 Lua 脚本，能力等同卡带） |
| `palette` | `theme/palette/<名称>/` | 内容色板：卡带与开机动画的 `phos.color.*`（由主题的 `palette` 字段引用，见下） |
| `sound` | `theme/sound/<名称>/` | 系统音效：按键声、插卡声、电流声、环境底噪 |
| `font` | `theme/font/<名称>/` | 字体文件（`.ttf` / `.otf` / `.ttc`），见下节"字体链" |

每个类型下可放任意多个包，主机内可随时切换。

`theme/icon/` 下有**两张图标**，用途不同（都是单个文件，不是可选内容包）：

- `phos_icon.jpg`：**窗口图标**，主机开窗时读取；读不到就退回系统默认图标并留日志。
  随发行包到输出目录，**可随时替换**
- `phos_icon.ico`：**可执行文件图标** —— Explorer / 任务栏给 `phosphor.exe` 显示的那枚。
  它在打包时已嵌进 `phosphor.exe`，运行时改不动（要换它得回到开发仓库重新构建）

## 二、包的物理结构

**一个包 = 一个文件夹 + 一个主脚本**（外加可选的 `assets/`）：

```
theme/skin/rust-cabinet/
├── skin.lua            # 主脚本（skin 类型）：机身字符画、界面配色、指示灯
└── assets/             # 该包自带的其他资源（可选）
```

各类型的主脚本文件名固定：`skin.lua`（skin）、`main.lua`（boot）、
`palette.lua`（palette）、`sounds.lua`（sound）、`font.lua`（font，可选声明）。

**没有 manifest，也没有第二套身份**：

- **显示名就是文件夹名**。设置界面里的 `< rust-cabinet >` 对应 `theme/skin/rust-cabinet/`，
  一眼能找到、改文件夹名即改显示名，不存在"名字与目录对不上"的可能
- 包的身份由路径决定（类型 = 父目录，id = 文件夹名），无需在文件里重复声明
- 风格的说明写在主脚本首行注释里——作者写给自己也写给玩家看

> 为什么不给内容包用 manifest：卡带需要 manifest，因为它携带运行数据
> （`entry` / `screen` / `sidebar` / `save`…）；内容包没有这类数据，
> 再加一个只放"名字"的文件，就产生了第二套命名，两处可能漂移。

## 三、列表来源与回退顺序

```
设置里可选的内容 = theme/<type>/ 下的每个文件夹（出厂默认也在这里）
        ↓ 该类型一个可用包都没有时
      system/<type>/ 中的固件资源（预留给将来；当前发行版不含此目录）
        ↓ 连它也没有时
      主机内建的硬编码兜底（builtin_skin / builtin_palette / SILENT / 文字自检动画）
```

- 用户选择的包损坏/缺失 → 安静回退 + 日志警告，**绝不让机器开不起来**
- 出厂默认包随发行版放在 `theme/<type>/default/`，用户可见、可直接改、可复制成新风格
- 当前发行版**不含** `system/`（字体已并入内容包 `theme/font/`），该目录保留给将来的固件资源；
  "内容被删干净时的兜底区"由各类型内置默认实现（不依赖磁盘）

## 四、激活配置

`config.json`（程序目录下）记录当前激活的包与界面选项：

```json
{
  "theme": {
    "skin": "rust-cabinet",
    "boot": "static-rain",
    "sound": "relay",
    "font": "default",
    "font_size": 0,
    "language": "zh"
  },
  "shelf_style": "window",
  "crt_level": 1,
  "fps": 60,
  "music_volume": 80,
  "sfx_volume": 90
}
```

- `skin`：游戏机主题（外壳 + 它使用的内容色板，见 `skin.lua` 的 `palette`）。色板不再是单独设置项
- `crt_level`：显像管档位 0=OFF 1=WEAK 2=MEDIUM 3=STRONG
  （实现为逐行扫描线 + 孔径格栅 + 辉光）
- `fps`：画面刷新率档位（30 / 60 / 120 / 180）。只改刷新率与 CPU 占用，**不改游戏速度**
- `music_volume` / `sfx_volume`：两路音量各 0~100（界面里分开调）
- `shelf_style`：卡带架样式（`list` 列表 / `window` 视窗轮播）
- `font`：字体方案（`theme/font/<方案>/` 的目录名；缺字由回退字体兜底）
- `font_size`：字号 = 单元格像素边长（`12`~`24`；`0` = 跟随字体方案声明的 `size`，缺省即 16）。
  整机字符与行距随之缩放（窗口也随格尺寸变大变小）
- `language`：界面语言（`zh` / `en`）—— 主机界面、卡带架简介与启动动画文案都随它切换
- 主机设置界面中可视化切换，等价于改写此文件。**全部即时生效并持久化**
- 版本约定：主机版本号是唯一权威（`phos.sys.version()`）；
  卡带/内容包的 `version` 是作者自己的版本，与主机版本无关；
  内容脚本引用版本通过 API（如 `phos.sys.version()`），不硬编码字符串

## 五、各类型补充约定

### skin（游戏机主题）

它决定**主机的样子**：机身外壳装饰、指示灯、以及卡带架/设置界面的界面配色。
主文件 `skin.lua` 返回一个表（所有字段可缺省，缺省回退出厂皮肤）：

```lua
return {
  screen = { x = 2, y = 3 },  -- 内容区（"屏幕"）左上角；尺寸由主机固定为 80x45，写 w/h 会被忽略
  left  = "||",       -- 左右侧壁装饰字符（按行轮换使用）
  right = "||",
  top = {             -- 内容区上方的机身装饰行（宽度自动补齐/截断到网格宽）
    string.rep("=", 84),
    "  PHOSPHOR P-1                     CRT DISPLAY UNIT",
    string.rep("=", 84),
  },
  bottom = { ... },   -- 内容区下方的机身装饰行
  colors = {          -- **机身界面**配色（卡带配色来自本主题声明的 palette，见下）
    frame  = { 70, 95, 70 },     accent = { 110, 255, 150 },
    ui_fg  = { 225, 255, 225 },  ui_bg  = { 0, 0, 0 },
    ui_dim = { 95, 120, 95 },    panel  = { 10, 20, 13 },
  },
  lamps = {           -- 指示灯：随运行时间呼吸
    { x = 0, y = 6, color = { 80, 255, 120 }, period = 2.4 },
  },
}
```

- 开机动画是**独立的内容包类型**（见下节），不在皮肤目录里
- `skin.lua` 可用 Lua 表达式生成（如 `string.rep`），便于快速构图
- `palette`：本主题使用的**内容色板**（`theme/palette/<名>/`，缺省 `default`；找不到回退 `NONE (RAW)`）。
  卡带与开机动画的 `phos.color.*` 取自它——设置里没有单独的"色板"项，色板是主题的一部分
- `panel`：右侧栏面板的底色（缺省 = `ui_bg`）。**刻意与机身区分**，给侧栏一层"凹槽"的层次；
  分隔线由主机画在**所有卡带图层之上**（否则会被卡带画的世界盖住）
- 内容区尺寸当前统一为 80x45（所有皮肤共享，切换时不重建窗口）

随包主题（名字即文件夹名）：

| 文件夹 | 风格 |
|--------|------|
| `default` | 出厂机身 P-1：极简工业风，双灯柱 + 铭牌 |
| `rust-cabinet` | 废弃游戏厅的机台：锈橙、故障灯 |
| `neon-husk` | 霓虹残壳：紫框 + 青/品红霓虹灯 |
| `ivory-terminal` | 象牙白实验仪器：暖白机身 + 琥珀高亮 |
| `crimson-arcade` | 红白街机机台：深红机身 + 金色高亮 |
| `graphite` | 石墨灰工程终端：细线冷灰 |
| `eva-unit01` | 初号机配色：紫机身 + 荧光绿高亮 + 橙色警戒 |

### boot（启动动画）

设置界面可随时切换，选择持久化。**设置里能看到几项，本目录下就有几个文件夹。**

- 文件：只需 `main.lua`
- 脚本与卡带同构：`update(dt)` / `draw()`，可用 `phos.screen` / `phos.color` /
  `phos.ui` / `phos.sys` / `phos.audio`
- **时长由动画自己决定**：脚本顶层可写 `duration = <秒>`（或 `function duration()`），
  未声明用出厂 3.2 秒；按 A 或 Esc 跳过
- **动画可以自带音效**：音频设备在开机动画之前就已就绪，
  所以 `phos.audio.beep / note / perc` 从第一帧起就能发声
  （例如 STATIC RAIN 的沙沙噪声、CART LOADER 的读写头咔哒）
- 此外主机还会播放音效包的 `boot` 事件音（换音效包即换开机提示音）
- 动画作者拥有与游戏作者同等的画面自由度——这是刻意的
- 一个可用包都没有时，回退主机内置的文字自检动画

出厂与随包动画（名字即文件夹名）：

| 文件夹 | 动效 |
|--------|------|
| `default` | TUBE WARMUP：中央亮线展开 + 冲击波 → 自检打字机 + 扫描头左右移动 → 末段电压抖动 |
| `static-rain` | STATIC RAIN：全屏雪花噪点雨 → LOGO 扫描式揭露 → 余噪干扰线（附沙沙噪声） |
| `sweep` | CART LOADER：进度条推进 + 闪烁读写头 + 逐块校验灯点亮（附启动扫频与完成音） |
| `persistence` | PERSISTENCE：写头扫过让字样"显影"，笔画按余辉先亮后暗（两遍扫描 + 就绪报字） |
| `waveform` | WAVEFORM LOCK：示波器栅格上的噪声波逐渐锁相成稳定波形（半格精度曲线 + 读数） |
| `bootlog` | BOOT LOG：逐行滚出的 POST 自检（每行一声轻响）→ 全部 OK 后打出产品名 |
| `spectrum` | SPECTRUM：电平柱跳动 + 峰值保持 + 倒影 + 扫描光标 → 收平成基线 → 锁定音 + 产品名 |
| `pulse` | PULSE：同心环扩散/收束 + 雷达扫描线 + 火花 + 同步率 HUD → 产品名在核心处亮起 |
| `ember` | EMBER：底部一排炉火跳动 + 火星升腾 → 产品名从火中浮出 |
| `stardust` | STARDUST：星辰向心汇聚成星滴 → 坠落水面溅起涟漪 → 产品名自水面浮起 |
| `helix` | HELIX：双螺旋——两条正弦链缠绕 + 碱基对逐个点亮 → 合拢后产品名亮起 |
| `circuit` | CIRCUIT：电路板通电——正交走线逐段点亮 + 电流亮点流动 + 焊盘闪烁 |
| `globe` | GLOBE：线框地球——经线随自转流动 + 陆地扫描 + 轨道卫星掠过 |

> **文案约定**：出厂默认字体方案已带中文字体（`theme/font/default/font-cn.otf` 作回退），
> 中文与 ASCII 都能显示。但一个包要在**任何**字体方案下都不缺字，只能用 ASCII 写文案
> ——用户可以自己做一个只含 ASCII 的字体方案（缺字以 `?` 占位）。
>
> **语言**：启动动画是以卡带形式运行的 Lua 脚本，面向玩家的文字按语言给两列、
> 取值用 `phos.lang.dict`（整张表）或 `phos.lang.pick`（单条），缺 en 会自动回落中文；
> 按显示宽度居中的用 `phos.text.width`；`#str` 是字节数不是列数。
> **皮肤（skin）里的字不参与本地化**：那是机台装饰（铭牌、贴纸、铭文），
> 写成 **ASCII 字符画**。
> 皮肤脚本也拿不到语言 API（内容包沙箱只有 `phos.text.width` / `truncate`）。

### palette（内容色板）

色板 = 主机内置项 `NONE (RAW)`（原色原样：黑底白字，不加扫描线与色调）+ `theme/palette/` 下的每个文件夹。
**它不再是一个单独设置项**：每个 `skin.lua` 用 `palette = "<名称>"` 声明自己用哪套色板
（缺省 `default`；找不到就回落 `NONE (RAW)`）。于是"换主题"会连同卡带的配色一起变。

`palette.lua` 返回配色表与 CRT 参数，所有字段可缺省（回退默认）。其中
`black` 是卡带的**清屏底色**、`white` 是默认**前景/文字色**：浅色主题（如配 `paper` 色板）
就是"浅底深字"：

```lua
return {
  scan = 0.08,                    -- 扫描线强度 0~1（设置界面的开关是总闸）
  tint = { 235, 255, 235 },       -- 显像管整体色调（乘算，含外壳界面）
  colors = {                      -- 12 色槽位，对应 phos.color.* 常量
    black = {0,0,0}, white = {230,255,230}, gray = {140,160,140},
    dark_gray = {60,80,60}, red = {255,80,80}, green = {80,255,120},
    blue = {90,140,255}, yellow = {255,230,90}, cyan = {90,230,230},
    magenta = {230,90,230}, orange = {255,160,60}, purple = {160,100,255},
  },
}
```

- 切换即时生效：CRT 参数作用于全部画面，色槽热更新到运行中的卡带
- 用户选择持久化于 `config.json`，重启后保持
- 可选 `crt.frag`：完全自定义后处理 shader，高级用户入口 **[未实装]**

随包色板（名字即文件夹名）：`default`（荧光绿）、`amber`（琥珀）、`ice-blue`（冰蓝）、
`slate`（灰白）、`paper`（纸面深墨）、`crimson`（血橙红，配 `crimson-arcade`）、
`eva`（初号机紫/绿/橙，配 `eva-unit01`）。

### sound（音效包）

主机事件音的来源。默认全部为**合成音**（无需二进制素材，契合字符机气质）。

- 文件：只需 `sounds.lua`
- 事件名：`boot`（开机）/ `insert`（插卡）/ `eject`（拔卡）/ `key`（按键）/
  `confirm`（确认）/ `error`（故障）
- 缺失的事件静默跳过，主机不报错

```lua
return {
  boot    = { wave = "square", freq = 220, sweep = 880, dur = 0.45, volume = 0.30 },
  insert  = { wave = "noise",  dur = 0.16, volume = 0.35 },
  key     = { perc = "K" },             -- 也可用打击乐记号
  eject   = { wave = "square", freq = 520, sweep = 90, dur = 0.24 },
  error   = { file = "assets/fault.wav" },  -- 或指向包内音频文件（优先）
}
```

随包音效包（名字即文件夹名）：

| 文件夹 | 风格 |
|--------|------|
| `default` | ARCADE BLIPS：方波短促提示声（出厂默认） |
| `soft` | SOFT TONES：正弦波、慢起落，深夜友好 |
| `relay` | RELAY CLACK：噪声与低频咔哒，机电继电器质感 |
| `chip` | CHIP BEEP：8 位芯片音，方波短促跳脱 |
| `deep` | DEEP HULL：低频厚重，机箱共振的沉响 |
| `glass` | GLASS BELL：清脆玻璃钟，正弦高频余音长 |
| `muted` | MUTED：轻柔极简，正弦极短低音量 |
| （主机选项） | SILENT：不播放任何主机事件音（卡带的音乐音效不受影响） |

> **卡带的音乐与音效不在这里**——它们随卡带分发（见 `api-reference.md` 的 `phos.audio`），
> 因此每张卡带的听感可以完全不同。

### font（字体方案）

字体包就是一套**字体方案**（与其它内容包一样，**文件夹名即方案名**），可在设置里切换；
出厂默认方案是 `default`，随发行版提供：

```
theme/font/default/
    font.ttf        角色 font    —— 主字体：ASCII 与整机字形风格
    font-cn.otf     角色 font-cn —— 回退：补齐主字体缺的码位（中文）
```

- 扩展名 `.ttf` / `.otf` / `.ttc` 均可（TTC 取第 0 号字体）
- **取字规则**：主字体 `font.*` 排最前，其余 `font-*` 回退按名称排序在后，
  依次取第一个含该字形的字体；都没有则显示 `?` 占位
- **方案声明（可选）** `theme/font/<方案>/font.lua`：不写就按上面的文件名规则；写了可显式声明
  字号范围与回退顺序，不必靠文件名表达意图：

  ```lua
  return {
    size = 16,                     -- 方案默认字号 = 单元格像素边长（行距随之变）
    min = 12,                      -- 设置界面可调范围下限
    max = 24,                      -- 上限（硬上限 32；Mod 覆盖本文件可抬高）
    order = { "font", "font-cn" }, -- 回退顺序，按 stem 或文件名；首个为主字体
  }
  ```

  `order` 里没列到的字体文件按文件名规则**附在其后**（绝不静默丢字）；`size` 是方案声明的默认字号。
  `min`/`max` 是**设置界面"字号"行的可调范围**——抬高 `max` 就是"允许更大的字"，
  且**可用 Mod 覆盖**（`mods/<任意名>/overrides/default/font.lua`，不改原文件；见「六、Mod 体系」）。
- 坏字体文件被跳过并告警；方案缺失或装不出字体时退回 `default` 方案并告警
  —— 绝不因此开不了机
- 更换中文观感：复制 `default/` 成新目录（如 `theme/font/hei/`），换掉字形文件，
  再切到该方案；打开任一带中文的卡带（如 `carts/snake`）可确认覆盖情况
- 纯 ASCII 的像素英文观感：建一个只放 `font.ttf` 的方案，中文显示为 `?` 占位

切换入口：`SETTINGS` → `FONT SCHEME` / `FONT SIZE` 两行（左右键切换，立即生效并写回 `config.json`）。
`FONT SIZE` 是**字号 = 单元格像素边长**（范围由字体方案的 `min`/`max` 声明，缺省 12~24，默认 16）：
整机字符与行距随之缩放（窗口也随格尺寸变大变小）。下面有一个**字形预览框**实时显示当前方案与
字号下的各类字形样本。

> 出厂默认方案里的中文字体体积大、**授权由使用者承担**，
> 随仓库分发前需确认授权。

**全角字符占两格**：CJK 字符在网格里占 2 列、UTF-8 占 3 字节。
卡带排版一律用 `phos.text.width(str)` 取列数（`#str` 是字节数）。

## 六、Mod 体系

### 覆盖层 Mod（Resource Override）——已实装

**Mod 就是 `mods/` 下的一个文件夹**，自由命名、**放进 mods/ 即自动生效**（没有开关、
没有"方案"之分）。一个 mod 可以覆盖多个目标，覆盖项放在 `overrides/` 下、按目标的 id 分目录：

```
mods/<任意名>/overrides/<目标id>/<目标内路径>

例：mods/big-font/overrides/default/font.lua     → 抬高大字号上限（覆盖 default 字体方案）
    mods/my-tweaks/overrides/snake/panel.lua     → 改贪吃蛇侧栏
    mods/my-tweaks/overrides/snake/game.lua      → 改贪吃蛇玩法数值
    mods/my-tweaks/overrides/snake/assets/map.txt→ 改关卡数据（经 phos.assets 读到的是覆盖后的）
    mods/dark/overrides/graphite/skin.lua        → 改某个主题的外观
    mods/dark/overrides/static-rain/main.lua     → 改开机动画
    mods/loud/overrides/relay/sounds.lua         → 改主机音效
```

- 目标 id：内容包的文件夹名、字体方案名，或卡带 id（目录名；`.phos` 单文件取文件名去后缀）
- 覆盖项与包内路径一致（`font.lua` / `skin.lua` / `panel.lua` / `assets/…`）；一个 mod 可放多条
- **多个 mod 改同一文件**：按 mod **目录名排序**，后者覆盖前者（可预测、与文件系统顺序无关）
- 查找顺序：命中的 mod 覆盖优先，否则包内本体兜底；**mods 无需修改原包**，删除即还原
- 覆盖层只替换"内容"，不改变"身份"

**唯一例外：卡带的 `manifest.lua` 不可被覆盖。** 身份
（`id` / `entry` / `save` 等）必须稳定，从而扫描、打包与运行时
对同一张卡带保持一致认知。

> 主机这边只有一处实现：对 `mods/*/overrides/**` 的统一路径解析（卡带与内容包共用），
> 启动时扫描一次 `mods/*/overrides/**` 并建表。**不硬编码任何具体 mod**——
> 引擎提供的是"覆盖任意内容文件"这条通用能力，具体改什么由 mod 自己决定。

### 脚本插件 Mod（Lua Plugin）——第二世代预留

主机级 Lua 插件：修改开机流程、在系统菜单加页、给所有卡带挂作弊层。
架构上已通过"API 注册表开放注册"预留接口，**当前世代不实现**。

## 七、常见改动对照（速查）

1. 想换机器外观 → 做 `skin` 包，放 `theme/skin/`
2. 想改开机仪式感 → 做 `boot` 包，写 Lua 动画
3. 想换卡带配色 → 改主题的 `palette`（或新做一个 `palette` 包、让主题的 `palette` 字段指名它）
4. 想改某张卡带 → 不动原卡带，在 `mods/` 里做覆盖层
5. 包损坏或缺失 → 删掉它，机器自动回退默认

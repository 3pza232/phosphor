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
| `palette` | `theme/palette/<名称>/` | 显像管质感：配色表 + CRT 后处理参数（可含自定义 shader） |
| `sound` | `theme/sound/<名称>/` | 系统音效：按键声、插卡声、电流声、环境底噪 |
| `font` | `theme/font/<名称>/` | 字体文件（`.ttf` / `.otf` / `.ttc`），见下节"字体链" |

每个类型下可放任意多个包，主机内可随时切换。

`theme/icon/` 下有**两张图标**，用途不同（都是单个文件，不是可选内容包）：

- `phos_icon.jpg`：**窗口图标**，主机开窗时经 `glfwSetWindowIcon` 设置，运行时读取；
  读不到就退回系统默认图标并留日志。随发行包到输出目录，**可随时替换**
- `phos_icon.ico`：**可执行文件图标** —— Explorer / 任务栏给 `phosphor.exe` 显示的那枚。
  它是**链接期嵌进 exe 的 Win32 资源**，运行时改不动；换了 jpg 想同步它，在源码仓库里
  跑 `python tools/make_icon.py` 重新生成 `.ico` 再构建即可（构建本身不依赖 Python）

## 二、包的物理结构

**一个包 = 一个文件夹 + 一个主脚本**（外加可选的 `assets/`）：

```
theme/skin/rust-cabinet/
├── skin.lua            # 主脚本（skin 类型）：机身字符画、界面配色、指示灯
└── assets/             # 该包自带的其他资源（可选）
```

各类型的主脚本文件名固定：`skin.lua`（skin）、`main.lua`（boot）、
`palette.lua`（palette）、`sounds.lua`（sound）。

**没有 manifest，也没有第二套身份**：

- **显示名就是文件夹名**。设置界面里的 `< rust-cabinet >` 对应 `theme/skin/rust-cabinet/`，
  一眼能找到、改文件夹名即改显示名，不存在"名字与目录对不上"的可能
- 包的身份由路径决定（类型 = 父目录，id = 文件夹名），无需在文件里重复声明
- 风格的说明写在主脚本首行注释里——作者写给自己也写给玩家看

> 为什么不给内容包用 manifest：卡带需要 manifest，因为它携带运行数据
> （`entry` / `screen` / `sidebar` / `save`…）；内容包没有这类数据，
> 再加一个只放"名字"的文件，就制造了第二套命名，等于给自己埋漂移的坑。

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
    "filter": "amber",
    "boot": "static-rain",
    "sound": "relay",
    "font": "default",
    "language": "zh"
  },
  "shelf_style": "window",
  "crt_level": 1,
  "music_volume": 80,
  "sfx_volume": 90
}
```

- `filter`：显像管滤镜（`none` = 原色原样）
- `crt_level`：显像管档位 0=OFF 1=WEAK 2=MEDIUM 3=STRONG
  （实现为逐行扫描线 + 孔径格栅 + 辉光，见 `core/crt.hpp`）
- `music_volume` / `sfx_volume`：两路音量各 0~100（界面里分开调）
- `shelf_style`：卡带架样式（`list` 列表 / `window` 视窗轮播）
- `font`：字体方案（`theme/font/<方案>/` 的目录名；缺字由回退字体兜底）
- `language`：界面语言（`zh` / `en`）—— 主机界面、卡带架简介与启动动画文案都随它切换
- 主机设置界面中可视化切换，等价于改写此文件。**全部即时生效并持久化**
- 版本约定：主机版本号是唯一权威（`phos.sys.version()`，定义于 `core/version.hpp`）；
  卡带/内容包的 `version` 是作者自己的版本，与主机版本无关；
  内容脚本引用版本请使用 API，勿硬编码字符串

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
  colors = {          -- 主机界面配色（卡带配色不受其影响，见 palette）
    frame  = { 70, 95, 70 },     accent = { 110, 255, 150 },
    ui_fg  = { 225, 255, 225 },  ui_bg  = { 0, 0, 0 },
    ui_dim = { 95, 120, 95 },
  },
  lamps = {           -- 指示灯：随运行时间呼吸
    { x = 0, y = 6, color = { 80, 255, 120 }, period = 2.4 },
  },
}
```

- 开机动画是**独立的内容包类型**（见下节），不在皮肤目录里
- `skin.lua` 可用 Lua 表达式生成（如 `string.rep`），便于快速构图
- 内容区尺寸当前统一为 80x45（所有皮肤共享，切换时不重建窗口）

### boot（启动动画）

设置界面可随时切换，选择持久化。**设置里能看到几项，本目录下就有几个文件夹。**

- 文件：只需 `main.lua`
- 脚本与卡带同构：`update(dt)` / `draw()`，可用 `phos.screen` / `phos.color` /
  `phos.ui` / `phos.sys` / `phos.audio`
- 播放约 3.2 秒后自动进入卡带架，按 A 或 Esc 跳过
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

> **文案约定**：出厂默认字体方案已带中文字体（`theme/font/default/font-cn.otf` 作回退），
> 中文与 ASCII 都能显示。但如果你的包要在**任何**字体方案下都不缺字，那就只用 ASCII 写文案
> ——用户完全可以自己做一个只含 ASCII 的字体方案（缺字以 `?` 占位）。
>
> **语言**：启动动画是以卡带形式运行的 Lua 脚本，面向玩家的文字按语言给两列、
> 取值用 `phos.lang.dict`（整张表）或 `phos.lang.pick`（单条），缺 en 会自动回落中文；
> 需要按显示宽度居中的，用 `phos.text.width`，不要拿 `#str` 当列数。
> **皮肤（skin）里的字不参与本地化**：那是机台装饰（铭牌、贴纸、铭文），
> 一律写成 **ASCII 字符画**即可——生硬翻译反而破坏机器感。
> 皮肤脚本也拿不到语言 API（内容包沙箱只有 `phos.text.width` / `truncate`）。

### palette（显像管滤镜）

滤镜列表 = 主机内置项 `NONE (RAW)`（原色原样，不加扫描线与色调）+ `theme/palette/`
下的每个文件夹。凡需要"卡带原本配色"的游戏，选择 `NONE` 游玩即可。

> `NONE` 与音效里的 `SILENT` 是**主机选项**（"关掉"），不是内容包，
> 因此没有对应文件夹——它们表达的是"不加修饰"，无法用配色表表达。

`palette.lua` 返回配色表与 CRT 参数，所有字段可缺省（回退默认）：

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
- 坏字体文件被跳过并告警；方案缺失或装不出字体时退回 `default` 方案并告警
  —— 绝不因此开不了机
- 想换中文观感：复制 `default/` 成新目录（如 `theme/font/hei/`），换掉字形文件，
  再切到该方案。打开任一带中文的卡带（如 `carts/snake`）即可确认覆盖情况
- 想要纯 ASCII 的像素英文观感：再建一个只放 `font.ttf` 的方案即可，中文会显示为 `?` 占位

切换入口：`SETTINGS` → `FONT SCHEME` 行（左右键切换，立即生效并写回 `config.json`）。

> 出厂默认方案里的中文字体体积大、**授权由使用者承担**——机器不替你做这个决定，
> 随仓库分发前请先确认授权。

**全角字符占两格**：CJK 字符在网格里占 2 列、UTF-8 占 3 字节。
卡带排版一律用 `phos.text.width(str)` 取列数，不要用 `#str`（那是字节数）。

## 六、Mod 体系

### 覆盖层 Mod（Resource Override）——已实装

任何卡带/内容包**脚本与资源**都可被同名文件覆盖：

```
mods/<目标id>/<与包内相同的相对路径>

例：mods/snake/panel.lua          → 替换贪吃蛇侧栏
    mods/snake/game.lua           → 改玩法规则/数值
    mods/snake/assets/map.txt     → 改关卡数据（经 phos.assets 读到的是覆盖后的内容）
    mods/rust-cabinet/skin.lua    → 改机台外观
    mods/static-rain/main.lua     → 改开机动画
    mods/relay/sounds.lua         → 改主机音效
```

- 目标 id = 文件夹名（`.phos` 单文件取文件名去后缀）
- 查找顺序：`mods/<id>/…` 优先，包内本体兜底；**mods 无需修改原包**，删除即还原
- 覆盖层只替换"内容"，不改变"身份"

**唯一例外：`manifest.lua` 不可被覆盖。** 卡带的身份
（`id` / `entry` / `save` 等）必须稳定，否则扫描、打包与运行时会
对同一张卡带产生不同认知——这是刻意的防线，不是遗漏。

### 脚本插件 Mod（Lua Plugin）——第二世代预留

主机级 Lua 插件：修改开机流程、在系统菜单加页、给所有卡带挂作弊层。
架构上已通过"API 注册表开放注册"预留接口，**当前世代不实现**。

## 七、作者指引（速查）

1. 想换机器外观 → 做 `skin` 包，放 `theme/skin/`
2. 想改开机仪式感 → 做 `boot` 包，写 Lua 动画
3. 想调显像管味道 → 做 `palette` 包，改参数或 shader
4. 想改某张卡带 → 不动原卡带，在 `mods/` 里做覆盖层
5. 包做坏了 → 删掉它，机器自动回退默认，永远能回家

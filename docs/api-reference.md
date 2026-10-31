# PHOSPHOR Host API 参考

卡带通过全局表 `phos` 与主机交互。这篇是**卡带作者的主要参考**：每个调用给
"一句话说明 + 签名 + 最小示例"，按模块分节。

> **用法**：本页按模块分节，可当字典查；想先跑起来，见 [devkit.md](devkit.md)。
> 编辑器补全定义在 `devkit/phos.lua`，与本文件是同一份规范的两个面向——改 API
> 时两者同步更新，`phosphor --check-api` 可核对。

---

## 总览

```lua
phos.screen   -- 字符屏幕：一切画面表达
phos.ui       -- 界面层：声明式 render（布局/控件/焦点/主题）+ 底层绘制原语/裁剪区域
phos.scene    -- 场景栈：压在世界之上的界面层（可冻结世界/暂停音频/接管更新与绘制）
phos.layer    -- 可选图层：把世界 / 下落物 / 特效 / 浮窗分开画（见下节）
phos.panel    -- 右侧栏面板（需 manifest 声明 sidebar）
phos.text     -- 文本度量与定宽裁剪（宽度单位是"列"，不是字节）
phos.color    -- 颜色常量与自定义色
phos.input    -- 输入查询
phos.lang     -- 卡带文案取当前语言那一列（dict / pick）
phos.audio    -- 合成音/音符/打击乐/音序器音乐/采样
phos.save     -- 存档（需 manifest 声明 save = true）
phos.assets   -- 包内资源读取（文本 / 按行 / 存在性 / 大小 / 列表）
phos.debug    -- 可调参数篮子：注册数值，用 `~` 调试台实时微调（见下节）
phos.score    -- 卡带排行榜：TOP N 分数（排序/截断/存档键/坏档容错在引擎侧）
phos.observe  -- 给 agent 的声明式观测表（字段可为函数，查询时求值）
phos.sys      -- 系统信息与工具
phos.cart     -- 当前卡带的身份（id / 标题 / 版本 / 作者 / 简介）
phos.net      -- 局域网联机：开房 / 加入 / 收发消息 / 发现（见下节）
```

> `phos.color` 的 12 色常量取自**当前主题声明的色板**（`skin.lua` 的 `palette`，指向
> `theme/palette/<名>/`）。设置里没有单独的"色板"项；换主题即换色板，卡带里的
> `phos.color.green` 等随之热更新。主题**未声明**色板时用 `default`；声明了却找不到对应包
> 时才回落内置色板 `NONE (RAW)`（原色原样）。

> **坐标系**：`phos.screen` / `phos.panel` 使用**内容区局部坐标**，左上角为 `(0, 0)`；
> 机身外壳（游戏机主题）由主机在外围绘制，卡带不需要关心内容区在窗口中的位置。
>
> **内容区恒为 `80x45`**，但整屏网格比它大（默认皮肤是 `84x51`：上下各 3 行机身、
> 左右各 2 列侧壁，由皮肤几何决定）。卡带只面对内容区；`screen.read` 读的是整屏网格。
> **声明了右栏的卡带按可玩区排版**：
> `local px, py, pw, ph = phos.screen.playfield()`（内容区扣掉右栏）。
> 照 `size()` 从 0 画到最右边，那几列会藏在面板后面——玩家只看到"东西突然冒出来"。

## phos.screen

逻辑屏幕是一个 `80 × 45` 的**内容区**（**尺寸由主机固定**，与主题和皮肤无关；
左上角为 `(0, 0)`）。每格包含：字符、前景色、背景色。
机身外壳在内容区之外，不属于 `phos.screen` 的坐标系。

```lua
w, h = phos.screen.size()                  -- 恒 80x45（内容区；**含侧栏覆盖的列**）
phos.screen.width, phos.screen.height      -- 同一对尺寸的常数字段（省一次调用；由主机固定）
px, py, pw, ph = phos.screen.playfield()   -- 可玩区：内容区扣掉侧栏后的那一块

-- 写入 --
phos.screen.put(x, y, ch)              -- 写一个字符（ch 为单字符字符串）
phos.screen.put(x, y, ch, fg, bg)      -- 带颜色
phos.screen.print(x, y, text)          -- 从 (x,y) 起写一行文本
phos.screen.print(x, y, text, fg, bg)
phos.screen.put(x, y, ch, fg, bg, scale)    -- scale>=2：那一个字占 scale 列 x scale 行（大字号）
phos.screen.print(x, y, text, fg, bg, scale)-- 整行按 scale 放大（逐字前进，块宽 = 宽度*scale）
phos.screen.fill(x, y, w, h, ch, fg, bg) -- 填充矩形
phos.screen.blit(x, y, rows, fg, bg)   -- 一次写多行（地图/画面搬运；超宽按显示宽度截断）
phos.screen.clear()                    -- 全清（空格 + 默认色）
phos.screen.clear(fg, bg)              -- 指定底色清屏

-- 同一格里的"两样东西" -- 
phos.screen.blend(x, y, ch, fg)        -- 追加一笔（叠加）：两笔都画，不是后来者顶掉前者
phos.screen.back(x, y, bg)             -- 只写这一格的底色：字形与已叠的笔迹都不动
phos.screen.back_rect(x, y, w, h, bg)  -- 整块只写底色
phos.screen.plot(x2, y2, fg)           -- 在**子位**上落一笔：(x2,y2) 是子格坐标（一格 = 2x2）
phos.screen.quadrant(bits)             -- 位掩码 → 象限字形（1 左上 / 2 右上 / 4 左下 / 8 右下）
phos.screen.cell_of(x2, y2)            -- 子格坐标 → 格坐标 + 子位（引擎唯一的这套换算）

-- 读取（调试与 agent 用；性能开销由主机承担） --
ch, fg, bg = phos.screen.get(x, y)
```

越界写入**静默裁剪到内容区**（侧栏与机身装饰不在卡的写入范围内），不报错——
卡带不必为边缘坐标防御性编程。四条写入一族的口径一致：`put` / `print` / `fill` / `blit`
都按内容区边界裁剪，其中 `print` / `blit` 按**显示宽度**截断（汉字算两格）。
读取同理：`screen.get` 落在内容区之外时返回空串。

**省略 `bg` 时怎么办？** 分两组：

| 调用 | 省略 `bg`（或传 `nil`） |
|---|---|
| `screen.put` / `screen.print`、`panel.put` / `panel.print` | **保留该格原有背景**（"透明底"）：字/图标压在地形、天空、机身上都不留色块 |
| `ui.region` 的 `put` / `print` / `fill` / `blit` / `clear` | 同上，一律保留背景（覆盖层压在游戏画面上不会糊出一块块黑底） |
| `screen.fill` / `screen.clear` / `screen.blit` / `screen.back` / `screen.back_rect`、`panel.blit` / `panel.back` / `panel.back_rect` | **总是写底色**：省略 = **激活色板的 `black`**（随主题变，不写死黑）——这族是"整块搬运 / 清一块地方" |
| `panel.fill` / `panel.clear` | 省略 = **主题面板色**（`skin.panel`）：右栏不属于游戏画面，底色随主题，不透出游戏、也不是写死的黑 |

> **省略 `fg`（前景）时 = 激活色板的 `white`。** 于是"换主题（预设）"会连同卡带的清屏底与文字底色一起改变——这是多主题适配的根。

> **同屏多字号**：`put` / `print` 的**可选末参 `scale`**（1~3）让同一画面里并存大小不同的字——
> `scale = 2` 的那个字占 2 列 x 2 行（块内其余格自动留给它），`scale = 3` 占 3 列 x 3 行。
> 典型用法：大标题 `scale = 2`、正文省略（= 1）。`screen` / `panel` / `ui.region` 都支持

所以"要让这块地方不透底"需**显式给色**：
`phos.screen.print(x, y, text, fg, bg)`。

**底色的粒度就是"一格"，不可能更细** —— 这一条决定了
"底板贴合字身"这类想法能不能做：

- 一格只有一个底色，而且**后写的整格会覆盖先写的**：世界与浮层写的是同一格，
  先画的内容不会留在底下。所以"背景只有字身那么窄"或"底板半透明、透出战况"
  在 API 层面**做不到**
- 真要"底色贴合字身"，正路是换一款**字身填满格子**的字体（`theme/font/<方案>/`）
- 反过来，"**不加底板**"完全可行：**省略 `bg`** 即不加底板 ——
  省掉的是底板，**不是**这一格的底（世界的底色留着，不会变黑洞）。
  例：WORMS 里虫子的 `@` 标与它头顶的箭头不垫底板，压在天空/土层上都不留色块

### 同一格里放两样东西：`blend` 与 `plot`

一格只有一个字形槽，但**不是只能放一样东西**：`put` 是"把这一格改成这个字"（替换），
`blend` 是"再画一笔"（叠加）。两笔在渲染时各自按**字形覆盖率**混合 ——
于是"两种内容落在同一格"两笔都看得见，重叠处后面那笔的颜色占优。

- 只收半角字形，且**只能落在有字形槽的格**：宽字的续格、被缩放的块覆盖的格没有字形槽，
  `blend` 直接返回 `false`（日志只报一次）
- 同一格最多叠 **3 笔**（含 `put` 那一笔）。满了 `blend` 返回 `false`
  并且**不画**（已画上的内容只增不减），日志里留一次痕
- **`plot` 管半格**：一格分 2×2 子位，多次 `plot` 落在同一格会合并成一个象限字形
  （位序由引擎定义：左上 / 右上 / 左下 / 右下），卡带不必自带那张字形表
- **底色可以单独铺**：`back` / `back_rect` 只写底色，"背景比字形宽一格"就在本格之外
  再 `back` 一次
- **文本通道是有损的**：`screen.read` 与 `--dump-screen` 一格只导出一个字形
  （最前面那一笔），所以"同格两笔"只有画面与 `screenshot` 看得全

## phos.color

```lua
phos.color.black  .white  .gray   .dark_gray
phos.color.red    .green  .blue   .yellow
phos.color.cyan   .magenta .orange .purple
-- 共 12 色，实际色值由当前主题声明的色板决定（"绿色"在不同主题下取值不同）

local c = phos.color.rgb(255, 128, 0)   -- 自定义色（会被 palette 做辉光映射）
```

## phos.text

文本度量。**全角字符（CJK 等）占两列、UTF-8 占三字节**，所以排版一律用它；
`#str` 数的是字节（会数成 3 列）：

```lua
phos.text.width("中文 abc")            -- 8  （2+2 全角 + 1 空格 + 3 半角）
phos.text.width("hello")               -- 5
phos.text.truncate("很长的中文标题", 8)  -- "很长的中"（8 列，绝不切出半个字）
phos.text.fit("很长的中文标题", 8)       -- "很长的…"（超宽才截，末尾留一个"…"；没超宽原样返回）
phos.text.pad("模式", 8)                -- "模式    "（右补到 8 列）
phos.text.pad_left("42", 6)             -- "    42"（左补：取值右对齐）
phos.text.ink_box("@")                  -- xoff, width, approx（字形墨迹框，像素；随字体而变）
```

`phos.screen` / `phos.panel` / `phos.ui` 的写文字接口都按显示宽度推进，
截断也发生在字符边界上——卡带不需要自己处理这些。全角字符的续格由主机维护，
`phos.screen.get()` 问哪一格都会返回该字符。

**`ink_box` 给的是"字形墨迹在格内占多宽"**（像素）：字体是比例字体，墨迹通常比一整格窄，
所以要"底板/装饰贴住字身"时按它算，而非按整格。拿不到字体度量时（无头运行、
字体未就绪）返回整格宽并置 `approx = true`。

**定宽位置（侧栏、状态条）用 `fit`**：主机在右侧是硬切，
写完超长的那一截就没了影，"按住更高"会变成"按住更"；`fit` 会补一个省略号，
玩家一眼就知道"这里还有字"。`columns` 传可用列宽（面板里通常是 `pw - 2`）。

## phos.audio

音频完全由**卡带自带的数据**驱动：音乐是文本记谱、音效是合成参数，
随卡带包分发（可被 `mods/` 覆盖）。若主机音频设备不可用，
全部调用安全降级为静音——卡带无需做任何防御。

```lua
phos.audio.available()          -- 音频设备是否可用
phos.audio.volume(v)            -- 主音量（0..1）
phos.audio.music_volume(v)      -- 音乐音量（音序器产出）——与设置界面 MUSIC VOLUME 同源
phos.audio.duck(level, seconds) -- 临时压低音乐：level 0..1、保持 seconds 秒（<=0 取消）
phos.audio.ui_volume(v)          -- UI 音量（主机事件音；与游戏音效分开）
phos.audio.music_state()         -- { playing, section, section_index, section_count, loop }
phos.audio.sfx_volume(v)        -- 音效音量（beep/音符/打击乐/采样）——与 SFX VOLUME 同源
-- 三个音量接口都是「传参即设置，返回当前值」

-- 合成音：频率(Hz)、时长(秒)、可选参数表
phos.audio.beep(880, 0.06)
phos.audio.beep(420, 0.55, { wave = "square", sweep = 70, volume = 0.28 })

-- 音符（音名写法：C4 / F#3 / Bb2）
phos.audio.note("C4", { dur = 0.12, volume = 0.2 })

-- 打击乐：K 底鼓 / S 军鼓 / H 踩镲
phos.audio.perc("K")

-- 音乐：文本记谱的音序器
--   单乐段简写（适合短循环）：
phos.audio.music({
  bpm  = 148,
  wave = "square",       -- 旋律默认波形
  loop = true,
  tracks = {
    lead = "E4 - G4 - B4 - A4 -",     -- 谱面可写字符串（空格分隔）或表
    bass = "E2 - - - A1 - - -",
    perc = "K - H - S - H -",         -- K 底鼓 / S 军鼓 / H 踩镲
  },
})

--   曲式写法（长曲子：乐段 + 曲序）：
phos.audio.music({
  bpm  = 132,
  wave = "square",                     -- 未指定音色的轨道跟随此波形
  loop = true,
  patterns = {
    A = {
      lead = { wave = "square",   volume = 0.55, release = 0.16,
               steps = "E4 = = = G4 = = B4 = = - - - - -" },
      bass = { wave = "triangle", volume = 0.85, release = 0.30,
               steps = "E2 - - - - - - - B1 - - - - - - -" },
      perc = { volume = 0.7, steps = "K - H - S - H - K - H - S - H - " },
    },
    B = { lead = "B4 - E5 - D5 = B4 = A4 - G4 -", bass = "E2 - - E2 - - - -", perc = "K - H - S - H S" },
  },
  order = { "A", "A", "B", "A" },     -- 每项播放一遍该乐段（循环时回到开头）
})
phos.audio.stop_music()
phos.audio.paused(true)   -- 暂停/恢复全部声音（音乐原地冻结续播）
phos.audio.stop_all()     -- 停掉一切（换卡/拔卡时主机自动调用）
```

> **音乐状态可观测**：`state.query` 的 `music` 字段给出
> `on`（是否在播；无音频设备时为 `false`）、`section`（当前乐段名）、
> `index` / `count`（曲序位置与总数）。写长曲子时可用它确认曲式在走，
> 而非只看谱面——`tools/` 下的脚本就是这么验的。
> 同一处还会给出 `voices`（活跃声部数）与 `dropped`（触发被丢弃的次数），
> 后者非 0 说明卡带一帧内触发的声音多到超过了请求队列长度，或声部池已满且没有更低
> 优先级的声部可抢占（见下方"声部池与优先级"）。

```lua
-- 采样：卡带包内的音频文件（wav / mp3 / flac，内存解码）
local hit = phos.audio.sample("assets/hit.wav")   -- 句柄，0 = 失败
phos.audio.play_sample(hit, { volume = 0.8, loop = false })
-- 关键反馈可以带优先级：池满时允许抢占氛围音（同 `phos.audio.Tone` 的 priority）
phos.audio.play_sample(hit, { volume = 1.0, priority = 20 })
phos.audio.stop_sample(hit)
```

`beep` / `note` 的选项表字段（写在末尾的 `opts` 里，均可缺省）。注意 `beep(freq, dur)`
的前两个是**位置参数、必填**，下表的默认值对 `beep` 不适用：

| 字段 | 含义 | 默认 |
|------|------|------|
| `wave` | `sine` / `square` / `triangle` / `saw` / `noise` | `square` |
| `freq` | 起始频率 Hz | 440（`note` 用） |
| `sweep` | 扫频终点 Hz（坠落音/上升音） | 无 |
| `dur` | 总时长（含释放段） | 0.25（`note` 用） |
| `volume` | 0..1 | 0.35 |
| `attack` / `release` | 起振 / 释放时长 | 0.004 / 0.05 |
| `priority` | 池满时的抢占权重：`0` 氛围 / `10` 普通音效 / `20` 关键反馈；越大越优先 | 0 |

> **声部池与优先级**：同时发声的声部有上限（约 48 个）。池满时新触发**不会**挤掉同档或更高的
> 声音，而是被丢弃并计入 `state.query` 的 `dropped`；只有当新触发的 `priority` **严格大于**
> 池中某个声部时才抢占它——被抢占的声部用 ~6ms 淡出，不硬切。**音乐声部永远不被抢占**，
> 所以环境音再多也不会把配乐挤断；音序器音符按内部最高档（`100`）参与比较，可抢占任何
> **非音乐**声部（优先丢氛围音；音乐之间仍不互相抢占）。
> 卡带可传的值范围是 `0..99`，越界自动钳制。

> **记谱约定**：一拍 = 十六分音符（一格 = 一步）；`-` 为休止；
> `=` 为**延音**（延续本轨上一个音，时值拉长、力度略降）——
> 用它能写出有呼吸感的旋律，而不是全程断奏。
>
> **轨道音色**：轨道可写成 `{ wave=, volume=, attack=, release=, steps= }`，
> 例如低音用 `triangle` 更柔和、旋律用 `square` 保持复古感；
> 打击乐同样受轨道音量控制。
>
> 音乐状态由主机持有：换卡或拔卡时自动停止卡带音乐；
> **游戏暂停（Esc）时音频整体冻结，继续时原地续播**。

## phos.ui

界面分两层：

- **声明式界面**（`phos_api = 7`，推荐）：`phos.ui.render(spec)` 提交一棵元素树，
  布局、焦点、滚动、勾选、文本输入与主题配色由引擎负责——卡带只声明"有什么"。
- **绘制原语**（更低层，旧卡带继续可用）：`frame` / `modal` / `menu` / `bar` / `text` /
  `divider` / `center_text` / `sprite` / `nav` / `line` / `outline` / `circle`，
  配合 `phos.ui.region` 的裁剪矩形使用。

两层的配色都取自当前主题声明的色板（与 `phos.color` 同源）。坐标是**内容区局部坐标**
（0-based）；`surface = "panel"` 时是面板局部坐标。

### 声明式界面：`phos.ui.render(spec)`

在 `draw()` 里提交一棵元素树；引擎按**盒模型**排版、维护焦点与控件状态，然后直接画到
当前帧的画面。返回本帧的**事件数组**。

**三条使用约定**

1. **在 `draw()` 里调用**：它写的是当前帧画面。`update()` 之后画，画面才属于这一帧。
2. **事件在下一帧 `update()` 里处理**：事件表只在本帧有效，不跨帧保存。
3. **同一帧只让一个界面消费输入**：世界 UI、侧栏、浮窗同帧出现时，给**负责输入**的那次传
   `input = true`（默认），其余传 `input = false`（只画）。否则同一次按 A 会被几个界面
   各处理一遍。

```lua
local pending = {}                       -- 上一帧 draw 返回的事件

function update(dt)
  for _, e in ipairs(pending) do         -- 先消费，再清空
    if e.kind == "activated" and e.id == "pause/list" then
      if e.index == 1 then paused = false end
    elseif e.kind == "cancelled" then
      close_top()
    end
  end
  pending = {}
end

function draw()
  phos.screen.clear()
  draw_world()                           -- 世界画面仍用 phos.screen 原语
  draw_ui()                              -- 界面见下面三个例子
end
```

**例一：侧栏（`surface = "panel"`，只显示）**

```lua
phos.ui.render{
  screen = "panel", surface = "panel", input = false,
  kind = "column", padding = { x = 1, y = 1 }, gap = 1,
  children = {
    { kind = "text", text = phos.cart.info().name, accent = true },
    { kind = "divider", fg = "dark_gray" },
    { kind = "stat", text = "SCORE", value = tostring(score) },
    { kind = "stat", text = "BEST",  value = tostring(best), accent = true },
    { kind = "spacer", grow = 1 },       -- 把后面的内容压到侧栏底部
    { kind = "hint", items = {
        phos.input.key_name("a"), "开始",
        phos.input.key_name("start"), "暂停",
      } },
  },
}
```

`surface = "panel"` 要求 manifest 声明了 `sidebar`；没有侧栏时这次 render 是空操作
（不画、不消费输入、返回空表）。

**例二：暂停浮窗（`rect` 定位，唯一消费输入的界面）**

```lua
pending = phos.ui.render{
  screen = "pause", surface = "content", input = true,
  rect = { x = 25, y = 18, w = 30, h = 9 },     -- 内容区局部坐标
  kind = "box", title = "PAUSED", border = "double", opaque = true,
  children = {
    { kind = "list", id = "pause/list",
      items = { "继续", "设置", "退出" }, indent = 2, text_gap = 2 },
    { kind = "hint", items = { phos.input.key_name("a"), "确认",
                               phos.input.key_name("b"), "返回" } },
  },
}
-- 事件：{ kind = "activated", id = "pause/list", index = 1 }（index 从 1 起）
```

**例三：文本域**

```lua
pending = phos.ui.render{
  screen = "name", surface = "content", input = true,
  rect = { x = 20, y = 16, w = 40, h = 7 },
  kind = "column", gap = 1, padding = { x = 2, y = 1 },
  children = {
    { kind = "text", text = "输入昵称", dim = true },
    { kind = "field", id = "name/input", width = 24, max_chars = 12,
      filter = "printable", text = "最多 12 字" },   -- text 是占位提示
    { kind = "hint", items = { phos.input.key_name("a"), "确认",
                               phos.input.key_name("b"), "取消" } },
  },
}
-- 事件：{ kind = "submitted", id = "name/input", text = "..." }
-- 当前值：phos.ui.field_text("name/input", "name")
```

- 文本域聚焦时，引擎自动接管 `phos.input.text()`；被其他控件聚焦时不读。
- `filter`：`"printable"`（默认）/ `"ascii"` / `"digits"` / `"hex"` / `"letters"` / `"any"`；
  `max_chars` 是**码点数**上限（0 = 不限）；退格按码点处理。
- 每个界面用独立的 `screen`（例里 `"panel"` / `"pause"` / `"name"`）：焦点、滚动、勾选与
  文本域状态按它分开存，互不串。
- **输入法**：文本域聚焦时，render 会向主机请求系统输入法（`state.query.ime` / 仅 Windows
  实际生效）；`input.text` 注入的多字节文本也可以进入，ASCII / 数字输入不受影响。

**顶层字段**

| 字段 | 类型 | 说明 |
|---|---|---|
| `kind` | string? | 根元素种类；省略时把 spec 本身当容器，数组部分即子元素 |
| `id` | string? | 根 id；缺省 = `screen` |
| `children` | table? | 子元素数组 |
| `surface` | string? | `"content"`（默认，内容区）/ `"panel"`（侧栏，需 manifest 声明 sidebar）/ `"playfield"`（内容区扣掉右栏与分隔线）；未知值按 `content` |
| `rect` | table? | `{x, y, w, h}`：在 surface 区域内的**偏移与大小**；省略 = 占满该区域。顶层元素占满该 rect——根上的 `width` / `height` 不生效，排版写在子元素上 |
| `screen` | string? | 跨帧状态的命名空间（焦点/滚动/勾选/文本域），缺省 `"cart"` |
| `input` | boolean? | 本帧是否消费输入，缺省 `true`；同一帧多次 render 只应有一次 `true` |

**元素种类（`kind`）**

| kind | 作用 | 交互 |
|---|---|---|
| `column` | 纵向容器（缺省根种类） | — |
| `row` | 横向容器 | — |
| `box` | 带边框 / 标题 / 内边距的容器 | — |
| `text` | 一段文字（`overflow` / `lines` / `scale`） | — |
| `divider` | 一条横线 | — |
| `spacer` | 占位（用 `grow` 撑开） | — |
| `list` | 可选列表（光标 + 滚动 + 禁用行） | A → `activated(index)` |
| `stat` | "标签 …… 取值"行（取值右对齐） | — |
| `option` | 左右改值的一行（显示 `text`，卡带自己格式化） | 左右 → `changed(delta)`；A → `changed(delta=1, confirm=true)` |
| `checkbox` | 勾选项（`[x]` / `[ ]`） | A → `changed(checked)` |
| `field` | 文本输入框 | A → `submitted(text)` |
| `bar` | 进度条（`ratio` 0..1；`fg` 覆盖填充色，`bg` 需 `opaque = true` 才生效） | — |
| `button` | 按钮行 | A → `activated` |
| `hint` | 页脚键位提示（`items` 为 `[键, 说明]` 交替） | — |
| `table` | 表格：`columns` 表头 + `rows` 数据，列宽/对齐可指定（表头下自动画分隔线） | — |
| `grid` | 等宽网格：按 `cols` 列逐行摆放子项（卡片/按键/头像墙） | — |
| `scroll` | 纵向滚动视口：`height` = 视口高、`scroll` = 纵向偏移（行）；`width` + `scroll_x` 可横向滚动；超出视口的子项被引擎裁剪 | — |

**元素字段**

| 字段 | 类型 | 默认 | 说明 |
|---|---|---|---|
| `width` / `height` | integer | 0 | **内容尺寸**（边框与内边距另加）；0 = 自动 |
| `min_w` / `min_h` / `max_w` / `max_h` | integer | 0 | 尺寸约束（0 = 不限） |
| `grow` | integer | 0 | 父容器主轴上的伸展权重（>0 参与分配剩余空间） |
| `gap` | integer | 1 | 容器内子项间距；顶层省略 `kind` 时根容器默认 0（子项紧贴） |
| `padding` / `margin` | integer 或 table | 0 | 数字 = 四边同值；`{x, y}` 或 `{l, t, r, b}` |
| `align_h` | string | `"stretch"` | `start` / `center` / `end` / `stretch`；column/box 控制子项水平落点；row 中子项按主轴顺序排，只有 `stretch` 会占满行高（center/end 暂无横向效果） |
| `align_v` | string | `"start"` | `start` / `center`；目前用于 text 的垂直居中（其它值按 start） |
| `opaque` | boolean | false | 是否铺实底；**只有 true 时 `bg` 才生效**（默认透明，透出世界/下层） |
| `bg` / `fg` | 色板名或 `{r,g,b}` | 主题角色 | 底色 / 前景色；色板名如 `"green"`、`"dark_gray"` |
| `border` | string | `"none"` | `none` / `single` / `double` |
| `title` | string | — | 边框标题（嵌在上边框，需有 border） |
| `dim` / `accent` / `danger` | boolean | false | 用主题的次要 / 强调 / 危险色作前景（`fg` 优先） |
| `scale` | integer | 1 | 文字字号倍率（>=2 成块放大） |
| `overflow` | string | `"ellipsis"` | `clip` / `ellipsis` / `wrap` |
| `lines` | integer | 1 | `wrap` 时的最大行数 |
| `text` | string | — | text / option / button / stat 的正文；field 的**占位提示** |
| `value` | string | — | stat 的右值；field 的**初始内容**（只在首次出现时写入） |
| `items` | string[] | — | list 的行；hint 的 `[键, 说明]` 交替 |
| `cols` | integer | 0 | grid 的列数（0 = 全部排一行）；单元格宽度均分可用宽度 |
| `scroll` | integer | 0 | scroll 的内容偏移（行）；由卡带显式控制，引擎负责视口裁剪 |
| `scroll_x` | integer | 0 | scroll 的横向内容偏移（列）；内容宽于视口时才启用横向滚动 |
| `scrollbar` | boolean | true | scroll 内容溢出时在视口右/下画位置指示条（只显示，不可拖拽） |
| `columns` | string[] | — | table 的表头（空 = 无表头；有表头时自动加一条分隔线） |
| `rows` | table[] | — | table 的数据行：每行一个字符串数组；数字单元格按整数/两位小数转文本 |
| `widths` | integer[] | — | table 各列**固定宽**；0 或缺省 = 按内容自适应。列间固定 2 格；剩余宽度只均摊到自适应列（全固定列时右侧留白） |
| `col_align` | string[] | start | table 各列对齐：`left` / `center` / `right` |
| `disabled` | table? | — | list 中不可选的行：**1 基**下标数组 `{2, 5}` 或等长布尔数组 |
| `ratio` | number | 0 | bar 的比例（0..1，越界按 0/1 画） |
| `checked` | boolean | false | checkbox 的**初值**；之后以用户操作为准 |
| `filter` / `max_chars` | string / integer | `"printable"` / 0 | field 的输入过滤与码点数上限 |
| `enabled` | boolean | true | false = 不可聚焦、按主题的禁用色画 |
| `indent` / `text_gap` | integer | 0 / 1 | 选中标记的缩进、正文相对标记的间距 |
| `label_w` | integer | 0 | stat 的标签列宽；0 = 主题默认（16） |
| `absolute` / `x` / `y` | boolean / integer | false / 0 | true = 相对父内容区定位，不参与流式布局（column/row/box/scroll；grid 不支持绝对定位） |

表格示例（表头 + 右对齐数值列）：

```lua
{ kind = "table", columns = { "RANK", "NAME", "SCORE" }, widths = { 4, 8, 6 },
  col_align = { "left", "left", "right" },
  rows = { { "1", "ALPHA", "1200" }, { "2", "BETA", "900" } } },
```

**交互与焦点**

- 按 **A 确认、B 取消**（卡带键位；主机的 Esc/F2 仍归主机）。**Tab 下一个焦点、Shift 上一个**。
- 方向键**按住约 300ms 后每 3 帧连发一格**（长列表不必连点）；松开立即重置，
  点按永远只走一格。帧数由 UI 层固定，与真实帧率无关的测试可复现
- 初始焦点 = 声明顺序里第一个可聚焦且 `enabled` 的元素；焦点与滚动按 `screen` 跨帧保留。
- 列表聚焦时，上下移动光标（循环、跳过 `disabled` 行），A 触发 `activated`。
- 表单（option / checkbox / button / field）聚焦时，上下 / Tab / Shift 移动焦点，A 确认。
- 可聚焦的种类只有 list / option / checkbox / field / button；文本、框、分隔线不参与焦点。

**事件表**

| 事件 | 附加字段 | 触发 |
|---|---|---|
| `activated` | `id`、`index`（list 行号，**1 基**） | A 在列表 / 按钮上确认 |
| `changed` | `id`、`delta`（option，-1/+1）、`confirm`（option）、`checked`（checkbox 新值） | 改值 / 勾选 |
| `submitted` | `id`、`text` | A 在文本域上提交 |
| `cancelled` | `id`（取消时的焦点 id，可能为空串） | B |

事件只出现在 `input = true` 的那次 render 的返回值里。

**查询与状态**

| 调用 | 说明 |
|---|---|
| `phos.ui.focus()` | 最近一次负责输入的 render 的焦点 id；没有焦点时为 `""` |
| `phos.ui.checked(id, screen?)` | checkbox 当前勾选态；`screen` 缺省 = 最近一次负责输入的界面 |
| `phos.ui.set_checked(id, value, screen?)` | 设置勾选态（卡带自己持有真值时用） |
| `phos.ui.field_text(id, screen?)` | 文本域当前内容；未知 id / 非文本域返回 `""` |
| `phos.ui.reset()` | 清空全部界面状态（焦点 / 滚动 / 勾选 / 文本域）；换场景时调用 |

- `checked` 与 field 的 `value` 是**初值**，只在控件第一次出现时写入；之后以用户操作为准。
- 元素树每帧重建：不要把 spec 或控件对象存起来跨帧用；跨帧状态只有上面那张表里的东西。
- `id` 建议显式给出且同屏唯一：焦点、事件与 agent/自测观测都以它为键；省略时按
  "父 id/序号" 派生，不要依赖自动 id 跨版本稳定。
- `input = false` 的 render 不返回事件，也不更新 `focus()` 的查询目标。

**agent 可观测（只读）**

- `state.query` 的顶层 `ui` 字段（没有卡带界面时为 `null`）：
  `{"screen", "focus", "widgets": [{"id", "role", "label", "state"}]}`。只列**可交互控件**
  （list / checkbox / field / option / button）与**负责输入的那一屏**（`input = false` 的
  显示界面不入表、也无法聚焦）；最多 64 个，超出带 `"truncated": true`。
  `state`：list = `{"selected": 1 基, "count"}`，checkbox = `{"checked"}`，field = `{"text"}`。
- 控制命令 `ui.list`（同一快照）/ `ui.focus{id}` / `ui.activate{id}`：`ui.activate` 与玩家按 A
  完全同语义，请求在下一逻辑帧的 render 生效。字段与示例见
  [agent-interface.md](agent-interface.md) 的「界面：读控件树、按 id 操作」一节。

### 滚动视口：kind = scroll

height 指定视口高度，scroll 指定纵向偏移（行，从 0 起）；width + scroll_x 可做横向滚动
（内容宽于视口时子项按自然宽排布，否则按视口宽拉伸，纵向列表行为不变）。
偏移由卡带显式控制（比如只显示日志尾部：scroll = max(0, #lines - height)）；
超出视口的子项由引擎**裁剪绘制**，不会漏到视口外。 内容溢出时默认在视口右缘/下缘画一条位置指示（`scrollbar = false` 可关）。`scroll` / `scroll_x` 只在首次出现时作为初值；
之后视口会**自动跟随焦点**（纵横各自把焦点"刚好"滚进可视区）
（焦点移出可视区时滚动刚好够用的行数），与 checkbox 的 `checked` 初值同一套语义。

### 瞬时提示：phos.ui.toast(text, seconds?)

底边居中浮一条消息，几秒后自动消失；**不接管输入、不冻结世界**，连续调用只显示最新几条。
计时跟逻辑帧走（暂停时冻结），不需要卡带自己算时间：

```lua
phos.ui.toast("SAVED")              -- 缺省 1.6 秒
phos.ui.toast("LEVEL 3", 2.0)
```

### 绘制原语（更低层）

以下函数是**无状态**绘制原语：调用时立刻往当前网格写，不持有焦点、滚动或控件状态。
旧卡带与特效继续可用；新代码优先用上面的 `render`。

**约定**：坐标为内容区局部坐标（0-based）；`phos.ui` 的**菜单索引同样 0-based**
（与屏幕坐标一致）。`items` 表本身仍是普通 Lua 数组——两者互不影响。

```lua
-- 边框（标题嵌在上边框，可留空）
phos.ui.frame(x, y, w, h, "INVENTORY")
```

> **`frame` 只画边框，不铺底**。卡带侧的界面样式默认**保留背景**——
> 卡带的浮窗/边框压在游戏画面上时不铺底。
> 需要一块**不透明浮窗**（挡住世界）时先铺底板：
> `region:clear(fg, bg)`（或 `fill`）铺满，再往上画边框与文字。
> 这与层的透明规则是同一件事的两面：**只写字形 = 透出世界，给了底色 = 盖住世界**

```lua

-- 居中浮窗：返回布局表 { x, y, w, h }，内容由卡带自己画
local box = phos.ui.modal(40, 16, "SETTINGS")
phos.ui.frame(box.x + 2, box.y + 3, box.w - 4, box.h - 6, "")
phos.ui.text(box.x + 4, box.y + 4, box.w - 8, "text goes here", 3)

-- 列表菜单（'>' 光标 + 高亮；h 省略时与条目数一致）
phos.ui.menu(x, y, w, { "SWORD", "SHIELD", "POTION" }, selected, h)

-- 进度条 / 分隔线 / 居中文本 / 折行正文
phos.ui.bar(x, y, w, hp / max_hp)
phos.ui.divider(x, y, w)
phos.ui.center_text(y, "GAME OVER")
phos.ui.text(x, y, w, "long body text...", 3)   -- 最多 3 行，超出加省略号（max_lines 可省略，缺省 1 行）

-- 像素精灵：rows 为字符画，colors 为 字符→颜色（'.' 与空格透明）
-- 颜色键按 UTF-8 首码点读取：["#"] 与 ["中"]/["→"] 都可以；旧单字节键行为不变
-- step 为**降采样步长**（缺省 1）：step=2 时源图每 2 行 / 2 列取一格，成品是源图的一半大小；
-- 它不是放大倍数（< 1 钳到 1）
-- brightness 为亮度 0..1（可省略，缺省 1；非有限按 1，越界钳制）：只缩放前景色/填充色
-- solid 为 true 时每个非空艺术字符不画字形，而用映射色（未命中用风格 accent）填满该格底：
-- 该格前景与底色都置为映射色（覆盖原有底色）；缺省 false 时仍只画字形、保留原底色
phos.ui.sprite(x, y, { "..##..", ".####." }, { ["#"] = { 80, 255, 120 } }, 1, 0.6)
phos.ui.sprite(x, y, { "中##中" }, { ["中"] = { 80, 255, 120 }, ["#"] = { 255, 80, 80 } },
               1, 1.0, true)   -- 实心色块

-- 列表导航（内部复用输入抽象）：返回 新下标, 动作
local index, action = phos.ui.nav(#items, selected)
-- action 为 "none" / "confirm" / "cancel"
```

### 几何原语：line / outline / circle

三个**无状态**几何绘制原语，坐标同为内容区局部坐标，越界部分静默裁剪
（线段先与屏幕网格求交再光栅化，屏幕外的超大坐标不会变成无界循环）：

```lua
phos.ui.line(2, 2, 70, 30)                        -- 斜线：Bresenham，陡/平/反向都正确
phos.ui.outline(10, 4, 20, 8, "#")                -- 空心框：1 格边线
phos.ui.circle(40, 22, 6, "o", phos.color.cyan)   -- 空心圆：midpoint，八向对称

-- 末尾参数：ch?, fg?, bg?
-- ch 缺省：线/框 '-'、圆 'o'
-- fg 缺省 = 激活色板的 white；bg 缺省 = 保留该格原有底色（不铺底）
-- fg/bg 接受 phos.color.*（色板色）或 {r,g,b} 表
```

- `outline` 的 `w`/`h` < 2 时退化：单列 / 单行 / 单格；`circle` 的 `r <= 0` 只画一格
- 三者都**只写字形，不铺底**（省略 `bg` = 透出下层）；要实底先 `fill` / `region:clear`
- `line` 同一格只写一次；`circle` 只光栅化可见弧段，半径再大也不会把主机拖住
- `phos.ui.region` 上也有同名方法（`map:line` / `map:outline` / `map:circle`）：
  坐标相对区域、参数相同，**自动裁在区域内**（不会画到区域外）

**导航示例**（背包/设置浮窗的典型写法）：

```lua
function update(dt)
  if not menu_open then return end
  local new_index, action = phos.ui.nav(#items, selected)
  selected = new_index
  if action == "confirm" then use_item(selected) end
  if action == "cancel"  then menu_open = false end
end
```

> 组件层与 `phos.panel` 的分工：`phos.panel` 是主机划定的**固定侧栏区**，
> `phos.ui` 是卡带在自己画面里自由布置的**任意窗口**。

## phos.panel

侧栏面板（卡带在 manifest 声明 `sidebar.w` 后可用）。
坐标为**面板局部坐标**：`(0, 0)` 是面板左上角，越界写入静默裁剪到面板内
（写不到内容区与机身装饰上）。
分隔线由主机统一绘制，卡带只负责面板内容。

```lua
w, h = phos.panel.size()        -- w = 0 表示本卡带无面板
phos.panel.put(x, y, ch, fg, bg)
phos.panel.print(x, y, text, fg, bg)
phos.panel.put(x, y, ch, fg, bg, scale)     -- 同 screen：scale>=2 = 大字号（占 scale 列 x scale 行）
phos.panel.print(x, y, text, fg, bg, scale)
phos.panel.fill(x, y, w, h, ch, fg, bg)  -- 省略 bg = 主题面板色 skin.panel
phos.panel.blit(x, y, rows, fg, bg)     -- 一次写多行（恒写底色，省略 = 色板 black）
phos.panel.clear(fg, bg)        -- 只清面板区（省略 bg = 主题面板色 skin.panel）
phos.panel.blend(x, y, ch, fg)  -- 同格追加一笔（叠加）
phos.panel.back(x, y, bg)       -- 只写底色：字形与已叠的笔迹都不动
phos.panel.back_rect(x, y, w, h, bg)
phos.panel.plot(x2, y2, fg)     -- 子格落笔（一格 = 2x2 子位）
phos.panel.resize(w)            -- 运行时改宽度（0 = 收起，上限 32）；返回实际宽度
```

### 绘制区域与窗口：`phos.ui.region(x, y, w, h, opts)`

一个**带裁剪的矩形**，坐标一律相对区域左上角，越界不画。它同时解决两件事——
**非浮动分区**（侧栏某块放小地图、游戏区某块放状态条）与**浮动窗口**（卡带自己的
设置/暂停/背包）：

```lua
-- 1) 非浮动分区：侧栏上半块放小地图
local map = phos.ui.region(0, 0, 20, 10, { surface = "panel" })
map:frame("MAP")
map:blit(1, 1, rows)                 -- 一次写多行（地图/表格搬运）

-- 2) 浮动窗口：卡带自己的设置面板（画在底图之后就是"浮在上面"）
local win = phos.ui.region(20, 5, 40, 12)
win:frame("SETTINGS")
win:menu(2, 2, 36, items, selected)  -- 窗口里的菜单，自动裁剪在窗口内
win:print(2, 10, long_text)          -- 超出窗口的部分被裁掉，不会溢出
win:outline(1, 1, 38, 10)            -- 空心框：坐标相对窗口，自动裁在窗口内
win:circle(20, 6, 3, "o", phos.color.cyan)  -- 空心圆：单格半径，画在区域里
```

- `opts.surface`：`"screen"`（默认，内容区）或 `"panel"`（侧栏面板）
- `opts.layer`：把区域锚定到某个**图层**（见 `phos.layer` 一节）。坐标原点仍是内容区左上角；
  层里的空白格是透明的，所以"只写字形"就等于把字压在世界之上
- 构造时与表层可用范围**求交**，所以 `x`/`y`/`w`/`h` 字段给的就是实际可画范围
- 可用的绘制方法：`clear` / `put` / `print` / `fill` / `blit`（多行）/ `blend`（同格叠加）/
  `back` / `back_rect`（只写底色）/ `plot`（子格落笔）/ `frame` /
  `divider` / `bar` / `menu`（`h` 可省略，缺省按条目数）/ `body`（折行正文，
  `max_lines` 可省略）/ `sprite`（`step` = 降采样步长、`brightness` = 0..1 亮度、
  `solid` = 实心色块，均可省略）/
  `line` / `outline` / `circle`（几何原语：与 `phos.ui.*` 同名同参数，坐标相对区域、
  **自动裁在区域内**）。其中 `put` / `print` / `fill` / `blit` / `clear`
  省略 `bg` 时一律**保留背景**（"透明底"）；`blend` / `back` / `back_rect` / `plot`
  与 `put` 同组，也**保留背景**
- **层级 = 调用顺序**：本机每帧清屏、卡带每帧重画，所以先画底图、再画窗口即可；
  窗口关闭时不再画它，底图自然就在（不需要"备份背景再还原"那类机制）
- 上面这条说的是**底层**。要让"浮层"与"世界"各自独立、互不擦除，用 `phos.layer`——
  那是可选能力：不用它的卡带，行为与以前完全一样
- 字段 `x/y/w/h` 是**构造时**与表层求交的结果：运行时改了面板宽度（`phos.panel.resize`）
  后需重新创建区域。旧区域即使不重建也不会写到面外（写入会按当前面板宽度再裁一次），
  但它报的 `w` 会比实际能画的宽
- 字段 `surface`：区域锚在哪张表层上 → `"screen"` / `"panel"`；锚到图层时返回**层名**
  （便于自检"我确实画到那一层去了"，agent 也爱看这一项）
- **`keep` 的解析域永远是"写入目标那张网格"**：区域的 `put` / `print` / `fill` 省略 `bg`
  时保留的是**目标网格该格**的原底色——写内容区就保内容区的，写某层的区域就保**该层**的。
  "保留底色"从不跨网格；跨层的"透下去"只有一条路：那一格**根本没写到**（见 `phos.layer`）

## phos.scene

场景栈：把"暂停菜单 / 背包 / 设置 / 结算"这类**压在世界上面的界面层**交给引擎排程。
一层场景 = 一张声明表（可选 `update` / `draw` / `on_enter` / `on_exit`），引擎负责：

| 引擎负责 | 说明 |
|---|---|
| 推进顺序 | 每逻辑帧只调用**栈顶**的 `update(dt)` |
| 绘制顺序 | 卡带 `draw()` 之后，从栈底到栈顶依次调用各层的 `draw()`（天然压在世界之上） |
| 世界冻结 | 栈上（不只栈顶）有 `pause_world = true` 的场景时，跳过卡带的 `update` |
| 音频暂停 | 栈上有 `audio_pause = true` 的场景时暂停音频，出栈后恢复 |

输入**不归引擎路由**：场景的 `draw` 里通常调用 `phos.ui.render{...}`（它消费本帧按键并返回事件），
场景的 `update` 消费上一帧存下的事件——这样"按键改状态"仍发生在 update 里，符合绘制只画不写的约定。

```lua
local pending = {}

local function pause_update(dt)
  for _, e in ipairs(pending) do
    if e.kind == "activated" and e.id == "menu" then
      if e.index == 1 then phos.scene.pop() end      -- RESUME
    elseif e.kind == "cancelled" then
      phos.scene.pop()                                -- B 返回
    end
  end
  pending = {}
end

local function pause_draw()
  local events = phos.ui.render{
    screen = "pause",
    rect = { x = 20, y = 15, w = 40, h = 10 },
    kind = "box", title = "PAUSED", border = "single", opaque = true, bg = "black",
    children = {
      { kind = "list", id = "menu", items = { "RESUME", "QUIT" }, indent = 2, text_gap = 2 },
      { kind = "hint", items = { phos.input.key_name("a"), "ok", phos.input.key_name("b"), "back" } },
    },
  }
  for i = 1, #events do pending[#pending + 1] = events[i] end
end

function update(dt)
  if phos.input.pressed("start") and phos.scene.depth() == 0 then
    phos.scene.push{
      id = "pause", modal = true, pause_world = true, audio_pause = true,
      update = pause_update, draw = pause_draw,
    }
  end
end
```

```lua
phos.scene.push{ id = "pause", modal = true, pause_world = true, audio_pause = true,
                 update = fn, draw = fn, on_enter = fn, on_exit = function(result) end }
phos.scene.pop(result)      -- 弹栈并执行 on_exit(result)
phos.scene.clear()          -- 清空整栈（不执行退出回调；重开一局/换场景时用）
phos.scene.top()            -- 栈顶 id；空栈 nil
phos.scene.depth()          -- 栈深（上限 8）
phos.scene.modal()          -- 栈顶是否声明 modal
phos.scene.pause_world()    -- 栈上是否有场景冻结世界
phos.scene.audio_pause()    -- 栈上是否有场景暂停音频
```

- 卡片字段：`id`（缺省 `"scene"`）、`modal`、`pause_world`、`audio_pause`、`update(dt)`、
  `draw()`、`on_enter()`、`on_exit(result)`；后四个均可省略
- 回调里可以继续 `push` / `pop`：引擎先排队、回调返回后再落地（不会在"正在执行的那层"上动刀）
- 压栈的那一帧**不调用**新场景的 `update`：按键在那一帧仍是"按下"状态，立刻调 update 会把开门键当成关门键
- `pause_world` / `audio_pause` 是**整栈查询**：压着菜单时世界就该停，回到栈顶也一样
- 场景栈随卡带生命周期：换卡/拔卡清空，不跨卡带
- agent 侧可读：`state.query.scenes` 报出底→顶的场景清单（id / modal / pause_world / audio_pause）
- 样板：`devkit/examples/scene/`（暂停浮窗：世界冻结、音频暂停、出栈恢复）

## phos.layer

**可选**图层：世界照旧画在底层（`phos.screen`），层只描述"叠在它上面的缓冲"。
不调用 `phos.layer.create` 的卡带完全不受影响——主机连一次合成都不会做。

```lua
local hud = phos.layer.create("hud", { z = 20 })      -- 建层：z 越大越靠上
local overlay = phos.layer.create("overlay", { z = 30 })
local r = phos.ui.region(0, 0, 80, 45, { layer = "hud" })

function draw()
  draw_world()                                        -- 世界：照旧写 phos.screen
  r:print(2, 1, "HP [=====]", phos.color.cyan)        -- 只给字形 → 字压在世界之上
  if paused then
    local w = phos.ui.region(20, 8, 40, 12, { layer = "overlay" })
    w:clear(phos.color.gray, phos.color.dark_gray)     -- 先铺不透明底板 → 挡住世界
    w:frame("PAUSE")                                   -- frame 只画边框，不铺底
  end
end
```

一层里的某一格落到画面上的规则（这就是"透明"的全部含义）：

| 层里的那一格 | 合成结果 |
|---|---|
| 没写到（透明） | 原样透出下层 |
| 只有字形（`print` / `put` 省略 `bg`） | 字形覆盖，**底色保留下面的** → 字压在世界底上 |
| 给了底色（`fill`、`put` 带 `bg`） | 底色覆盖；字形槽以这一层为准（写空格 = 抹掉下层字形） |

- **alpha 是布尔，不是半透明**：上面这张表就是全部规则——一格的"底色存不存在"只有两态，
  没有 0~255 的插值。真半透明留给以后的世代（字节已预留，现在不做）
- **"压暗世界"的半透观感由抖屏给出**（字符机的惯用手法）：在 overlay 层按
  `(x + y) % 2 == 0` 铺深色格、其余留透明——远看就是压暗：

  ```lua
  -- win 是锚在 overlay 层、盖住整个世界区域的 region
  for y = 0, win.h - 1 do
    for x = (y % 2 == 0) and 0 or 1, win.w - 1, 2 do
      win:put(x, y, " ", phos.color.dark_gray, phos.color.dark_gray)  -- 铺底色 = 盖住
    end
  end
  ```

- 层**每帧由主机清成透明**，与底层"每帧重画"同一心智：这帧不再画它，它就消失
- 层随卡带生命周期：插卡为空、拔卡销毁；层名只在本卡带内有意义
- 层数上限 **6**：层数直接乘进每帧的合成开销，所以是硬上限，超出时 `create` 报错
- 层名写错（区域锚定到不存在的层）：写入回落到内容区，并留一次日志——不会静默画到别处
- `phos.layer.create(name, opts)` 返回**层句柄**：`handle.name`（只读）、`handle.visible`
  （读写，整层显隐，合并时跳过）、`handle.z`（读写，调层序）、`handle:clear()`
  （整层清成透明）。注意 `visible` / `z` 是**字段**不是方法：写 `handle.visible = false`
- `phos.layer.order()` 返回层名数组（按 z 升序）；`phos.layer.remove(name)` 注销一层
  （此后写入它的区域回落到内容区并留痕）
- 单层读取（agent 用）：`screen.read(layer = "hud")` 读某一层自己的内容（内容区局部坐标）；
  `layer = "screen"` 读**合并后的整屏**（层是就地合并进底层的，没有"合并前的那一层"可读，
  所以这个取值与不写 `layer` 等价，只是把"我读的是整屏"明说出来）
- 合并不影响游戏速度；`state.query` 的顶层 `merge_ms` 报出每帧合成耗时（没建层的卡带恒为 0）

**两层叠在同一格**：渲染是**按像素**叠的 —— 底层（世界）先画，各层再按 z 升序各画一遍：
只有给过底色的格才铺底，字形只画自己的笔画，**笔画之外是透明的**。于是雨滴落在地形格上时，
雨滴的笔画压在地形像素之上、笔画之外仍是地形 —— 两种内容同格共存，而不是"上层把下层顶掉"。

**屏幕文本是另一回事**：文本视图一格只有一个字形槽，`screen.read` 与 `--dump-screen` 取的是
合并结果（最前面那一笔赢），所以**文本里看不到"同格的两种内容"**，只有画面与 `screenshot`
看得到。同格共存不必再挤到不同的层上：`phos.screen.blend` 直接叠一笔、`plot` 落半格
（见 `phos.screen` 一节）。

## phos.net

局域网联机：**开房 / 加入 / 收发消息 / 发现**。引擎只做**传输**——连接、房间（对端列表）、
消息投递、可观测；**同步模型**（锁步 / 行动中继 / 主机权威）由卡带自己在 `send` / `poll`
上实现。未调用 `host` / `join` 时完全休眠（不占端口、不起线程）。

- 传输是 **TCP 星型 + 主机中继**：客人只与主机相连，客人之间互发由主机转发。
- 对端 id：主机恒为 `1`，客人依次 `2, 3, …`；`0` 是**广播地址**（`send(0, …)` = 发给除自己外所有人）。
- 收发与连接维护在后台线程：`send` 只入队、`poll` 只取队（与音频同一套"主线程不阻塞"的心智）。
- **例外**：`join` 的 TCP 连接（最多等 3 秒）与 `discover` 的收集窗口（默认 0.5 秒）在调用它的
  那一帧同步完成——它们是有界阻塞，不要每帧调用。
- **房间可广播"是否还接受加入"**：主机开局前 `open = true`，开局后 `phos.net.set_room({ open = false })`；
  搜索方在 `discover()` 结果里读到 `open`，据此提示"游戏中、无法加入"。
- 设计细节（拓扑、协议、线程、确定性注意）属引擎内部设计，不随发行包发布。

```lua
-- 开房 / 加入
phos.net.host({ port = 7770, name = "P1" })        -- 成功返回 true
phos.net.join_async("192.168.1.20", { port = 7770, name = "P2" })  -- 不阻塞；结果走事件
phos.net.join("192.168.1.20", { port = 7770, name = "P2" })
phos.net.stop()                                     -- 离开 / 关房

-- 状态与房间
phos.net.status()      -- "off" | "hosting" | "connecting" | "connected" | "error"
phos.net.role()        -- "none" | "host" | "client"
phos.net.error()       -- 最近一次错误串（无则 ""）
phos.net.connected()   -- 主机=已开房；客人=已连上主机
phos.net.self_id()     -- 自己的对端 id（未联机 0）
phos.net.host_id()     -- 主机对端 id（未联机 0）
phos.net.port()        -- 游戏 TCP 端口（未联机 0）
phos.net.local_ip()    -- 本机局域网 IPv4（提示用）
phos.net.peers()       -- { { id, name, address, rtt_ms }, ... }（不含自己）

-- 消息：data 是可 JSON 化的表（可省）；kind 是卡带自定义的类型串
phos.net.send(to_id, kind, data)         -- to_id = 0 表示广播给其他所有人
phos.net.broadcast(kind, data)           -- 等价 send(0, kind, data)
for _, m in ipairs(phos.net.poll()) do   -- 本帧收到的：{ from, kind, data }
  if m.kind == "shot" then apply_shot(m.data) end
end

-- 连接变化事件（与消息分开，便于大厅 UI）
for _, e in ipairs(phos.net.events()
-- 事件类型：connected / disconnected / connect_failed（带 reason）) do -- { type="connected"|"disconnected", peer, name }
  print(e.type, e.peer)
end

-- 局域网发现：广播查询并收集应答（有界阻塞，默认 0.5 秒）
-- 帧内用异步版（后台扫描，主线程不阻塞）：
phos.net.discover_async(0.6)
local rooms = phos.net.discover_poll()   -- nil = 还没好；表 = 结果（空表 = 0 个房间）
phos.net.discovering()                   -- 是否有扫描在途

for _, room in ipairs(phos.net.discover(0.5)) do
  -- 字段：name / address / port / players（人数）/ open（房主是否还接受加入）
  local tag = room.open and ("x" .. room.players) or "IN GAME"   -- 开局后的房间标"游戏中"
  phos.ui.text(2, y, 40, room.name .. "  " .. room.address .. ":" .. room.port .. "  " .. tag)
  y = y + 1
end

-- 更新房间对外广播（发现应答用）：主机开局后调一次，搜索方就会看到"游戏中"并拒绝加入
phos.net.set_room({ open = false })
```

> **谁负责同步**：引擎不做锁步/回滚。回合制卡带（如炮弹对战）用"行动中继"——
> 只在轮到某人动作时把该动作发给对方；严格锁步需要**双方同种子**，并且卡带里
> 用 `phos.sys.random`（`math.random` 不受主机种子控制）。局域网内同版本二进制可保证
> 逐位一致；跨平台浮点不保证一致。

> 自测：`tools/net_smoke.py`（同机起两进程，验证连接、局域网发现、消息互通、断开事件）。
> 它用 `tools/fixtures/net/` 的夹具卡带驱动——那是**开发目录里的测试夹具，不随发行包**。

## phos.input

输入抽象为虚拟键名：方向 + 动作键 + 系统键。
输入来源是**物理键盘、标准布局手柄**与 **agent 注入**（手柄映射见 [playing.md](playing.md)），
它们在此汇入同一队列，卡带无从分辨来源。

```lua
-- 持续按住（在 update 中查询） --
phos.input.down("left")  / "right" / "up" / "down"
phos.input.down("a")     / "b"     / "x"  / "y"
phos.input.duration("right")   -- 已按住的秒数（松开 = 0）：长按类手感不必自己攒计时
phos.input.keys()              -- 主机见过的所有键名（写"按任意键改绑定"时遍历它）
phos.input.down("start") / "select"
-- 键盘专属的四颗：空格 / 逗号 / 句点 / 退格（不映射到任何动作键）
phos.input.down("space") / "comma" / "period" / "backspace"

-- 边沿触发：本帧刚按下 / 刚松开 --
phos.input.pressed("a")
phos.input.released("a")

-- 任意文本输入（用于命名、密码、输入磁带码等场景） --
-- 语义是"本帧"：每帧清空，所以在 update 里读到的就是这一帧新敲的字符
local s = phos.input.text()      -- UTF-8 字符串；无输入时为空串
-- 能收到中文等多字节字符——前提是本帧有声明 ime = true 的输入框被 feed（见下节）：
-- 主机的系统输入法只在那时开着。退格以 '\b'（U+0008）送达，需自行处理：
--   while #s > 0 do
--     local ch = utf8.char(utf8.codepoint(s))   -- 按码点切，不能按字节切
--     s = s:sub(#ch + 1)
--     if ch == "\b" then name = name:sub(1, -2) else name = name .. ch end
--   end
```

**动作映射**：把"跳跃 / 确认 / 左"这类玩家意图绑定到一组虚拟键，查询时**任一键满足即为真**；
未注册的动作默认映射同名虚拟键（`action_down("left") == down("left")`）。

```lua
-- 注册 / 替换：keys 可为字符串或字符串数组；返回当前键列表
local keys = phos.input.action("jump", { "space", "a" })
phos.input.action("jump", "space")          -- 单键也可以
phos.input.action("jump", {})               -- 已注册、无绑定键：任何物理键都不触发
local current = phos.input.action("jump")   -- 省略 keys = 只查询（未注册返回 { "jump" }）

-- 查询：任一绑定键满足即真
if phos.input.action_down("jump") then ... end      -- 持续按住
if phos.input.action_pressed("jump") then ... end   -- 本帧刚按下
if phos.input.action_released("jump") then ... end  -- 本帧刚松开
```

动作表**按卡带生命周期存在**（插拔 / 重载时清空，不写盘）；同一动作最多 16 个键。
非法 name / keys（含非字符串项、不可见字符）返回 `nil` 并写 warning。

默认键位映射：

| 虚拟键 | 键盘 | 说明 |
|--------|------|------|
| 方向 | 方向键 | 不用 WASD（A/S/D/W 会与面键冲突） |
| a / b | **A / B** | `a` 是确认，`b` 是取消 / 返回 |
| x / y | **X / Y** | 卡带专用（主机保留键是 Esc / F2） |
| start / select | Enter / Shift | `start` 是卡带自己的开始 / 暂停 |
| space / comma / period / backspace | **空格 / , / . / 退格** | 键盘专属：留给"用了就舒服"的功能（发射、镜头平移、悔棋这类）；手柄没有对应键，这四颗只在键盘上 |
| 其余任意键 | F1–F25、Tab、Home/End/Insert/Delete、PageUp/PageDown、小键盘、Ctrl/Alt/Super、其余符号… | **全部按键都有稳定名字**，卡带直接用 `phos.input.pressed("home")` / `"f5"` / `"tab"` 即可，**主机不为某个键改代码**；键名表见 `phos.input.keys()`。Esc / F2 除外（主机保留） |
| 系统菜单 | Esc | 主机保留，卡带收不到 |

键位分两层：

- **主机界面**（开机 / 卡带架 / 设置 / 暂停 / 错误屏）走 PC 习惯：
  Enter 确认、Esc 返回或暂停、F2 打开设置、方向键选择。动作键 / 面键在这里无效。
- **卡带游戏内**用动作键（虚拟键名）：A 确认、B 取消、X / Y 次功能、Enter 开始或暂停、Shift 选择。

**一个功能一个键**：不为同一按钮提供替代键（J/K/Z/C/V 一律无效，
主机界面的提示也只写主键名）。同一物理键的不同位置不算替代——左右 Shift、
主键盘与小键盘的 Enter 都可用，按"键帽上的字"算同一个键。

> **手柄**：标准布局手柄映射到同一套虚拟键——左摇杆/十字键 → 方向，A/B/X/Y → `a/b/x/y`，
> START/BACK → `start/select`，LB/RB → `lbrace/rbrace`；键盘与手柄同时可用（任一来源按下即按下），
> 详见 [playing.md](playing.md)。
> 卡带写操作提示时用 `phos.input.key_name("a")` 取真实键名
> （返回 "A"/"ENTER"/"SHIFT"/"LEFT"…），而非写死 "A"/"START" 之类的手柄叫法——
> 否则提示与实际能按的键不一致。

### 任意键捕获：`phos.input.any_pressed()`

```lua
local key = phos.input.any_pressed()   -- 本帧新按下的键（虚拟键名）；没有则 nil
if key then
  bindings.jump = key
  phos.save.write("bind_jump", key)
  -- 显示给玩家看时，取键盘上真实的键名
  phos.ui.text(2, 10, 40, "JUMP = " .. phos.input.key_name(key), 1)
end
```

主机保留键（`Esc` / `F2`）**不会**被捕获到——它们永远属于主机，卡带看不到。
拿到键名后存进 `phos.save` 就是一份玩家自定义键位表。

### 文本框：`phos.input.field(cfg)`

命名、密码、输入磁带码这类"要玩家敲一串字"的场景用**输入框缓冲**：
过滤、按码点退格、限长都在主机侧完成，与主机界面的磁带码输入是**同一套实现**——
所以"删掉一个中文字"不会变成半个字符。

```lua
local name = phos.input.field({ filter = "printable", max = 12 })

function update(dt)
  name:feed()                       -- 每帧一次；同一帧重复调用是幂等的
  if phos.input.pressed("start") then submit(name.value) end
end

-- name.value     当前文本（UTF-8，永远是完整的码点序列）
-- name.count     已录入的**码点**数（中文与半角同样算 1）
-- name:clear()   清空
```

- `filter` 预设：`"any"`（默认）/ `"printable"` / `"ascii"` / `"digits"` / `"hex"` / `"letters"`；
  也可以传 `function(cp) return true end` 自己判（`cp` 是码点数字，回调出错按"不接受"处理）
- `max` 是**码点数**上限（0 = 不限）
- `ime = true` 才允许**收中文**（默认关）。主机据此在该框被 `feed` 的那一帧打开**系统输入法**；
  不声明的框收不到中文（拼音候选里选出来的字进不来），所以"哪些框要中文"由卡带在**代码里**
  说了算（如联机昵称框 `ime = true`，纯数字 / hex 的框不声明）。主机自带的卡带架搜索框不走
  卡带声明，由主机在编辑期间打开输入法（同一条开关路径），因此也能直接输中文。
  仅在 Windows 上由主机开关输入法；其它平台交给各自的输入法框架
- 缓冲随卡带一起销毁；要持久化时自己写进 `phos.save`

## phos.save

需 manifest 声明 `save = true`；值支持**文本 / 数字 / 布尔 / 表**（读回是同一类型/同构表），否则 `available()` 返回 false 且写入被忽略（不报错）。

表的映射规则（`write` 时判定，`read` 时按同构还原）：

- 连续 `1..n` 整数键 = **数组**；其余键 = **对象**（键转字符串，数字/布尔键也转）
- 嵌套深度 ≤ **8**；函数 / userdata / thread / 表作为键 / 环引用 / 键转字符串后撞车 / 裸 `nil` / NaN / inf 一律拒绝，`write` 返回 false（不静默存半份）
- 结构化值按**其 JSON 文本长度**计入 ≤4096 的上限；`null` 不合法（与"键不存在"无法区分）
- 磁带码 `export()`/`import()` 仍走文本语义：表值以 JSON 文本携带，导入后成为**文本值**（结构不保留）

```lua
phos.save.available()           -- 存档是否可用
phos.save.write(key, value)     -- value 为文本/数字/布尔；入库成功返回 true
local v = phos.save.read(key)   -- 不存在返回 nil
phos.save.erase(key)
phos.save.slot(n)              -- 切换存档槽（0 = 默认，1..9 独立文件）；返回是否成功
phos.save.slot_index()         -- 当前槽位

local code = phos.save.export() -- 导出磁带码（可复制文本）
local ok = phos.save.import(code) -- 从磁带码恢复（**整份替换**）；码非法返回 false 且不做改动
```

入库约束（`write` 与 `import` 共用，越界即拒绝）：

| 项 | 上限 | 说明 |
|----|------|------|
| 键长 | 64 | 非空，且不含 `=` 与换行 |
| 值长 | 4096 | 不含换行 |
| 条目数 | 256 | 新键超出后不再接受 |

> 磁带码是"整份存档"的载体：`import` 成功即替换全部条目（不是合并）。
> 导入前会全量校验，任何一处非法都保持原存档不变。

## phos.lang

多语言取值：文案属于卡带内容，主机只提供"取当前语言那一条"的机制。

```lua
local t = phos.lang.dict({ zh = { score = "得分" }, en = { score = "SCORE" } })
local word = phos.lang.pick({ zh = "普通炮弹", en = "SHELL" })
local words = phos.lang.shared()   -- 通用词表（SCORE/BEST/PAUSED/RESUME/...）
```

- `dict(fields)`：返回 `{zh=…,en=…}` 里当前语言那一张表（**引用**，每帧取一次即可跟随切换）
- `pick(fields)`：取单条；两者都是**缺 en 回落中文**，漏翻不会露出空串
- `shared()`：引擎自带的通用词表（18 个常用词，取当前语言那一列）。每调用一次新建一张表——
  在 `init` 里取一次就够了，语言切换后按需重取；卡带自己的专有词仍写在自己的 `Text` 表里

## phos.assets

读取卡带包内的文件。路径相对包根；越界（`..`）一律拒绝；**缺失返回 `nil` / `false`，
不抛异常**（缺资源怎么处理是卡带自己的事）。

```lua
local text = phos.assets.text("assets/title.txt")   -- 全文；缺失返回 nil
local rows = phos.assets.rows("assets/map.txt")     -- 按行（1 基数组，保留空行）；缺失返回 nil
local ok   = phos.assets.exists("assets/map.txt")   -- 是否存在
local size = phos.assets.size("assets/map.txt")     -- 字节数（缺失为 0）
local all  = phos.assets.list("assets/")            -- 列出包内文件（可省略前缀）
```

> **单文件上限 8 MiB**：`text` / `rows` 会整读进内存，超过上限的文件**拒读**（返回 `nil`
> 并写主机日志），避免超大素材把 Lua 堆撑爆。`size` / `exists` 只查元信息、不读
> 全文，所以**先问大小再决定读不读**是安全的（`exists` 对超大文件仍如实报告存在）。
```

适合放的东西：关卡 / 地图 / 对话表（一行一个元素，用 `rows` 读）、字符画素材、
音频文件（配合 `phos.audio.sample`）、平衡性数值表（改数值不必动代码）。

> 覆盖层 Mod 生效时读到的是替换后的内容，卡带代码无感知
> （做覆盖层 Mod：在 `mods/<mod-id>/` 里放好替换文件，再由 `mod.lua` 的 `overrides`
> 登记到键 `<卡带id>/assets/…`，见 content-packs.md）。

## phos.score

卡带排行榜：TOP N 分数，写进**当前卡带的存档**（需要 manifest 声明 `save = true`；
没声明时只在内存里工作，`available()` 返回 false——卡带不需要为此写分支）。
排序、截断、存档键与坏档容错都在引擎侧，卡带只回答"加多少分"。

```lua
local board = phos.score.new{ max = 5, key = "scores" }  -- 构造时自动装载

board:add(1200)      -- 插入并返回名次（1 基）；没进 TOP N 返回 0
board:best()         -- 第一名（空榜 = 0）
board:list()         -- 降序数组，最多 max 项
board:clear()        -- 清空并落盘
board:available()    -- 存档是否可写（manifest 未声明 save 时为 false）
board:key()          -- 实际使用的存档键

phos.score.top(5, "scores")   -- 只读地取前 N 名（不写盘）
```

- `max` 钳到 **1..20**（缺省 5）；`key` 缺省 `"scores"`，过长/含 `=` 或换行时回退默认键
- 只接受非负整数；同分保持插入顺序（先到的排前面）
- 存档是逗号分隔的整数串，坏项跳过而不是整榜作废；写入失败只记日志，卡带照常运行
- 换卡/重载不串榜：每个实例绑定当前卡带的存档句柄

## phos.cart

```lua
local cart = phos.cart.info()   -- 取一次存起来（每次调用都会建一张新表）
cart.id       -- "snake"   卡带 id
cart.name     -- "SNAKE"   卡带架与侧栏显示的标题
cart.version  -- "1.0.0"   作者自己的版本号（与主机版本无关）
cart.author   -- 作者
cart.desc     -- 简介（按当前界面语言取；英文缺失时回落中文）
```

卡带的身份以 `manifest.lua` 为**唯一来源**：标题画面、关于页、标题栏都从这里读；
在 Lua 里再抄一份字符串时，改了 manifest 就会留下对不上的旧文案。
未插卡时（主机脚本，例如出厂启动动画）各项为空串。

## phos.observe

给 agent 看的玩法状态用**声明式观测**声明一次：每个字段可以是值，也可以是函数，
引擎在 `state.query` 时求值——观测因此永远与真实状态一致，不必维护一份会过期的手写快照。

```lua
function init()
  phos.observe{
    score = function() return score end,
    hp = function() return hp end,
    units = function() return summarize_units() end,   -- 返回表也可以（深度 4 序列化）
    wave = wave,                                        -- 固定值直接写
  }
end
```

- 在 `init()` 里登记一次即可；之后 `state.query` 的 `debug` 字段自动带上这些键
- 字段可以是 number/string/boolean/表（数组写成 JSON 数组；超过深度 4 的嵌套截断）
- 单个字段求值报错只跳过该字段，不影响整份观测；登记了 `debug_state()` 的卡带仍以它为准
- 老写法 `debug_state()` 继续有效；新卡带推荐 `phos.observe`（少一份手写快照）

## phos.debug

把玩法里的常数登记进"**可调篮子**"，就能在运行中用 `~` 呼出的调试台**拖滑条实时改**，
无需反复改代码重启。移动速度、生命值、武器半径/威力等常数都可登记。

```lua
-- 浮点（滑条）：get 读当前值、set 写回，range 决定滑条
local SPEED = 1.0
phos.debug.number("移动速度", function() return SPEED end,
                  function(v) SPEED = v end, { min = 0.1, max = 3.0, step = 0.05 })

-- 整数（滑条取整）：弹药 / 弹丸数之类
phos.debug.integer("弹药", function() return W.ammo end, function(v) W.ammo = v end,
                   { min = 0, max = 20, step = 1 })

-- 布尔（复选框）
phos.debug.toggle("无敌", function() return GOD end, function(v) GOD = v end)

-- 嵌套数据也能调（回调自己存取）+ 分组折叠：武器表里第 1 件放在 "武器/<名字>" 下
phos.debug.number({ zh = "爆炸半径", en = "Blast radius" },
                  function() return WEAPONS[1].radius end,
                  function(v) WEAPONS[1].radius = v end,
                  { group = { { zh = "武器", en = "WEAPONS" }, WEAPONS[1].name },
                    min = 1, max = 12, step = 0.5 })
```
三个入口形状相同：**浮点** `phos.debug.number`、**整数** `phos.debug.integer`（滑条取整）、**布尔**
`phos.debug.toggle`（复选框）。分别对应面板里的浮点滑条 / 整数滑条 / 勾选框。

- `get` / `set` 是**卡带自己的函数**，后端存储随意（局部变量、表字段、对象成员都行）。
  `get` 在**面板打开**、`state.query`、
  以及 `debug.set` 匹配名字时被调用，无需每帧执行。
- `opts`：`min` / `max`（滑条范围，缺省 0 / 1）、`step`（缺省 0.01；**当前滑条样式下保留未用**）。
  退化范围有兜底（`max <= min` 记作 `min + 1`，`step <= 0` 记作 0.01）；**空名 / 同组重名 /
  超过上限（128）**的注册会被忽略。
- **类型对得上**：`integer` 的 get 返回整数、set 收到**整数**；`toggle` 的 get 返回 `true/false`、
  set 收到**布尔**——卡带直接 `X = v` 即类型匹配，无需转换（给浮点会让 HUD 显示 `5.0`，
  给 0 在 Lua 里是真值，勾选框就"关不掉"）。
- **注册随卡带生命周期**：拔卡即清；未插卡（主机脚本）时调用安全无效。
- 面板里的改动**下一帧**才写回（不在渲染中途改卡带状态）。
- 同一批参数也经控制通道暴露：`state.query.debug_params`（读）+ `debug.set`（写）——
  agent 也能实时调参（见 `agent-interface.md`）。注意 `debug.set` **不做 min/max 钳制**
  （那是滑条的活），值原样交给卡带的 `set`。
- 调试台用**反引号键**（`` ` ``，就是键盘左上角那个 `~` 键）呼出。
- **分组**：`opts.group` 把参数放进折叠层级（`"武器"` / `{zh=,en=}` 单层；数组 = 多层，如
  `{ {zh="武器",en="WEAPONS"}, weapon.name }`）。分组是**默认关闭**的折叠节点，将来新增的
  组 / 参数自动出现——遍历武器表逐件登记即可，加武器时面板自己会长出来。
- **文案随语言**：`name` 与组标签都可写成 `{ zh = …, en = … }`；切界面语言时篮子文案跟着变。
- 调试台 **HOST** 页里有个开关 **`Pause while panel is open`**：勾上后打开调试台即**冻结整机**
  （卡带 `update` 不跑、`phos.sys.time` 不走、声音也停；画面仍按当前状态重绘），用于对静止画面细调。

## phos.sys

```lua
local t   = phos.sys.time()        -- 卡带运行秒数（从 init 起）
local fps = phos.sys.fps()         -- 当前实际帧率
local fr  = phos.sys.frame()        -- 当前逻辑帧号（"每 N 帧一次"不必自己数）
local r   = phos.sys.random(1, 100) -- 区间随机整数（确定性模式下由种子驱动）
phos.sys.seed(42)                   -- 重置随机种子

phos.sys.log("debug info")          -- 写主机日志（开发期）
phos.sys.version()                  -- 主机版本（唯一权威来源）
phos.sys.product()                  -- 产品名 "PHOSPHOR"
phos.sys.language()                 -- 界面语言 "zh" / "en"（见下）
phos.sys.capture_escape(true)       -- 接管 Esc：此后 Esc 是普通键（phos.input "escape"），
                                    -- 主机不再拿它做暂停/返回。联机对局用它弹"非暂停"菜单
```

### 卡带文案的多语言

**卡带文案属于卡带内容**，主机只告诉卡带"当前是什么语言"（`phos.sys.language()`），
怎么翻译由卡带自己决定；**取值那一步用 `phos.lang`**，不必自己写查表：

```lua
-- 整屏的文案写成"两列"：新增语言只需再加一列
local Text = {
  zh = { over = "游戏结束", restart = "按 %s 重开" },
  en = { over = "GAME OVER", restart = "press %s to restart" },
}

function draw()
  local t = phos.lang.dict(Text)      -- 每帧取一次，跟随设置里的语言切换
  phos.ui.center_text(mid, t.over)
  phos.ui.center_text(mid + 2, string.format(t.restart, key))   -- 带参数的用 %s / %d
end

-- 单条（武器名、状态文案这类一条一对的记录）：
local label = phos.lang.pick({ zh = "普通炮弹", en = "SHELL" })
```

- `phos.lang.dict(fields)` 返回**原表里的那一张**（引用，不拷贝）：每帧取一次即可，
  设置里切了语言，下一帧的读数就跟着变
- `phos.lang.pick(fields)` 取单条；两者都是**缺 en 回落中文**，漏翻不会露出空串
- 排版一律用 `phos.text.pad` / `phos.text.width` 量宽度：中英宽度不同（汉字 2 列、
  字母 1 列），写死列号、或按字节补空格的排版，在英文下必然错位

按几列居中用 `phos.text.width` 判断；`#str` 数的是字节。

---

## 默认配色下的一个完整示例

```lua
local x, y = 40, 22

function update(dt)
  if phos.input.down("left")  then x = x - 1 end
  if phos.input.down("right") then x = x + 1 end
  if phos.input.pressed("a") then phos.audio.beep(880, 0.05) end
end

function draw()
  phos.screen.clear()
  phos.screen.print(2, 1, "PHOSPHOR DEMO", phos.color.green)
  phos.screen.put(x, y, "@", phos.color.yellow)
end
```

## 设计说明（给实现者）

- API 表通过**开放注册表**装配（各模块可注册子表），为主机插件预留
- 所有颜色/屏幕参数流经 palette 内容包，API 层不硬编码任何风格数值
- 每个 API 函数必须对非法参数防御（类型检查 + 明确报错），错误信息面向卡带作者而非主机开发者

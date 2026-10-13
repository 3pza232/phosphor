# PHOSPHOR Host API 参考

卡带通过全局表 `phos` 与主机交互。这篇是**卡带作者的主要参考**：每个调用给
"一句话说明 + 签名 + 最小示例"，按模块分节。

> **怎么用**：写卡带时把本页当字典查；想先跑起来再回头查，走 [devkit.md](devkit.md)。
> 编辑器补全定义在 `devkit/phos.lua`，与本文件是同一份规范的两个面向——改了 API
> 两者都要更新，`phosphor --check-api` 会替你核对有没有漏。

---

## 总览

```lua
phos.screen   -- 字符屏幕：一切画面表达
phos.ui       -- 组件层：边框/浮窗/菜单/进度条/正文/精灵/导航/绘制区域
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
> **声明了右栏的卡带要按可玩区排版**：
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

-- 读取（调试/AI 友好，性能开销由主机吸收） --
ch, fg, bg = phos.screen.get(x, y)
```

越界写入**静默裁剪到内容区**（侧栏与机身装饰不在卡的写入范围内），不报错——
卡带不必为边缘坐标防御性编程。四条写入一族的口径一致：`put` / `print` / `fill` / `blit`
都按内容区边界裁剪，其中 `print` / `blit` 按**显示宽度**截断（汉字算两格）。
读取同理：`screen.get` 落在内容区之外时返回空串。

**省略 `bg` 时怎么办？** 分两组，这是写卡带最容易踩的一条：

| 调用 | 省略 `bg`（或传 `nil`） |
|---|---|
| `screen.put` / `screen.print`、`panel.put` / `panel.print` | **保留该格原有背景**（"透明底"）：字/图标压在地形、天空、机身上都不留色块 |
| `ui.region` 的 `put` / `print` / `fill` / `blit` / `clear` | 同上，一律保留背景（覆盖层压在游戏画面上不会糊出一块块黑底） |
| `screen.fill` / `screen.clear` / `screen.blit` / `screen.back` / `screen.back_rect`、`panel.blit` / `panel.back` / `panel.back_rect` | **总是写底色**：省略 = **激活色板的 `black`**（随主题变，不写死黑）——这族是"整块搬运 / 清一块地方" |
| `panel.fill` / `panel.clear` | 省略 = **主题面板色**（`skin.panel`）：右栏不属于游戏画面，底色随主题，不透出游戏、也不是写死的黑 |

> **省略 `fg`（前景）时 = 激活色板的 `white`。** 于是"换主题（预设）"会连同卡带的清屏底与文字底色一起改变——这是多主题适配的根。

所以"要让这块地方不透底"是**显式给色**，而不是指望默认值：
`phos.screen.print(x, y, text, fg, bg)`。

**底色的粒度就是"一格"，不可能更细** —— 这一条值得单独记住，因为它决定了
"底板贴合字身"这类想法能不能做：

- 一格只有一个底色，而且**后写的整格会覆盖先写的**：世界与浮层写的是同一格，
  先画的内容不会留在底下。所以"背景只有字身那么窄"或"底板半透明、透出战况"
  在 API 层面**做不到**，别往这个方向设计
- 真要"底色贴合字身"，正路是换一款**字身填满格子**的字体（`theme/font/<方案>/`）
- 反过来，"**不要底板**"完全可行，而且往往更好看：**省略 `bg`** 即可 ——
  省掉的是底板，**不是**这一格的底（世界的底色留着，不会变黑洞）。
  例：WORMS 里虫子的 `@` 标与它头顶的箭头就不垫底板，压在天空/土层上都不留色块

### 同一格里放两样东西：`blend` 与 `plot`

一格只有一个字形槽，但**不是只能放一样东西**：`put` 是"把这一格改成这个字"（替换），
`blend` 是"再画一笔"（叠加）。两笔在渲染时各自按**字形覆盖率**混合 ——
于是"两种内容落在同一格"两笔都看得见，重叠处后面那笔的颜色占优。

- 只收半角字形；同一格最多叠 **3 笔**（含 `put` 那一笔）。满了 `blend` 返回 `false`
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
-- 共 12 色，实际色值由当前主题声明的色板决定（"绿色"在不同主题上味道不同）

local c = phos.color.rgb(255, 128, 0)   -- 自定义色（会被 palette 做辉光映射）
```

## phos.text

文本度量。**全角字符（CJK 等）占两列、UTF-8 占三字节**，所以排版一律用它，
不要用 `#str`（那会数成 3 列）：

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
所以要"底板/装饰贴住字身"就得按它算，而不是按整格猜。拿不到字体度量时（无头运行、
字体未就绪）返回整格宽并置 `approx = true`。

**定宽位置（侧栏、状态条）用 `fit` 而不是 `truncate`**：主机在右侧是硬切，
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

--   曲式写法（长曲子推荐：乐段 + 曲序，两分钟级不必写成长龙）：
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
> `index` / `count`（曲序位置与总数）。写长曲子时靠它确认曲式真的在走，
> 而不是只看谱面猜——`tools/` 下的脚本就是这么验的。
> 同一处还会给出 `voices`（活跃声部数）与 `dropped`（请求队列丢弃数），
> 后者非 0 说明卡带一帧内触发的声音多到超过了队列长度。

```lua
-- 采样：卡带包内的音频文件（wav / mp3 / flac，内存解码）
local hit = phos.audio.sample("assets/hit.wav")   -- 句柄，0 = 失败
phos.audio.play_sample(hit, { volume = 0.8, loop = false })
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

主机组件层：边框、浮窗、菜单、进度条、正文、像素精灵、列表导航。
与系统界面**共用同一套绘制原语**，因此卡带界面与主机界面风格天然一致；
配色取自当前主题声明的色板（与 `phos.color` 同源）。

**约定**：坐标为内容区局部坐标（0-based）；`phos.ui` 的**菜单索引同样 0-based**
（与屏幕坐标一致，避免 C++/Lua 两端基准错位）。
`items` 表本身仍是普通 Lua 数组——两者互不影响。

```lua
-- 边框（标题嵌在上边框，可留空）
phos.ui.frame(x, y, w, h, "INVENTORY")
```

> **`frame` 只画边框，不铺底**。卡带侧的界面样式默认**保留背景**（见 `core/ui.cpp` 的
> cart style）——卡带的浮窗/边框压在游戏画面上时，不该把底下糊成一块黑板。
> 因此要一块**不透明浮窗**（挡住世界），得自己先铺底板：
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

-- 像素精灵：rows 为字符画，colors 为 字符→颜色（'.' 与空格透明），step 为缩放步长（可省略，缺省 1）
phos.ui.sprite(x, y, { "..##..", ".####." }, { ["#"] = { 80, 255, 120 } }, 1)

-- 列表导航（内部复用输入抽象）：返回 新下标, 动作
local index, action = phos.ui.nav(#items, selected)
-- action 为 "none" / "confirm" / "cancel"
```

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
```

- `opts.surface`：`"screen"`（默认，内容区）或 `"panel"`（侧栏面板）
- `opts.layer`：把区域锚定到某个**图层**（见 `phos.layer` 一节）。坐标原点仍是内容区左上角；
  层里的空白格是透明的，所以"只写字形"就等于把字压在世界之上
- 构造时与表层可用范围**求交**，所以 `x`/`y`/`w`/`h` 字段给的就是实际可画范围
- 可用的绘制方法：`clear` / `put` / `print` / `fill` / `blit`（多行）/ `blend`（同格叠加）/
  `back` / `back_rect`（只写底色）/ `plot`（子格落笔）/ `frame` /
  `divider` / `bar` / `menu`（`h` 可省略，缺省按条目数）/ `body`（折行正文，
  `max_lines` 可省略）/ `sprite`（`step` 可省略）。其中 `put` / `print` / `fill` / `blit` / `clear`
  省略 `bg` 时一律**保留背景**（"透明底"）；`blend` / `back` / `back_rect` / `plot`
  与 `put` 同组，也**保留背景**
- **层级 = 调用顺序**：本机每帧清屏、卡带每帧重画，所以先画底图、再画窗口即可；
  窗口关闭时不再画它，底图自然就在（不需要"备份背景再还原"那类机制）
- 上面这条说的是**底层**。要让"浮层"与"世界"各自独立、互不擦除，用 `phos.layer`——
  那是可选能力：不用它的卡带，行为与以前完全一样
- 字段 `x/y/w/h` 是**构造时**与表层求交的结果：运行时改了面板宽度（`phos.panel.resize`）
  后请重新创建区域。旧区域即使不重建也不会写到面外（写入会按当前面板宽度再裁一次），
  但它报的 `w` 会比实际能画的宽
- 字段 `surface`：区域锚在哪张表层上 → `"screen"` / `"panel"`；锚到图层时返回**层名**
  （便于自检"我确实画到那一层去了"，agent 也爱看这一项）
- **`keep` 的解析域永远是"写入目标那张网格"**：区域的 `put` / `print` / `fill` 省略 `bg`
  时保留的是**目标网格该格**的原底色——写内容区就保内容区的，写某层的区域就保**该层**的。
  "保留底色"从不跨网格；跨层的"透下去"只有一条路：那一格**根本没写到**（见 `phos.layer`）

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
- **想要"压暗世界"的半透观感，用抖屏**（字符机的惯用手法）：在 overlay 层按
  `(x + y) % 2 == 0` 铺深色格、其余留透明——远看就是压暗，比亚像素级半透明更像这台机器：

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
- 运行在后台线程，主线程只入队/取队（与外设、音频同一套"主线程不阻塞"的心智）。
- **房间可广播"是否还接受加入"**：主机开局前 `open = true`，开局后 `phos.net.set_room({ open = false })`；
  搜索方在 `discover()` 结果里读到 `open`，据此提示"游戏中、无法加入"。
- 设计细节（拓扑、协议、线程、确定性注意）见 `design/networking.md`（开发文档）。

```lua
-- 开房 / 加入
phos.net.host({ port = 7770, name = "P1" })        -- 成功返回 true
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
for _, e in ipairs(phos.net.events()) do -- { type="connected"|"disconnected", peer, name }
  print(e.type, e.peer)
end

-- 局域网发现：广播查询并收集应答（有界阻塞，默认 0.5 秒）
for _, room in ipairs(phos.net.discover(0.5)) do
  -- 字段：name / address / port / players（人数）/ open（房主是否还接受加入）
  local tag = room.open and ("x" .. room.players) or "IN GAME"   -- 开局后的房间标"游戏中"，别去连
  phos.ui.text(2, y, 40, room.name .. "  " .. room.address .. ":" .. room.port .. "  " .. tag)
  y = y + 1
end

-- 更新房间对外广播（发现应答用）：主机开局后调一次，搜索方就会看到"游戏中"并拒绝加入
phos.net.set_room({ open = false })
```

> **谁负责同步**：引擎不做锁步/回滚。回合制卡带（如炮弹对战）用"行动中继"最省事——
> 只在轮到某人动作时把该动作发给对方；要严格锁步就得**双方同种子**，并且卡带里
> 一律用 `phos.sys.random`（`math.random` 不受主机种子控制）。同一份二进制在局域网内
> 逐位一致最稳；跨平台浮点不保证一致。

> 自测：`tools/net_smoke.py`（同机起两进程，验证连接、局域网发现、消息互通、断开事件）。
> 它用 `tools/fixtures/net/` 的夹具卡带驱动——那是**开发目录里的测试夹具，不随发行包**。

## phos.input

输入抽象为虚拟手柄：方向 + 动作键 + 系统键。
物理键盘/手柄/Agent 注入的输入在此统一，卡带无从分辨来源。

```lua
-- 持续按住（在 update 中查询） --
phos.input.down("left")  / "right" / "up" / "down"
phos.input.down("a")     / "b"     / "x"  / "y"
phos.input.duration("right")   -- 已按住的秒数（松开 = 0）：长按类手感不必自己攒计时
phos.input.keys()              -- 主机见过的所有键名（写"按任意键改绑定"时遍历它）
phos.input.down("start") / "select"
-- 键盘专属的三颗：空格 / 逗号 / 句点（主机不给它们配手柄替代键）
phos.input.down("space") / "comma" / "period"

-- 边沿触发：本帧刚按下 / 刚松开 --
phos.input.pressed("a")
phos.input.released("a")

-- 任意文本输入（用于命名、密码、输入磁带码等场景） --
-- 语义是"本帧"：每帧清空，所以在 update 里读到的就是这一帧新敲的字符
local s = phos.input.text()      -- UTF-8 字符串；无输入时为空串
-- 可含中文等多字节字符；退格以 '\b'（U+0008）送达，需自行处理：
--   while #s > 0 do
--     local ch = utf8.char(utf8.codepoint(s))   -- 按码点切，不能按字节切
--     s = s:sub(#ch + 1)
--     if ch == "\b" then name = name:sub(1, -2) else name = name .. ch end
--   end
```

默认键位映射：

| 虚拟键 | 键盘 | 说明 |
|--------|------|------|
| 方向 | 方向键 | 不用 WASD（A/S/D/W 会与面键冲突） |
| a / b | **A / B** | `a` 是确认，`b` 是取消 / 返回 |
| x / y | **X / Y** | 卡带专用（主机保留键是 Esc / F2） |
| start / select | Enter / Shift | `start` 是卡带自己的开始 / 暂停 |
| space / comma / period | **空格 / , / .** | 键盘专属：留给"用了就舒服"的功能（发射、镜头平移这类）；手柄上没有对应位置 |
| 系统菜单 | Esc | 主机保留，卡带收不到 |

键位分两层，别混用：

- **主机界面**（开机 / 卡带架 / 设置 / 暂停 / 错误屏）走 PC 习惯：
  Enter 确认、Esc 返回或暂停、F2 打开设置、方向键选择。虚拟手柄键在这里无效。
- **卡带游戏内**用虚拟手柄：A 确认、B 取消、X / Y 次功能、Enter 开始或暂停、Shift 选择。

**一个功能一个键**：不为同一按钮提供替代键（J/K/Z/C/V 一律无效，
主机界面的提示也只写主键名）。同一物理键的不同位置不算替代——左右 Shift、
主键盘与小键盘的 Enter 都可用，按"键帽上的字"算同一个键。

> **主机没有手柄**：四个面键就是键盘上的 A/B/X/Y 本身。
> 卡带写操作提示时请用 `phos.input.key_name("a")` 取真实键名
> （返回 "A"/"ENTER"/"SHIFT"/"LEFT"…），不要写死 "A"/"START" 之类的手柄叫法——
> 否则提示与实际能按的键会不一致，玩家按下去没反应。

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

命名、密码、输入磁带码这类"要玩家敲一串字"的场景，用**输入框缓冲**比自己拼字符串稳：
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
- 缓冲随卡带一起销毁；要持久化请自己写进 `phos.save`

## phos.save

需 manifest 声明 `save = true`，否则 `available()` 返回 false 且写入被忽略（不报错）。

```lua
phos.save.available()           -- 存档是否可用
phos.save.write(key, value)     -- value 为字符串；入库成功返回 true
local v = phos.save.read(key)   -- 不存在返回 nil
phos.save.erase(key)

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
> 并写主机日志）——一张超大素材不该无声地把 Lua 堆撑爆。`size` / `exists` 只查元信息、不读
> 全文，所以**先问大小再决定读不读**是安全的（`exists` 对超大文件仍如实报告存在）。
```

适合放的东西：关卡 / 地图 / 对话表（一行一个元素，用 `rows` 读）、字符画素材、
音频文件（配合 `phos.audio.sample`）、平衡性数值表（改数值不必动代码）。

> 覆盖层 Mod 生效时读到的是替换后的内容，卡带代码无感知
> （把同名文件放到 `mods/<卡带id>/assets/` 即可，见 content-packs.md）。

## phos.cart

```lua
local cart = phos.cart.info()   -- 取一次存起来（每次调用都会建一张新表）
cart.id       -- "snake"   卡带 id
cart.name     -- "SNAKE"   卡带架与侧栏显示的标题
cart.version  -- "1.0.0"   作者自己的版本号（与主机版本无关）
cart.author   -- 作者
cart.desc     -- 简介（按当前界面语言取；英文缺失时回落中文）
```

卡带的身份以 `manifest.lua` 为**唯一来源**：标题画面、关于页、标题栏都从这里读，
不要在 Lua 里再抄一份字符串——那样改了 manifest 就会留下对不上的旧文案。
未插卡时（主机脚本，例如出厂启动动画）各项为空串。

## phos.debug

把玩法里的常数登记进"**可调篮子**"，就能在运行中用 `~` 呼出的调试台**拖滑条实时改**，
不必反复改代码重启。写玩法时（移动速度、生命值、武器半径/威力……）随手一挂即可。

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

- `get` / `set` 是**卡带自己的函数**，后端存储随意（局部变量、表字段、对象成员都行）——
  这正是它比"声明一个值交给主机保管"更实用的地方。`get` 在**面板打开**、`state.query`、
  以及 `debug.set` 匹配名字时被调用，不必每帧执行。
- `opts`：`min` / `max`（滑条范围，缺省 0 / 1）、`step`（缺省 0.01；**当前滑条样式下保留未用**）。
  退化范围有兜底（`max <= min` 记作 `min + 1`，`step <= 0` 记作 0.01）；**空名 / 同组重名 /
  超过上限（128）**的注册会被忽略。
- **类型对得上**：`integer` 的 get 返回整数、set 收到**整数**；`toggle` 的 get 返回 `true/false`、
  set 收到**布尔**——卡带直接 `X = v` 就是对类型，不必自己转（给浮点会让 HUD 显示 `5.0`，
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
  （卡带 `update` 不跑、`phos.sys.time` 不走、声音也停；画面仍按当前状态重绘），方便对静止画面细调。

## phos.sys

```lua
local t   = phos.sys.time()        -- 卡带运行秒数（从 init 起）
local fps = phos.sys.fps()         -- 当前实际帧率
local fr  = phos.sys.frame()        -- 当前逻辑帧号（"每 N 帧一次"不必自己数）
local r   = phos.sys.random(1, 100) -- 区间随机整数（确定性模式下由种子驱动）
phos.sys.seed(42)                   -- 重置随机种子

phos.sys.log("debug info")          -- 写主机日志（开发期利器）
phos.sys.version()                  -- 主机版本（唯一权威来源：core/version.hpp）
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

不要用 `#str` 判断按几列居中，那数的是字节：用 `phos.text.width`。

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
- 每个 API 函数必须对非法参数防御（类型检查 + 友好报错），错误信息面向卡带作者而非主机开发者

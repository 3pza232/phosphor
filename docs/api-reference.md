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
phos.panel    -- 右侧栏面板（需 manifest 声明 sidebar）
phos.text     -- 文本度量与定宽裁剪（宽度单位是"列"，不是字节）
phos.color    -- 颜色常量与自定义色
phos.input    -- 输入查询
phos.lang     -- 卡带文案取当前语言那一列（dict / pick）
phos.audio    -- 合成音/音符/打击乐/音序器音乐/采样
phos.save     -- 存档（需 manifest 声明 save = true）
phos.assets   -- 包内资源读取（文本 / 按行 / 存在性 / 大小 / 列表）
phos.sys      -- 系统信息与工具
phos.cart     -- 当前卡带的身份（id / 标题 / 版本 / 作者 / 简介）
```

> `phos.color` 的 12 色常量取自当前激活的显像管滤镜（palette 内容包），
> 用户在设置中切换滤镜时，卡带里的 `phos.color.green` 等会热更新为新的色值。
> 选择滤镜 `NONE` 时使用出厂原色——需要保留卡带原本配色的游戏应选它。

> **坐标系**：`phos.screen` / `phos.panel` 使用**内容区局部坐标**，左上角为 `(0, 0)`；
> 机身外壳（游戏机主题）由主机在外围绘制，卡带不需要关心网格在窗口中的位置。
>
> 网格恒为 `80x45`，但**声明了右栏的卡带要按可玩区排版**：
> `local px, py, pw, ph = phos.screen.playfield()`（内容区扣掉右栏）。
> 照 `size()` 从 0 画到最右边，那几列会藏在面板后面——玩家只看到"东西突然冒出来"。

## phos.screen

逻辑屏幕是一个 `80 × 45` 的字符网格（**尺寸由主机固定**，与主题无关；
左上角为 `(0, 0)`。每格包含：字符、前景色、背景色。

```lua
w, h = phos.screen.size()                  -- 恒 80x45，**含侧栏覆盖的列**
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
| `screen.put` / `screen.print`、`panel.put` / `panel.print` | **保留该格原有背景**（"透明底"）：字压在地形、天空、底图上都不留色块 |
| `ui.region` 的 `put` / `print` / `fill` / `blit` | 同上，一律保留背景（覆盖层压在游戏画面上不会糊出一块块黑底） |
| `screen.fill` / `screen.blit` / `screen.clear`、`panel.fill` / `panel.blit` / `panel.clear`、`ui.region.clear` | **总是写底色**（省略 = 黑）——这些调用常被用来"整块搬运/清一块地方"，默认透明会让底图从字缝里透出来，清屏则变成什么都不做 |

所以"要让这块地方不透底"是**显式给色**，而不是指望默认值：
`phos.screen.print(x, y, text, fg, bg)`。

## phos.color

```lua
phos.color.black  .white  .gray   .dark_gray
phos.color.red    .green  .blue   .yellow
phos.color.cyan   .magenta .orange .purple
-- 共 12 色，实际色值由当前 palette 内容包决定（"绿色"在不同显像管上味道不同）

local c = phos.color.rgb(255, 128, 0)   -- 自定义色（会被 palette 做辉光映射）
```

## phos.text

文本度量。**全角字符（CJK 等）占两列、UTF-8 占三字节**，所以排版一律用它，
不要用 `#str`（那会数成 3 列）：

```lua
phos.text.width("中文 abc")            -- 8  （2+2 全角 + 1 空格 + 3 半角）
phos.text.width("hello")               -- 5
phos.text.truncate("很长的中文标题", 8)  -- "很长的中"（8 列，绝不切出半个字）
phos.text.fit("很长的中文标题", 8)       -- "很长的中…"（8 列；没超宽就原样返回）
phos.text.pad("模式", 8)                -- "模式    "（右补到 8 列）
phos.text.pad_left("42", 6)             -- "    42"（左补：取值右对齐）
```

`phos.screen` / `phos.panel` / `phos.ui` 的写文字接口都按显示宽度推进，
截断也发生在字符边界上——卡带不需要自己处理这些。全角字符的续格由主机维护，
`phos.screen.get()` 问哪一格都会返回该字符。

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

-- 采样：卡带包内的音频文件（wav / mp3 / flac，内存解码）
local hit = phos.audio.sample("assets/hit.wav")   -- 句柄，0 = 失败
phos.audio.play_sample(hit, { volume = 0.8, loop = false })
phos.audio.stop_sample(hit)
```

`beep` / `note` 的参数表字段（均可缺省）：

| 字段 | 含义 | 默认 |
|------|------|------|
| `wave` | `sine` / `square` / `triangle` / `saw` / `noise` | `square` |
| `freq` | 起始频率 Hz | 440 |
| `sweep` | 扫频终点 Hz（坠落音/上升音） | 无 |
| `dur` | 总时长（含释放段） | 0.1 |
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
配色取自当前滤镜（与 `phos.color` 同源）。

**约定**：坐标为内容区局部坐标（0-based）；`phos.ui` 的**菜单索引同样 0-based**
（与屏幕坐标一致，避免 C++/Lua 两端基准错位）。
`items` 表本身仍是普通 Lua 数组——两者互不影响。

```lua
-- 边框（标题嵌在上边框，可留空）
phos.ui.frame(x, y, w, h, "INVENTORY")

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
phos.ui.text(x, y, w, "long body text...", 3)   -- 最多 3 行，超出加省略号

-- 像素精灵：rows 为字符画，colors 为 字符→颜色（'.' 与空格透明），step 为缩放步长
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
phos.panel.fill(x, y, w, h, ch, fg, bg)
phos.panel.blit(x, y, rows, fg, bg)     -- 一次写多行（恒写底色，省略 = 黑）
phos.panel.clear(fg, bg)        -- 只清面板区（恒写底色）
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
- 构造时与表层可用范围**求交**，所以 `x`/`y`/`w`/`h` 字段给的就是实际可画范围
- 可用的绘制方法：`clear` / `put` / `print` / `fill` / `blit`（多行）/ `frame` /
  `divider` / `bar` / `menu`（`h` 可省略，缺省按条目数）/ `body`（折行正文，
  `max_lines` 可省略）/ `sprite`（`step` 可省略）。其中 `put` / `print` / `fill` / `blit`
  省略 `bg` 时**保留背景**，`clear` 省略 `bg` 时**写黑**（见 `phos.screen` 一节的 `bg` 规则）
- **层级 = 调用顺序**：本机每帧清屏、卡带每帧重画，所以先画底图、再画窗口即可；
  窗口关闭时不再画它，底图自然就在（不需要"备份背景再还原"那类机制）
- 字段 `x/y/w/h` 是**构造时**与表层求交的结果：运行时改了面板宽度（`phos.panel.resize`）
  后请重新创建区域。旧区域即使不重建也不会写到面外（写入会按当前面板宽度再裁一次），
  但它报的 `w` 会比实际能画的宽

## phos.input

输入抽象为虚拟手柄：方向 + 动作键 + 系统键。
物理键盘/手柄/Agent 注入的输入在此统一，卡带无从分辨来源。

```lua
-- 持续按住（在 update 中查询） --
phos.input.down("left")  / "right" / "up" / "down"
phos.input.down("a")     / "b"     / "x"  / "y"
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

## phos.sys

```lua
local t   = phos.sys.time()        -- 卡带运行秒数（从 init 起）
local fps = phos.sys.fps()         -- 当前实际帧率
local r   = phos.sys.random(1, 100) -- 区间随机整数（确定性模式下由种子驱动）
phos.sys.seed(42)                   -- 重置随机种子

phos.sys.log("debug info")          -- 写主机日志（开发期利器）
phos.sys.version()                  -- 主机版本（唯一权威，当前 "0.1.1"）
phos.sys.product()                  -- 产品名 "PHOSPHOR"
phos.sys.language()                 -- 界面语言 "zh" / "en"（见下）
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

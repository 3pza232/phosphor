---@meta
-- PHOSPHOR Host API —— 编辑器补全定义（EmmyLua / Lua Language Server）
--
-- 用法（VSCode + Lua 插件）：在卡带工程里引用本文件即可获得补全与参数提示，
-- 例如在 .luarc.json 中：
--   { "workspace.library": ["../devkit/phos.lua"] }
--
-- 本文件只描述类型，不参与运行；实现见 src/api/。
-- 规范文档见 docs/api-reference.md。

---颜色：由当前主题声明的色板（skin.palette）决定，切换主题时热更新
---@class phos.Color
---@field r integer
---@field g integer
---@field b integer
phos = {}

---@class phos.color
---@field black phos.Color
---@field white phos.Color
---@field gray phos.Color
---@field dark_gray phos.Color
---@field red phos.Color
---@field green phos.Color
---@field blue phos.Color
---@field yellow phos.Color
---@field cyan phos.Color
---@field magenta phos.Color
---@field orange phos.Color
---@field purple phos.Color
phos.color = {}

---构造自定义颜色
---@param r integer 0~255
---@param g integer 0~255
---@param b integer 0~255
---@return phos.Color
function phos.color.rgb(r, g, b) end

---@class phos.screen
---@field width integer
---@field height integer
phos.screen = {}

---屏幕网格尺寸（字符格），恒为 80x45。**含侧栏覆盖的部分**：
---画"游戏画面"请用 phos.screen.playfield()，否则右侧会被侧栏挡掉几列
---@return integer w, integer h
function phos.screen.size() end

---可玩区：内容区扣掉侧栏以后的那一块（左上角 + 宽高）。任何"自适应铺满"的排版
---都应该以它为准——侧栏宽度可以随包声明，也能在运行时用 phos.panel.resize() 改，
---所以它是**函数**而不是字段：每次都按当前宽度算
---  local px, py, pw, ph = phos.screen.playfield()
---@return integer x, integer y, integer w, integer h
function phos.screen.playfield() end

---写入单个字符（越界裁到内容区，不会画到侧栏或机身装饰上；省略 bg = 保留该格原有背景）
---@param x integer
---@param y integer
---@param ch string|integer 字符（也可给**码点**整数）
---@param fg phos.Color|nil
---@param bg phos.Color|nil
---@param scale integer|nil 字号倍数：>=2 时是大字号（占 scale 列 x scale 行），上限 3；省略=1
function phos.screen.put(x, y, ch, fg, bg, scale) end

---写一行文本（超出内容区宽度的部分按**显示宽度**截断，汉字算两格；省略 bg = 保留该格原有背景）
---@param x integer
---@param y integer
---@param text string
---@param fg phos.Color|nil
---@param bg phos.Color|nil
---@param scale integer|nil 字号倍数（>=2 时每个字占 scale 列 x scale 行，逐字前进）
function phos.screen.print(x, y, text, fg, bg, scale) end

---填充矩形（**总是写底色**，省略 = 黑）
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param ch string|integer 字符（也可给**码点**整数）
---@param fg phos.Color|nil
---@param bg phos.Color|nil
function phos.screen.fill(x, y, w, h, ch, fg, bg) end

---清屏（**总是写底色**，省略 = 黑）
---@param fg phos.Color|nil
---@param bg phos.Color|nil
function phos.screen.clear(fg, bg) end

---读取某格字符（与 `--dump-screen` 是同一份字符屏幕，两者可逐字对照）。
---越界（内容区之外）返回空串

---@param x integer
---@param y integer
---@return string ch, phos.Color fg, phos.Color bg
function phos.screen.get(x, y) end

---一次写多行（每行一条字符串）：地图/画面搬运用，比逐格 put 少一堆调用。
---超出内容区宽度的部分按**显示宽度**截断，不会溢到机身装饰上；**总是写底色**（省略 = 黑）
---@param x integer
---@param y integer
---@param rows string[]
---@param fg phos.Color|nil
---@param bg phos.Color|nil
function phos.screen.blit(x, y, rows, fg, bg) end

---在**同一格**追加一笔（叠加）：不清掉这一格已有的字形与笔迹。
---两笔各自按字形覆盖率混合，"两个东西落在同一格"因此是叠加而不是顶替
---@param x integer
---@param y integer
---@param ch string|integer 字符（也可给**码点**整数）
---@param fg phos.Color|nil
---@return boolean ok false = 越界，或这一格已叠满（3 笔）
function phos.screen.blend(x, y, ch, fg) end

---只写这一格的**底色**：字形与已叠的笔迹都不动。
---"背景比字形宽一格"就在本格之外再 back 一次
---@param x integer
---@param y integer
---@param bg phos.Color|nil 省略 = 黑（与 fill 同组：这是"写底"的调用）
function phos.screen.back(x, y, bg) end

---整块只写底色（与 fill 的分工：fill 连字形一起写）
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param bg phos.Color|nil
function phos.screen.back_rect(x, y, w, h, bg) end

---在**子位**上落一笔：一格 = 2x2 子位（(x, y) 是子格坐标）。
---同一格的多次 plot 合并成一个象限字形，位序由引擎定义（左上 / 右上 / 左下 / 右下）
---@param x integer 子格坐标（0 ~ 宽度*2-1）
---@param y integer 子格坐标（0 ~ 高度*2-1）
---@param fg phos.Color|nil
function phos.screen.plot(x, y, fg) end

---位掩码 → 象限字形（1 左上 / 2 右上 / 4 左下 / 8 右下，0 = 空格、15 = 整格）。
---给"已经算好四个子位"的绘制用（地形、地图）：`put` 一次画完一格，比逐子位 plot 省。
---**位序与字形表只有引擎这一份** —— 卡带自己抄一张，迟早把左上与右上写反
---@param bits integer 0~15
---@return string
function phos.screen.quadrant(bits) end

---子格坐标 → **格坐标 + 子位**（位 1/2/4/8）。一格 = 2x2 子格，
---这一步换算是引擎契约：相机、降水、光柱都用它，各处自己写 `floor(u/2)`
---会让同一屏长出两套网格，差半格就是"看着陷进墙里"
---@param x integer 子格坐标
---@param y integer
---@return integer gx, integer gy, integer bit
function phos.screen.cell_of(x, y) end

---侧栏面板（需在 manifest 声明 sidebar）
---@class phos.panel
phos.panel = {}

---返回面板宽度与屏幕高度；宽度为 0 表示本卡带无侧栏
---@return integer w, integer h
function phos.panel.size() end

---运行时改面板宽度（0 = 收起面板，上限 kPanelMaxW=32）；返回钳制后的实际宽度。
---分隔线与面板局部坐标会立即跟着变（主机只认这一个宽度值）
---@param w integer
---@return integer
function phos.panel.resize(w) end

---一次写多行（每行一条字符串）：面板里的地图/表格搬运用。与 screen.blit 同组：
---**恒写底色**（省略 = 黑），不能靠省略 bg 来透出底图
---@param x integer
---@param y integer
---@param rows string[]
---@param fg phos.Color|nil
---@param bg phos.Color|nil
function phos.panel.blit(x, y, rows, fg, bg) end

---在同一格追加一笔（叠加）；返回 false = 越界或这一格已叠满（3 笔）
---@param x integer 面板局部坐标
---@param y integer
---@param ch string|integer 字符（也可给**码点**整数）
---@param fg phos.Color|nil
---@return boolean ok
function phos.panel.blend(x, y, ch, fg) end

---只写底色：字形与已叠的笔迹都不动
---@param x integer 面板局部坐标
---@param y integer
---@param bg phos.Color|nil 省略 = 黑
function phos.panel.back(x, y, bg) end

---整块只写底色
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param bg phos.Color|nil
function phos.panel.back_rect(x, y, w, h, bg) end

---子格落笔（(x, y) 是子格坐标：一格 = 2x2 子位）
---@param x integer
---@param y integer
---@param fg phos.Color|nil
function phos.panel.plot(x, y, fg) end

---写一个字符（越界裁到面板内；省略 bg = 保留该格原有背景）
---@param x integer 面板局部坐标
---@param y integer
---@param ch string|integer 字符（也可给**码点**整数）
---@param fg phos.Color|nil
---@param bg phos.Color|nil
---@param scale integer|nil 字号倍数：>=2 时是大字号（占 scale 列 x scale 行），上限 3；省略=1
function phos.panel.put(x, y, ch, fg, bg, scale) end

---写一行文本（超出面板宽度的部分按显示宽度截断；省略 bg = 保留该格原有背景）
---@param x integer
---@param y integer
---@param text string
---@param fg phos.Color|nil
---@param bg phos.Color|nil
---@param scale integer|nil 字号倍数（>=2 时每个字占 scale 列 x scale 行，逐字前进）
function phos.panel.print(x, y, text, fg, bg, scale) end

---填充矩形（省略 bg = 主题面板色 skin.panel）
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param ch string|integer 字符（也可给**码点**整数）
---@param fg phos.Color|nil
---@param bg phos.Color|nil
function phos.panel.fill(x, y, w, h, ch, fg, bg) end

---只清空面板区（省略 bg = 主题面板色 skin.panel）
---@param fg phos.Color|nil
---@param bg phos.Color|nil
function phos.panel.clear(fg, bg) end

---组件层：边框/浮窗/菜单/进度条/正文/精灵/导航（与系统界面同一套原语）
---@class phos.ui
phos.ui = {}

---带标题的边框（标题嵌在上边框；空标题为普通边框）
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param title string|nil
function phos.ui.frame(x, y, w, h, title) end

---居中浮窗；返回布局表，内容由卡带自己画
---@param w integer
---@param h integer
---@param title string|nil
---@return table {x=integer, y=integer, w=integer, h=integer}
function phos.ui.modal(w, h, title) end

---分隔线
---@param x integer
---@param y integer
---@param w integer
function phos.ui.divider(x, y, w) end

---垂直列表菜单（'>' 光标 + 高亮；h 省略时为条目数）
---@param x integer
---@param y integer
---@param w integer
---@param items string[]
---@param selected integer 0-based
---@param h integer|nil
function phos.ui.menu(x, y, w, items, selected, h) end

---百分比进度条
---@param x integer
---@param y integer
---@param w integer
---@param ratio number 0~1
function phos.ui.bar(x, y, w, ratio) end

---自动折行正文
---@param x integer
---@param y integer
---@param w integer
---@param body string
---@param max_lines integer|nil
function phos.ui.text(x, y, w, body, max_lines) end

---居中的单行文本
---@param y integer
---@param text string
function phos.ui.center_text(y, text) end

---像素精灵：rows 为字符画，colors 为 字符→颜色 映射（'.' 与空格透明）
---@param x integer
---@param y integer
---@param rows string[]
---@param colors table<string, phos.Color|integer[]>
---@param step integer|nil 缩放步长（1 = 原尺寸）
function phos.ui.sprite(x, y, rows, colors, step) end

---列表导航：返回新下标（0-based）与动作
---@param count integer
---@param current integer
---@return integer index, string action "none"|"confirm"|"cancel"
function phos.ui.nav(count, current) end

---音频：合成音 / 音符 / 打击乐 / 音序器音乐 / 采样
---@class phos.audio
phos.audio = {}

---@return boolean
function phos.audio.available() end

---主音量（传参即设置，返回当前值）
---@param v number|nil 0~1
---@return number
function phos.audio.volume(v) end

---音乐音量
---@param v number|nil 0~1
---@return number
function phos.audio.music_volume(v) end

---音效音量
---@param v number|nil 0~1
---@return number
function phos.audio.sfx_volume(v) end

---@param pause boolean|nil
---@return boolean
function phos.audio.paused(pause) end

---@class phos.audio.Tone
---@field wave string|nil "sine"|"square"|"triangle"|"saw"|"noise"
---@field freq number|nil 起始频率 Hz
---@field sweep number|nil 扫频终点 Hz
---@field dur number|nil 总时长（秒）
---@field volume number|nil 0~1
---@field attack number|nil
---@field release number|nil

---合成音
---@param freq number Hz
---@param dur number 秒
---@param opts phos.audio.Tone|nil
function phos.audio.beep(freq, dur, opts) end

---单音（音名：C4 / F#3 / Bb2）
---@param note string
---@param opts phos.audio.Tone|nil
function phos.audio.note(note, opts) end

---打击乐
---@param token string "K" 底鼓 | "S" 军鼓 | "H" 踩镲
function phos.audio.perc(token) end

---音序器音乐：单乐段（tracks）或曲式（patterns + order）
---@param tune table
function phos.audio.music(tune) end

function phos.audio.stop_music() end
function phos.audio.stop_all() end

---加载卡带包内音频文件（wav/mp3/flac），返回句柄（0 = 失败）
---@param path string 例如 "assets/hit.wav"
---@return integer
function phos.audio.sample(path) end

---@param handle integer
---@param opts table|nil { volume = number, loop = boolean }
function phos.audio.play_sample(handle, opts) end

---@param handle integer
function phos.audio.stop_sample(handle) end

---输入：虚拟手柄抽象
---@class phos.input
phos.input = {}

---@param key string "left"|"right"|"up"|"down"|"a"|"b"|"x"|"y"|"start"|"select"|"space"|"comma"|"period"
---@return boolean
function phos.input.down(key) end

---本逻辑帧刚按下
---@param key string
---@return boolean
function phos.input.pressed(key) end

---本逻辑帧刚松开
---@param key string
---@return boolean
function phos.input.released(key) end

---该按键在键盘上的**主键名**（"A"/"B"/"X"/"Y"/"ENTER"/"SHIFT"/"LEFT"…）
---用它写操作提示，提示才与实际能按的键一致（主机没有手柄）：
---  panel.print(1, 3, phos.input.key_name("a") .. " JUMP")
---@param key string
---@return string
function phos.input.key_name(key) end

---该键已按住的秒数（松开或没按过 = 0）。按逻辑帧累计。
---"按住越走越快"这类手感用它，不必自己攒计时
---@param key string
---@return number
function phos.input.duration(key) end

---本帧新按下的键（任意一个），返回虚拟键名或 nil。
---给"让玩家按一个键来完成绑定"用：拿到键名可以存进 phos.save，
---再用 phos.input.key_name() 显示成键盘上真实的键。
---主机保留键（Esc / F2）不在其中——它们永远属于主机。
---@return string|nil
function phos.input.any_pressed() end

---主机见过的所有键名（内置十颗在最前）。写"按任意键改绑定"这类界面时遍历它
---@return string[]
function phos.input.keys() end

---本帧输入的文本（UTF-8，无输入时为空串）
---语义是"本帧"：每帧清空，所以在 update 里读到的就是这一帧新敲的字符。
---可含中文等多字节字符；退格以 '\b'（U+0008）送达，需自行处理。
---  local s = phos.input.text()
---  while #s > 0 do                      -- 按码点切，不能按字节切
---    local ch = utf8.char(utf8.codepoint(s))
---    s = s:sub(#ch + 1)
---    if ch == "\b" then name = name:sub(1, -2) else name = name .. ch end
---  end
---@return string
function phos.input.text() end

---创建一个**文本输入框缓冲**：过滤、按码点退格、限长都在主机侧完成
---（与主机界面的磁带码输入是同一套实现），卡带只管每帧 feed() 一次、然后读 value。
---用于命名 / 密码 / 输入磁带码等长按输入场景，比自己拼字符串稳。
---@param cfg table|nil filter = "any"|"printable"|"ascii"|"digits"|"hex"|"letters"|function(cp)->bool；max = 码点数上限（0=不限）；ime = true 才收中文（默认关；仅 Windows）
---@return phos.TextField
function phos.input.field(cfg) end

---文本输入框（由 phos.input.field 创建）。usertype：注解不配 `= {}`，
---与 phos.Color / phos.audio.Tone 同一套写法（--check-api 因此不校验其成员）。
---@class phos.TextField
---@field value string 当前文本（UTF-8，永远是完整的码点序列）
---@field count integer 已录入的**码点**数（中文与半角同样算 1）
---@field feed fun(self: phos.TextField) 消费"本帧"输入（每帧一次；同一帧重复调用幂等）
---@field clear fun(self: phos.TextField) 清空缓冲

---可选图层：世界照旧写底层（phos.screen），这里只声明"叠在它上面的缓冲"。
---不调用 create 的卡带完全不受影响 —— 主机连一次合成都不会做，
---既有实现也不需要改写成"分层"的写法
---@class phos.layer
phos.layer = {}

---建层（重名幂等：同名再取一次还是那层）。z 越大越靠上；层数有上限（6），超出报错
---@param name string 层名（只在本卡带内有意义）
---@param opts table|nil { z = integer }（缺省 0；z 越大越靠上）
---@return phos.Layer
function phos.layer.create(name, opts) end

---层序（z 升序，同 z 保持注册先后）→ 名字数组
---@return string[]
function phos.layer.order() end

---注销一层。之后写到它的绘制区域会回落到内容区，并留一次日志
---@param name string
---@return boolean
function phos.layer.remove(name) end

---图层句柄（由 phos.layer.create 返回）。usertype：注解不配 `= {}`，
---与 phos.TextField 同一套写法（--check-api 因此不校验其成员）
---@class phos.Layer
---@field name string 层名
---@field visible boolean 整层显隐（不可见的层在合成时跳过）
---@field z integer 层序（越大越靠上）
---@field clear fun(self: phos.Layer) 整层清成透明：上层每帧"从空开始"的写法

---创建一个**绘制区域**：带裁剪的矩形，坐标一律相对区域左上角，越界不画。
---两种用法同源：
---  * **非浮动分区**：侧栏某块放小地图、游戏区某块放状态条
---  * **浮动窗口**：卡带自己的设置/暂停/背包面板
---本机每帧清屏、卡带每帧重画，所以**层级就是调用顺序**：先画底图、再画窗口；
---窗口关闭时不再画它，底图自然就在。
---构造时会与表层可用范围求交，所以 x/y/w/h 字段给的就是实际可画范围。
---  local map = phos.ui.region(0, 0, 20, 10, { surface = "panel" })
---  local win = phos.ui.region(20, 5, 40, 12)   -- 画面中间
---@param x integer
---@param y integer
---@param w integer
---@param h integer
---@param opts table|nil surface = "screen"（默认，内容区）| "panel"（侧栏面板）；layer = 层名（锚定到该图层，坐标原点仍是内容区左上角）
---@return phos.Region
function phos.ui.region(x, y, w, h, opts) end

---@class phos.Region
---@field x integer 实际左上角 x（已与表层求交）
---@field y integer 实际左上角 y
---@field w integer 实际宽度
---@field h integer 实际高度
---@field surface string 锚定面："screen"（内容区）/ "panel"（侧栏）/ 层名
---@field clear fun(self: phos.Region, fg: phos.Color|nil, bg: phos.Color|nil) 省略 bg = 保留该格原有背景
---@field put fun(self: phos.Region, x: integer, y: integer, ch: any, fg: phos.Color|nil, bg: phos.Color|nil, scale: integer|nil) 省略 bg = 保留该格原有背景；scale>=2 = 大字号
---@field print fun(self: phos.Region, x: integer, y: integer, text: string, fg: phos.Color|nil, bg: phos.Color|nil, scale: integer|nil) 省略 bg = 保留该格原有背景；scale>=2 = 大字号
---@field fill fun(self: phos.Region, x: integer, y: integer, w: integer, h: integer, ch: any, fg: phos.Color|nil, bg: phos.Color|nil) 省略 bg = 保留该格原有背景
---@field blit fun(self: phos.Region, x: integer, y: integer, rows: string[], fg: phos.Color|nil, bg: phos.Color|nil) 一次写多行；省略 bg = 保留该格原有背景
---@field blend fun(self: phos.Region, x: integer, y: integer, ch: any, fg: phos.Color|nil) 同一格追加一笔（叠加）；返回是否画上
---@field back fun(self: phos.Region, x: integer, y: integer, bg: phos.Color|nil) 只写底色：字形与已叠的笔迹都不动
---@field back_rect fun(self: phos.Region, x: integer, y: integer, w: integer, h: integer, bg: phos.Color|nil) 整块只写底色
---@field plot fun(self: phos.Region, x: integer, y: integer, fg: phos.Color|nil) 子格落笔（坐标是子格：一格 = 2x2）
---@field frame fun(self: phos.Region, title: string|nil)
---@field divider fun(self: phos.Region, y: integer)
---@field bar fun(self: phos.Region, x: integer, y: integer, w: integer, ratio: number)
---@field menu fun(self: phos.Region, x: integer, y: integer, w: integer, items: string[], selected: integer, h: integer|nil)
---@field body fun(self: phos.Region, x: integer, y: integer, w: integer, text: string, max_lines: integer|nil)
---@field sprite fun(self: phos.Region, x: integer, y: integer, rows: string[], colors: table, step: integer|nil)

---文本度量：全角字符（CJK 等）占两格，排版请用它而不是 #str（那是字节数）
---@class phos.text
phos.text = {}

---字符串的显示宽度（列数；全角字符算 2，控制字符算 0）
---@param text string
---@return integer
function phos.text.width(text) end

---字形在**格内**的墨迹框（像素，相对格左缘）。字体是比例字体，墨迹通常比一整格窄 ——
---要"底板/装饰贴住字身"就得按它算，而不是按整格猜。
---拿不到字体度量时（无头运行、字体未就绪）返回整格宽并置 approx = true
---@param ch string
---@return integer xoff, integer width, boolean approx
function phos.text.ink_box(ch) end

---按显示宽度截断，绝不切出半个全角字符
---@param text string
---@param columns integer
---@return string
function phos.text.truncate(text, columns) end

---定宽裁剪：超宽时截断并补省略号（"…"），没超就原样返回。
---侧栏、状态条这类**位置固定**的文案都用它——主机在右侧是硬切，
---会留下"[↑/A] 跳：按住更"这种半句话，玩家只能猜
---@param text string
---@param columns integer
---@return string
function phos.text.fit(text, columns) end

---按显示宽度**右补空格**（不足才补，超了原样返回）。定宽排版的对齐用它，
---不要用 string.format 的 %-Ns：那个按字节数补，"队友交给 AI" 这类中英混排会整列歪
---@param text string
---@param columns integer
---@return string
function phos.text.pad(text, columns) end

---按显示宽度**左补空格**（数字/取值右对齐时用）
---@param text string
---@param columns integer
---@return string
function phos.text.pad_left(text, columns) end

---多语言取值：文案属于卡带内容（主机不替卡带翻译），这里只提供"取当前语言那一条"
---的机制。缺项一律回落中文，卡带不必为漏翻写防御代码。
---@class phos.lang
phos.lang = {}

---从 `{ zh = "普通炮弹", en = "SHELL" }` 里取当前语言那一条；缺项回落中文
---@param fields table zh / en 两条
---@return string
function phos.lang.pick(fields) end

---从 `{ zh = {…}, en = {…} }` 里取当前语言的**那张表**（返回引用，不拷贝）。
---用法：`local Text = { zh = {...}, en = {...} }`，每帧 `local t = phos.lang.dict(Text)` ——
---每帧取一次就能跟着设置里的语言切换即时变，不必自己缓存
---@param fields table zh / en 两张表
---@return table
function phos.lang.dict(fields) end

---包内资源读取（路径相对包根；覆盖层 Mod 生效时读到替换后的内容）
---@class phos.assets
phos.assets = {}

---读取文本资源全文；不存在返回 nil
---@param path string 例如 "assets/map.txt"
---@return string|nil
function phos.assets.text(path) end

---按行读取（1 基数组；保留空行与行首空格）；不存在返回 nil
---@param path string
---@return string[]|nil
function phos.assets.rows(path) end

---@param path string
---@return boolean
function phos.assets.exists(path) end

---@param path string
---@return integer 字节数（不存在返回 0）
function phos.assets.size(path) end

---列出包内文件（可按前缀过滤，如 "assets/"）
---@param prefix string|nil
---@return string[]
function phos.assets.list(prefix) end

---存档（需 manifest 声明 save = true）
---@class phos.save
phos.save = {}

---@return boolean
function phos.save.available() end

---@param key string 长度 ≤64
---@param value string 长度 ≤4096
---@return boolean
function phos.save.write(key, value) end

---@param key string
---@return string|nil
function phos.save.read(key) end

---删除键
---@param key string
---@return boolean 是否写入成功
function phos.save.erase(key) end

---导出为可复制的磁带码文本
---@return string
function phos.save.export() end

---从磁带码恢复（整份替换现有存档）；码非法时不做改动并返回 false
---@param code string
---@return boolean
function phos.save.import(code) end

---系统信息与工具
---@class phos.sys
phos.sys = {}

---卡带运行秒数
---@return number
function phos.sys.time() end

---当前实际画面帧率（逻辑帧率恒为 60；逻辑帧号见 phos.sys.frame）
---@return integer
function phos.sys.fps() end

---当前逻辑帧号（与 state.query 的 frame 同源）："每 N 帧做一次"不必自己数
---@return integer
function phos.sys.frame() end

---确定性随机整数 [lo, hi]
---@param lo integer
---@param hi integer
---@return integer
function phos.sys.random(lo, hi) end

---重设随机种子
---@param seed integer
function phos.sys.seed(seed) end

---写主机日志（开发期利器）
---@param message string
function phos.sys.log(message) end

---主机版本（唯一权威，形如 x.y.z）
---@return string
function phos.sys.version() end

---产品名（"PHOSPHOR"）
---@return string
function phos.sys.product() end

---当前界面语言（"zh" 或 "en"）。卡带文案属于卡带自己，按它选一套文案即可；
---每帧读取可让文案跟着设置里的切换即时变化
---@return string
function phos.sys.language() end

---卡带接管 Esc：true 时主机不再把 Esc 当"暂停/返回"，而是把它当**普通键**交给卡带
---（用 phos.input.pressed("escape") 读）。默认 false（Esc 仍是主机保留键）。
---典型用途：联机对局**不能暂停**，卡带要自己用 Esc 弹一个"非暂停"的浮层
---@param on boolean
---@return boolean 生效后的值
function phos.sys.capture_escape(on) end

---卡带自己的身份（取自 manifest.lua）
---@class phos.CartInfo
---@field id string 卡带 id
---@field name string 卡带架与侧栏显示的标题
---@field version string 作者自己的版本号（与主机版本无关）
---@field author string 作者
---@field desc string 简介（按当前界面语言取；英文缺失时回落中文）

---@class phos.cart
phos.cart = {}

---当前卡带的身份。标题画面 / 关于页用它，别在 Lua 里再抄一份字符串——
---那样改了 manifest 就会留下对不上的旧文案。
---每次调用都会建一张新表，取一次存起来即可；未插卡（主机脚本）时各项为空串
---@return phos.CartInfo
function phos.cart.info() end

-- ─────────────────────────────────────────────────────────────────────────
-- phos.debug —— 把可调参数交给 `~` 调试台做实时微调
--
-- 写玩法时常数满屏（移动速度、生命值、武器参数……）。把它们注册进"篮子"，
-- 就能在**运行中**用 `~` 面板拖滑条实时改，不必反复改代码重启。
-- get 读当前值、set 写回；都是卡带自己的函数，于是嵌套数据（如 weapons[i].radius）
-- 也照样能调。注册随卡带生命周期，拔卡即清；未插卡时安全无效。
-- ─────────────────────────────────────────────────────────────────────────

---@class phos.debug
phos.debug = {}

---注册一个可实时调的**数值**参数。
---@param name string|table 面板上显示的名字；写 `{ zh = …, en = … }` 可随界面语言切换（只写一种也认）
---@param get fun():number 读当前值（面板打开或 state.query 时被调用——不必每帧执行）
---@param set fun(value:number) 写回
---@param opts table|nil min / max（滑条范围）、step（拖动步长）、
---       group = 折叠分组：字符串或 `{ zh =, en = }`（单层），或数组（多层，每项又是标签）。
---       分组在面板里是**默认关闭**的折叠节点，将来新增的组 / 参数自动出现
function phos.debug.number(name, get, set, opts) end

---注册一个可实时调的**整数**参数（滑条取整——弹药数 / 弹丸数之类）。
---参数形状与 phos.debug.number 相同；min / max / step 按整数给（如 1 / 20 / 1）
function phos.debug.integer(name, get, set, opts) end

---注册一个可实时调的**布尔**参数（复选框）。
---@param name string|table 同上
---@param get fun():boolean 读当前值
---@param set fun(value:boolean) 写回
function phos.debug.toggle(name, get, set) end

-- ─────────────────────────────────────────────────────────────────────────
-- phos.net —— 局域网联机（第四代接口）
--
-- 只做**传输**：开房 / 加入 / 收发消息 / 局域网发现。同步模型（锁步 / 行动中继 /
-- 主机权威）由卡带自己在 send / poll 上实现。见 design/networking.md。
-- 未调用 host / join 时完全休眠（不占端口、不起线程）。
-- ─────────────────────────────────────────────────────────────────────────

---@class phos.net
phos.net = {}

---开房（主机）。opts 可省，字段：port(默认 7770)、name、max_peers(默认 8)、
---discovery_port(默认 45454)、discoverable(默认 true)。成功返回 true
---@param opts? table
---@return boolean
function phos.net.host(opts) end

---加入主机。address 是主机 IP；opts 字段：port(默认 7770)、name。成功返回 true
---@param address string
---@param opts? table
---@return boolean
function phos.net.join(address, opts) end

---离开 / 关房（可重复调用）
function phos.net.stop() end

---状态："off" | "hosting" | "connecting" | "connected" | "error"
---@return string
function phos.net.status() end

---最近一次错误串（无则 ""）
---@return string
function phos.net.error() end

---角色："none" | "host" | "client"
---@return string
function phos.net.role() end

---自己的对端 id（未联机 0）
---@return integer
function phos.net.self_id() end

---主机对端 id（未联机 0）
---@return integer
function phos.net.host_id() end

---游戏 TCP 端口（未联机 0）
---@return integer
function phos.net.port() end

---本机在局域网里的 IPv4 地址（提示用）
---@return string
function phos.net.local_ip() end

---是否已连上（主机 = 已开房；客人 = 已连上主机）
---@return boolean
function phos.net.connected() end

---对端列表（不含自己）：{ { id, name, address, rtt_ms }, ... }
---@return table
function phos.net.peers() end

---发给对端 to（0 = 广播给其他所有人）。data 是可 JSON 化的 Lua 表（可省）
---@param to integer
---@param kind string
---@param data? table
---@return boolean
function phos.net.send(to, kind, data) end

---等价 send(0, kind, data)：广播给其他所有人
---@param kind string
---@param data? table
---@return boolean
function phos.net.broadcast(kind, data) end

---取本帧收到的消息：{ { from, kind, data }, ... }（每次调用清空）
---@return table
function phos.net.poll() end

---取连接变化事件：{ { type = "connected"|"disconnected", peer, name }, ... }（每次调用清空）
---@return table
function phos.net.events() end

---广播查询并收集应答（有界阻塞，默认 0.5 秒）：
---{ { name, address, port, players, open }, ... }（open = 房主是否还接受加入）
---@param seconds? number
---@return table
function phos.net.discover(seconds) end

---更新房间对外广播的信息（供局域网发现应答）：主机开局后 set_room({ open = false })，
---搜索方就会在列表里看到"游戏中"并据此拒绝加入
---@param opts table { name? = string, open? = boolean }
function phos.net.set_room(opts) end

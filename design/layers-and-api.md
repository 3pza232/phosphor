# PHOSPHOR 未来功能设计：可选图层与 API 扩展

> 定位：后续开发的**技术蓝图**。所有"现状"陈述都以当前代码为准并标注文件，
> 可用 `grep` 逐条核查；所有"设计"决策都给出理由与回退路径。
> 读者：实现者与评审者。先读 §1（事实），再读 §3、§4（设计），施工看 §5。

> **最高原则：纯增量。**
> 分层是**可选的新能力**——将来的新卡带需要时拿得出手；不需要时，
> 现有程序、既有界面、全部出厂卡带的**代码路径与今天完全一致**。
> 不用分层的地方**不**用分层 API 重写，既有实现**不**做分层化重构。

---

## 0. 范围

两个方向，共用一条主线——**把"分层"做成一件卡带想用就能取用的新工具**：

1. **可选图层**：图层结构、渲染顺序、交互逻辑、性能考量（§3）。
2. **更丰富的 API**：接口设计、能力边界、调用方式、兼容性规划（§4）。

非目标（本文不设计，且在 §4.8 列为"明确不做"）：逐像素绘制、逐格半透明、
输入按层路由、富文本导出、以及**对既有实现的分层化重构**。

---

## 1. 现状盘点（可核查事实）

### 1.1 画面模型：单张网格，整格覆盖

- 画面是 `Screen`：一个字符网格（内容区 80×45，`core/screen.hpp`）。
  每格 `Cell{ ch, fg, bg, cols }`——**一格只有一个底色**；后写的整格覆盖先写的。
  不存在"这格底下是什么"，所以"浮层透出战况""背景比一格窄"在模型里做不出来。
- 全角字符占两格（头格 `cols=2` + 续格 `cols=0`），宽字符规则的唯一一份实现
  在 `Screen::put`（`core/screen.cpp`）。
- 唯一的"透明"语义是 `Color.keep`（`core/color.hpp`）：背景带 keep 时
  **解析为该格原有底色**，解析点全屏唯一（`Screen::put`）。
  Lua 侧"省略 bg"就是它（`api/lua_value.cpp` 的 `read_background`）。
- 写入一律经过 `Surface`（`core/surface.hpp`）：内容区、侧栏面板、卡带绘制区域
  都是它的实例——越界裁剪、透明底、宽字符占格**只有一份规则**。
  Lua 侧的"绘制区域"是 `DrawRegion`（`api/draw_region.hpp`），
  其注释明说：**"每帧清屏、卡带每帧重画，所以层级就是调用顺序"**。

### 1.2 合成顺序（`core/app.cpp` 逐帧的真实流程）

```
tick_playing:
  shell_.draw_chassis(screen_)      ← 机身装饰（内容区之外）
  cart_->update(dt) / cart_->draw() ← 卡带内容（世界/角色/特效/HUD 全靠作者按序重画）
  effects::draw_insert_flash(...)   ← 主机特效（插卡电压闪）
  侧栏分隔线（主机绘制）
渲染:
  renderer.draw(screen_)            ← 窗口 GL（每格：底色四边形 + 字形四边形）
  CRT 后处理（着色器内）
```

`effects::draw_eject_collapse`（拔卡收缩）与调试台、磁带码等同理：全是**画进同一张
Screen 的不同调用者**。无头模式下 `Screen::to_text()` 是唯一消费者；
截图走 `render/screen_image.cpp`（与窗口同一套格级语义）。

### 1.3 API 与版本机制

- 卡带 API 通过**开放注册表**装配（`api/host_api.cpp` + 各 `api/*_api.cpp`）：
  `phos.screen / color / text / audio / ui / panel / ui.region / input / save /
  assets / cart / sys / lang`。
- 版本门控真实存在：`core/version.hpp` 的 `kPhosApiVersion`；`manifest.lua` 声明 `phos_api`
  高于它即在 `cart/cartridge.cpp` 被拒绝加载，报错里写明两个具体版本号。
  当前世代 **2**（1 = 基础接口；2 = 图层与新的观测面）。
- 一致性门禁：`--check-api` 比对 DevKit 注解与实装；控制通道契约由
  `tools/control_test.py` 守；画面行为由 `tools/window_smoke.py` /
  `tools/cart_smoke.py` 守。

### 1.4 痛点（全部来自仓库里真实发生过的事）

| # | 现象 | 根因 | 当时的绕法 |
|---|------|------|-----------|
| P1 | 单格底板总比字身宽一格（`@`、`^` 右侧多一截） | 背景粒度 = 一格 | 干脆不垫底板（省略 bg） |
| P2 | K 浮板边框透明、必须先整块铺底再画框 | 同格后写覆盖先写，没有"底下一层" | `fill(w×h)` 再画框 |
| P3 | 瞄准线钻进地形就消失 | 同格覆盖 | 换字形（`+`/`·`）提示"在土里" |
| P4 | agent 想要"只看世界、不要 HUD" | 只有一张合并好的网格 | 拿不到，只能读合并结果 |

P1~P3 的共同点是：**分层这件事目前靠卡带作者按序重画来自律**。
注意：这些痛点**已被各自的绕法解决**，本文的方案**不是**为了回去修它们，
而是让**将来的新卡带**遇到同类需求时手里有一件正式工具。

---

## 2. 设计目标与非目标

**目标**

- G1：将来的卡带能声明"世界照旧画、HUD/浮窗画在叠加层上"，**顶层不用知道
  底下画了什么**，透明处自然透出下层。
- G2：合并语义**唯一且可逐字断言**：窗口、离屏截图、无头文本、控制通道
  读到的是同一份合成结果。
- G3：**零回归**：不取用新 API 的卡带（包括全部出厂卡带）输出逐字节不变。
- G4：API 扩展按"默认不变、显式取用"进库，版本与文档、门禁同批落地。
- **G5：纯增量**。不创建层的卡带、主机既有界面（开机/卡带架/设置/暂停/
  磁带码/调试台），**代码路径与今天完全一致**——不是"输出等价"，
  是**结构性零改动**；既有实现不做分层化重构。

**非目标（本文明确排除，理由见 §4.8）**

- 逐像素绘制与半格背景（与"格"的粒度冲突）。
- 逐格半透明（alpha 是布尔语义，字节仅作预留；变暗用抖动，见 §3.3 末）。
- 输入按层路由 / 命中测试（输入是全局命名键，焦点归卡带，§3.5）。
- 跨卡带共享层（沙箱边界不变）。
- **对既有代码的分层化改造**（§3.1 的方案 A1 因此被否决）。

---

## 3. 可选图层

### 3.1 方案比选

| 方案 | 内容 | 判断 |
|------|------|------|
| A1 | 内容区整体改为"全局层栈"：今天的 Screen 变成 world 层、主机特效进 system 层 | ✗ 否决：违反 G5——这是对既有合成流程的重构，即使用了快路径，结构也已改动 |
| A2 | **卡带级层缓冲 + 可选合并**：层随卡带创建而存在，合并是一个"有层才执行"的新增步骤 | ✅ 选这个 |
| B | `Cell` 改为"格内小层栈" | ✗ 一格一个栈：合并语义散到每格，写入、文本导出、调试全变复杂 |
| C | 引入全局 alpha 混合 | ✗ 与"格"的气质冲突；§4.8 列为明确不做 |

选 A2 的硬理由（每条可核查）：

1. **不用就是零成本**。卡带不调用 `phos.layer.create`，主循环里连一次
   合并都不发生（仅多一次布尔判断）——G5 由此成立。
2. **渲染器零改动**。合并产出的还是今天那张 `Screen`，
   `render/renderer.cpp` 与 `render/screen_image.cpp` 不动。
3. **旧写入路径零改动**。`phos.screen` / `phos.panel` / `ui.region`（不带 layer）
   照旧写今天那张网格；`keep` 语义、裁剪规则、`Surface` 一字不改。
4. **心智与现状一致**。"每帧重画"不变：建了层的卡带，每层仍每帧重画，
   变的只是"这几块缓冲最后叠上去"。

### 3.2 图层结构

新单元 `core/layered_screen.hpp/.cpp`（归属 core 层：不依赖 sol / GL，见
`design/architecture.md` 的依赖铁律）。**它归卡带所有**——挂在卡带的宿主上下文上，
随插卡创建、随拔卡销毁：

```cpp
struct Layer {
    std::string name;
    int z = 0;            // 越大越靠上；同 z 按注册先后
    bool visible = true;
    bool dirty = true;    // 任何写入置脏；合并后清
    Screen cells;         // 80×45，与内容区同构
};

class LayeredScreen {
public:
    static constexpr int kMaxLayers = 6;   // 卡带自定义层的上限（不含底层）
    bool active() const { return !layers_.empty(); }
    Layer& create(const std::string& name, int z);
    Layer* find(const std::string& name);
    /// 把所有可见层按 z 叠到 target 的内容区（target = 今天的 screen_）。
    /// 只在 active() 且有脏层时被调用；什么都不画时直接返回
    bool merge_over(Screen& target);
};
```

- **没有 world 层 / system 层的概念**：今天的 `screen_` 就是底层，语义不变；
  层只描述"**叠在底层之上**的那几块缓冲"。
- 上层的初始状态是**全透明**（见 §3.3 的 alpha 语义）。
- 侧栏面板（`phos.panel`）**不进这个体系**：它是"机身的一部分"，保持主机直属区域。
- 机身装饰（`draw_chassis`）与主机特效（插卡电压闪、拔卡收缩、调试台、
  暂停菜单、磁带码）**一律保持现状**：照旧直接写 `screen_`，不碰层。
- 层**不跨卡带持久**：换卡带即销毁（与卡带沙箱同生命周期）。
- **层每帧由主机清成透明**（实现时定下）：与底层"每帧重画"同一心智，
  于是"这帧不再画它 = 它消失"，不会在层里留下上一帧的残影。这一步在卡带绘制**之前**做，
  没建层的卡带只是一次判断。

### 3.3 合并规则（语义的唯一来源）

`Cell` 增加一个字段：

```cpp
struct Cell {
    char32_t ch; Color fg; Color bg;
    uint8_t cols;
    uint8_t alpha = 255;   // 0 = 该格不存在（透明）；非 0 = 存在（布尔语义）
};
```

- **alpha 是布尔语义**：`0` = 透明（整格跳过，字形与底色都不参与）；
  非 0 = 存在（整格覆盖下层）。**不做逐格半透明**——字节仅为未来预留，
  v1 读写只允许 0 或 255（写入时把非零一律归一成 255，防"以为能半透"的误用）。
- 合并（只有脏层参与）：

```
for layer in 卡带层按 z 升序:
    if not layer.visible: continue
    for each cell (x, y):
        if layer.cells[y][x].alpha != 0:
            target[y][x] = layer.cells[y][x]      # 整格覆盖：ch + fg + bg 一并取
```

- **一格有两个槽**（实现时定下的精化，api-reference 同步了）：**底色槽**由 `alpha`
  决定存不存在，**字形槽**由"这一格写没写过字"决定。于是三种写法各自成立：
  只写字形（`print` 省略 `bg`）= 字压在下层底上；给了底色 = 底色覆盖且字形槽以这一层
  为准（写空格就是抹掉下层字形）；没写到 = 整格透传。
- **`keep` 的解析域 = 写入目标那张网格**：旧 API 写 `screen_`，keep 照旧解析为
  `screen_` 该格原有底色（行为与今天完全一致）；写某层的 region 里带 keep，
  解析为**该层**该格原有底色——"保留底色"从不跨网格，跨层的"透下去"只能靠"没写到"。
- 半透效果（弹窗压暗世界）的地道做法：**棋盘格抖屏**——在 overlay 层按
  `(x + y) % 2 == 0` 铺深色格、其余留透明。这是字符机上的惯用手法，
  api-reference 给出三行 recipe，而不是引入半透明。

### 3.4 渲染顺序

与 §1.2 的现有顺序**逐项相同**，只在卡带 draw 之后插入一个**可选**步骤：

```
shell_.draw_chassis(screen_)          机身装饰（照旧，不进任何层）
cart_->update / cart_->draw()         卡带内容（照旧写 screen_）
[ 若该卡带建过层 ]  layers.merge_over(screen_)   ← 唯一新增步骤
effects::draw_insert_flash(...)       主机特效（照旧）
侧栏分隔线（主机，照旧）
调试台 / 暂停 / 磁带码（照旧，最上）
renderer.draw(screen_)                照旧
```

- 合并时机：**该逻辑帧的 `cart_->draw()` 之后**；无层时这一步不存在
  （`active()` 为 false，直接跳过）。
- 无头模式：建了层时，`to_text()` 与 `screen.read` 读**合并后**的屏幕；
  离屏截图同。未建层时与今天逐字节一致（§3.7、§7）。
- **单层读取只覆盖卡带自己的层**：`screen.read(layer = <层名>)` 读那块层缓冲；
  **底层没有单独的读法**——世界与合并结果本来就是同一张网格（合并是就地写入）。
  "只想看世界"的正当途径是让层隐起来（`layers` 里可见可见性，或卡带自己给开关）。

### 3.5 交互逻辑

- **输入与层无关，保持现状**：`core/input.hpp` 是全局命名键的汇流，
  卡带读不到主机保留键（escape/settings），agent 与玩家按键语义必然一致
  （`InputAction` 是唯一注入通道）。
- **不做命中测试与按层路由**：哪个浮窗拥有焦点是**卡带自己的状态**，
  与今天 `phos.ui.region` 的窗口相同——层只解决"画在哪"，不解决"键给谁"。
  这条边界写进 §4.8，防止未来有人把 UI 框架的责任塞进层栈。
- `phos.ui.region(x, y, w, h, { layer = "hud" })`：区域锚定到某层（§4.3）。
  区域依旧是"带裁剪的矩形"，层的差别只是 Surface 指向的网格不同。
- 控制通道（agent 交互面）：
  - `screen.read` 默认返回**合并后**文本（与今天一致）；卡带建过层时，
    新增可选参数 `layer = <name>` 返回单层——P4 痛点由此消解。
  - `input.inject` / `time.step` 不变；单步语义不受层数影响。

### 3.6 性能考量

**内存账**（可核查）：`Cell` 现约 13B（ch 4 + fg 3+1 + bg 3+1 + cols 1），
加 alpha 后按 16B 对齐；80×45 = 3600 格 → 每层 ≈ 57.6KB；6 层 ≈ 0.35MB。
不触发任何分配策略变化（层在 create 时一次分配）。

**合并账**：每帧每格一次 alpha 判断，3.6k × 6 ≈ 22k 次整数比较，量级为微秒；
实装是每帧线性遍历全部可见层（**没有**脏层标记这套机制——层本来就每帧清成透明、
每帧重画，判脏省不下多少，反而多一处状态）。**验收：合并耗时并入 `state.query` 的
顶层字段 `merge_ms`，预算 ≤ 0.3ms**（对照基线：现有 `cart.draw_ms` 通常 < 2ms）。

**无层时的成本 = 一次布尔判断**：`tick_playing` 里 `layers.active()` 为 false
就走今天的路径——不是"快路径等价"，是**根本没有这一步**。

**帧率档联动**：`config.fps` 的节流在主循环（`App::run_windowed`），
与合并无关；验收时实测：建了 6 层的卡带，60 档 `render_fps` 不低于
无层基线的 95%。

### 3.7 兼容性

| 项目 | 承诺 | 验收 |
|------|------|------|
| 不创建层的卡带 | **结构性零改动**：主循环无合并步骤，输出逐字节不变 | 全部出厂卡带对照（§7） |
| 既有界面（开机/架/设置/暂停/磁带码/调试台） | 不触碰，不用层重写 | 门禁全绿 |
| `keep` 语义 | 各网格内解析，行为不变 | 现有卡带不作改动即通过 |
| `to_text` / `screen.read` | 无层时 = 今天的输出；有层时 = 合并结果 | 文本对照 |
| 新能力 | 显式取用（`phos.layer` / `phos_api = 2`） | --check-api |

---

## 4. API 扩展

### 4.1 设计原则（与仓库既有规则同源）

1. **默认行为不变**：新能力是"取用"，不是"变更"；既有调用点不迁移。
2. **单一解析点**：同一份语义只在一个文件落地（keep 的先例：
   `Screen::put` 是全屏唯一解析点）。
3. **注册表装配**：新子表加在 `api/host_api.cpp` 的注册序列里，
   与 `phos.screen` 等同源。
4. **门禁同行**：每个新接口必须同时更新 DevKit 注解（`--check-api`）、
   `docs/api-reference.md`、以及一份冒烟（`tools/` 或卡带内自检）。
5. **Lua 只在 `api/`、`cart/`、`pack/`、`devkit/` 出现**（依赖铁律）：
   新接口的实现不往 core/render 里塞 sol 类型。

### 4.2 `phos.layer`（新增子表）

```lua
local hud = phos.layer.create("hud", { z = 20 })  -- 注册命名层；z 缺省 0
local order = phos.layer.order()                  -- → { "hud", "overlay", ... }（按 z 升序）
hud.visible = false                               -- 整层显隐（合并时跳过）——**字段**，不是方法
hud.z = 30                                        -- 调层序：同样是字段
hud:clear()                                       -- 整层清成透明（这一帧从空开始）
phos.layer.remove("hud")                          -- 注销（写入它的 region 回落底层并留痕）
```

语义边界：
- 层**归当前卡带所有**：插卡时为空、拔卡时销毁；层名只在本卡带内有意义。
- 层名未知时 `region` / 操作一律 **warn + 回落底层**——与 `ui.region` 现有的
  "名字写错按 screen 处理并留痕"同规矩，**绝不静默画错地方**。
- 层不跨帧持久：每帧由卡带重画（与今天一致），`clear()` 只是"这一帧
  从透明开始"的显式写法。

### 4.3 `phos.ui.region` 的 layer 锚点

```lua
local r = phos.ui.region(x, y, w, h, { layer = "hud" })
```

- **不传 `layer` 时与今天完全一致**：照旧写内容区那张网格。
- `opts.layer` 与现有 `opts.surface` 的关系：`surface` 决定内容区还是侧栏面板
  （现状不变）；`layer` 只在内容区这一侧叠加一层。两者都给时以 `layer` 为准
  并留痕一次（防歧义）。
- 区域内一切原语（put/print/fill/blit/frame/body/sprite…）不变，
  只是写入目标换了网格。

### 4.4 `phos.text.ink_box`（字身形框）

```lua
local xoff, w, approx = phos.text.ink_box("@")   -- 墨迹相对格左缘的偏移与宽度（像素）
```

（落地时只提供 `ink_box`：整行墨迹宽可以由它组合出来，多一个接口不如少一个。）

- 动机：P1 痛点的**信息层**解药——将来的卡带要摆底板、摆装饰字时，
  能按字身算宽度，而不是按整格猜。
- 实现路径的依赖处理（重要）：字体度量在 `render/`（`FontChain`，
  `render/font.cpp`），而 `api/` 不许 include `render/`（依赖铁律）。
  做法：core 侧定义一个**度量查询回调**（`using GlyphMetricsFn =
  std::function<GlyphBox(char32_t)>`），渲染器在 `Renderer::init` /
  `reload_fonts` 时装配它并挂到 `HostContext`；api 层只调回调。
  字体未就绪（无头、无窗口）时返回整格宽并注明 `approx = true`。
- 能力边界：返回**像素**而非格；对无字形（空格）返回 0；
  它是"查询"，不改变任何写入语义。

### 4.5 `phos.input` 增补

```lua
phos.input.duration("right")   -- 按住秒数（松开为 0）——"越按越快"类手感不必自攒计时
phos.input.keys()              -- 已登记键名表（写"按任意键改绑定"帮助用）
```

（`phos.input.text()` 与 `phos.input.field()` 早已存在，不在此列。）

- `duration` 的实现：`Input` 增按住计时数组，`set_key` 时记下**内部逻辑帧时钟**
  （不是 `host.time` —— 那个跟着主机时钟走，卡带的手感不该受主机节流影响）；
  读取即两个时刻之差。帧推进语义与 `pressed/released` 同源（`next_frame()` 推进）。
- 边界：这些是**查询**，不引入事件队列、回调或"键被谁消费"的概念（§3.5）。

### 4.6 `phos.sys` 增补（只列缺口，不重复已有）

```lua
phos.sys.frame()   -- 当前逻辑帧号（"每 N 帧一次"不必自己数；控制通道的 frame 同源）
```

已有不重复：`time()` / `fps()` / `random` / `seed` / `log` / `version` /
`product` / `language`（见 api-reference.md §phos.sys）。

### 4.7 控制通道增补（agent 方向）

| 命令 | 变更 | 说明 |
|------|------|------|
| `state.query` | 增 `layers`（名称/z/可见性，仅当卡带建过层）、**顶层** `merge_ms` | 与 `cart.update_ms` 同族的观测 |
| `screen.read` | 增可选参数 `layer` | 默认合并结果（向后兼容） |
| 事件订阅（P3 可选） | `events.subscribe` | 卡带侧 `phos.events.emit/on`；agent 收订阅事件而不必轮询——**标注为可选**，落地与否不影响 §3 主体 |

兼容性：`screen.read` 不加参数时返回合并文本，旧工具（`phos.py`、
`control_test.py`、`agent_shell_demo.py`）零改动通过。

### 4.8 能力边界（明确不做，以及为什么）

| 不做 | 理由（与仓库气质/架构一致） |
|------|----------------------------|
| 逐像素绘制 / 半格背景 | 画面抽象就是字符网格（`Screen`）；开了这个口子，渲染、文本导出、agent 读屏三处全部失真 |
| 逐格半透明 | alpha 布尔语义已覆盖"透/不透"；半透请用棋盘抖屏（§3.3 给了 recipe） |
| 输入按层路由 / 命中测试 | 输入是全局命名键；"键给谁"是卡带自己的状态（§3.5） |
| 富文本导出（含颜色的文本） | 文本通道只承诺字符；颜色与层请用 `screen.read(layer=…)` + `screenshot` |
| 跨卡带共享层 | 沙箱边界：卡带互不可见（`cart/cartridge.cpp` 独立 `lua_State`） |
| Lua 访问任意文件/内存 | 沙箱边界不变；资源走 `phos.assets` |
| **用新 API 重写既有实现** | 纯增量原则（G5）：出厂卡带与既有界面保持现状，示范只用将来的新卡带 |

### 4.9 调用方式（给**将来新卡带**的写法示例）

> 这段示例展示"将来做新游戏、想用分层时怎么用"。
> **任何既有卡带（含全部出厂卡带）不需要、也不应改写成这样**——
> 它们不调用 `phos.layer`，行为与今天完全一致。

```lua
-- init：声明分层（这一步就是"取用"的全部成本）
local hud = phos.layer.create("hud", { z = 20 })
local r_hud = phos.ui.region(0, 0, 80, 45, { layer = "hud" })

-- draw：世界照旧写 phos.screen（= 底层）；HUD 写 hud 层
function draw()
  draw_world()                        -- 地形、角色：照旧落在底层
  r_hud:clear()                       -- 透明重开（上层惯例）
  r_hud:print(2, 2, "HP [=====]", phos.color.cyan)
  -- 浮窗关闭 = 这帧不再画它；底下的世界自然透出，不需要"备份背景"
end
```

对照：这段代码**不**注册层时，写法与今天完全一样——`phos.screen` 就是底层。

### 4.10 兼容性规划

**版本线**：`kPhosApiVersion` 升到 **2**（layers 落地时）；`manifest.lua` 的
`phos_api` 门控沿用现有机制（`cart/cartridge.cpp`：高于主机世代即拒绝，
信息明确）。旧卡带（`phos_api = 1`）在新主机上行为不变。

**特性探测**（让一张卡带同时跑在新旧主机上）：

```lua
if phos.layer then ... else ... end    -- 探的是"这个接口在不在"，不必记版本号
```

- 现在走的是**直接探测接口本身**（`phos.layer` 是 nil 就说明主机没这个接口），
  与 manifest 的 `phos_api = 2` 声明互补：声明管"卡带架就明确拒绝"，
  探测管"同一份代码在新旧主机上都跑得起来"。
- 早先设想的 `phos.has("layer")` **没有实装**（多一层名字到接口的映射表，
  而直接 `if phos.layer` 已经把话说清楚了）。

**弃用政策**（任何 API 变更一律走它）：

| 阶段 | 时长 | 行为 |
|------|------|------|
| warn | ≥ 1 个 minor | 日志提醒（`log::warn`），功能照旧 |
| fallback | ≥ 1 个 minor | 近似行为 + 提醒 |
| remove | 之后 | 移除；`--check-api` 与文档同批更新 |

**兼容矩阵**（维护在 api-reference.md 的版本节，随每次发版更新）：

| 主机世代 | phos_api=1 卡带 | phos_api=2 卡带 |
|----------|-----------------|-----------------|
| v1（0.2.x） | 正常 | 拒绝加载（现有提示） |
| v2（layers 起） | 正常（行为不变） | 正常 |

---

## 5. 落地路径

每阶段**独立可回退**；每阶段收尾跑全部门禁（`control_test` / `window_smoke` /
`cart_smoke` / `agent_shell_demo` / `--check-api` / lint）+ 等价性对照。
**任何阶段都不改写出厂卡带与既有界面。**

**落地状态（本文写作时）**：P0–P4 已按本文实现并全绿——`core/layered_screen`、
`phos.layer`、region 的 layer 锚点、`phos.text.ink_box`、`phos.input.duration` /
`phos.input.keys`、`phos.sys.frame`、`phos_api = 2`，以及控制通道的 `layers` /
`merge_ms` / `screen.read(layer)`。门禁新增 `tools/layer_smoke.py`（含"没建层的卡带
`layers` 为空、`merge_ms == 0`"这条纯增量证据）；可跑的样板见
`package/devkit/examples/layers/`。实现中精化了三处并已回写本文：
一格分**底色槽/字形槽**、层**每帧自动清成透明**、**底层没有单独的读法**。

| 阶段 | 内容 | 涉及文件 | 验收 |
|------|------|----------|------|
| P0 地基 | `Cell.alpha`（默认 255）+ `core/layered_screen`（create/find/merge_over） | `core/screen.hpp`、`core/layered_screen.*`（新） | 单测级：合并结果 == 手工预期；门禁全绿 |
| P1 增量接线 | `tick_playing` 在 `cart_->draw()` 后加**一处** `if (layers.active()) layers.merge_over(screen_)`；层缓冲挂到卡带宿主上下文，随插拔创建/销毁 | `core/app.cpp`（仅此一处）、`core/host_context*`、`cart/cartridge.cpp`（生命周期挂钩） | 无层卡带：反汇编级也能确认无新增行为（结构性零改动）；未建层的出厂卡带逐字节一致 |
| P2 卡带 API | `phos.layer`、`ui.region` 的 layer 锚点、DevKit 注解与模板、文档；`phos_api → 2` | `api/host_api.cpp`、`api/ui_api.cpp`、`api/draw_region.*`、`core/version.hpp`、`package/devkit/*`、`docs/*` | 新接口冒烟（devkit 的**演示卡带**，另加两张真用图层的出厂卡带：`carts/tetris` 四层、`carts/worms` 前景/读数/浮窗三层且画面逐字节不变）；`--check-api` 绿；不建层的旧卡带照旧 |
| P3 通道 | `state.query.layers`、**顶层** `merge_ms`、`screen.read(layer=…)`；（可选）事件订阅 | `core/app_control.cpp`、`docs/agent-interface.md`、`tools/*` | control_test 扩展断言 |
| P4 增配 | `text.ink_box`、`input.duration` / `input.keys`、`sys.frame`（`input.text` 早就在，不算本批新增） | `render/*`（度量回调装配）、`api/*`、`core/input.*` | 各自冒烟 + devkit 示例 |

回退策略：P1 是唯一触碰主循环的阶段，且只加一处受 `active()` 保护的调用——
若验收不过，删掉这一行即完全回到现状；P0 产物（layered_screen 与 alpha 字段）
仍可独立存在，不影响任何路径。

风险清单（提前写明）：

- **等价性是第一风险**：验收用逐字节对照，不靠肉眼；"无层 = 无合并步骤"
  由 `active()` 的结构保证，不靠"快路径"模拟。
- **keep 跨层误解**：作者会天然以为 keep 透到下层——§3.3 的规则与
  api-reference 的措辞必须在 P2 同批落地，否则会出现"在新 API 上复刻旧 bug"。
- **层数失控**：上限 6 写死在 `LayeredScreen`；超过时 `create` **直接报错**（走卡带既有的
  "错误屏 + 安全拔卡"通道）——返回一个"已有层"会让作者以为建好了，反而更难查。
  不允许"层多到合并变慢"成为隐形性能税。
- **惯性重构**：施工中最容易犯的错是"顺手把旧界面也用层重写一遍"——
  这在本文里是明确禁止项（G5、§4.8），评审时逐条对照。

---

## 6. 开放问题

| 问题 | 暂定结论 | 何时定案 |
|------|----------|----------|
| alpha 要不要真半透明 | v1 不做（布尔语义，字节预留） | 出现真实需求再说（届时单独立项） |
| 层是否对主机脚本（boot.lua 等）开放 | 暂不开放（层归卡带） | 有真实诉求时 |
| 事件订阅做不做 | 可选，P3 末尾评估 | 有 agent 侧真实诉求时 |
| 演示卡带放出厂还是 devkit | 已定：devkit 示例（`package/devkit/examples/layers/`），不进出厂列表 | 已落地 |
| 出厂卡带要不要有一张真用图层的 | 要，而且不止一张：`package/carts/tetris/`（井+已落定方块 / 下落块 / 特效 / 浮窗四层）与 `package/carts/worms/`（前景 / 读数 / 浮窗三层——它原是手排次序的立即式绘制，改成分层后画面逐字节不变）。示例卡带仍只在 devkit —— 不为了展示往架子上摆"样板"，摆真能玩的 | 已落地 |

---

## 7. 验收门禁清单（落地时逐项打勾）

- [x] 无层卡带：`tick_playing` 无合并步骤（`active()` 结构保证），
      未建层的出厂卡带 `--dump-screen` 逐字节一致
- [x] 合并语义用例：上层透明格透出底层、不透明格整格覆盖、keep 不跨网格（`tools/layer_smoke.py`）
- [x] 既有界面（开机/架/设置/暂停/磁带码/调试台）：未经任何改写，门禁全绿
- [x] `control_test.py` 增断言：`state.query.layers`、`screen.read(layer=…)` 默认等价
- [x] `--check-api` 覆盖全部新接口（DevKit 注解同步）
- [x] `merge_ms` ≤ 0.3ms（实测约 0.03ms）；60 档 `render_fps` 不低于无层基线 95%
- [x] `docs/api-reference.md` 补 `phos.layer`（句柄字段 / `order` / `remove` / 单层读取语义）、
      `docs/agent-interface.md`、`docs/cart-format.md`（`phos_api` 一节）同批更新
- [ ] 手册里仍差三段细目：region 的 `keep` 解析域、层的 alpha 布尔语义总表、抖屏 recipe
      （设计与实现在 §3.3 与本文其它节，api-reference 只欠这三段）
- [x] 版本：`kPhosApiVersion = 2` 与 manifest 门控用例（v2 卡带在 v1 主机被拒）

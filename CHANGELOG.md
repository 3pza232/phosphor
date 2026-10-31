# CHANGELOG

本文件记录面向卡带作者与发行版的**可见变化**；逐条实现细节见提交历史与 `docs/engine/acceptance.md`。
版本号与 `phos_api` 世代以 `src/core/version.hpp` 和 `docs/api-reference.md` 为准。

## 0.9.0（开发中）

### 平台与工程

- 内容根按 **exe 所在目录**解析（`--root` 可覆盖），绿色免安装；DevKit 资源缺失时回退 exe 目录。
- Windows + MSYS2 CI：构建、单测、14 项无头门禁（含 include 方向、API 一致性、内容包校验、便携启动）、
  性能预算与像素基线（非门禁）报告。
- 文本 golden（外壳 8 屏）+ 像素 golden（7 场景，含设置/Mod/磁带码/UI 示例）作为回归对照。
- `--check-cart`（manifest/入口/隐式全局/阻塞调用）与 `--check-packs`（六类内容包 error/warn，
  退出码 2）静态检查；`tools/release_check.py` 汇总发布前检查。
- 发行：`tools/package_release.py` 生成带清单/校验的 win64 zip；Debug/Sanity preset。

### 声明式 UI（`phos.ui` v2）

- 每帧声明元素树 + 引擎持有状态：column/row/box/text/divider/spacer/list/stat/option/checkbox/field/bar/
  button/hint/table/grid/scroll；padding/margin/gap/Box model；主题 token（颜色/字形/度量）。
- 焦点二维导航、按键重复（300ms + 3 帧/格）、模态捕获、`input=false` 只读屏。
- Scroll：纵向/横向（`scroll`/`scroll_x`）、视口裁剪、焦点自动跟随、位置指示条（可关）。
- Table：列宽基数 + 自适应列摊余量、列对齐、超长省略；Grid：`cols` 等宽分行、margin 语义。
- `phos.ui.toast`、`phos.ui.line/outline/circle` 几何原语（预裁剪/有界半径）、sprite 亮度；
  skin.lua 可选 `ui` 字形/度量覆盖（UI 主题包）。
- 外壳 7 屏（开机/卡带架/设置/暂停/Mod/磁带码/错误）全部由组件树绘制；`ui::ScreenStack` 表达浮层导航。
- `sprite`：UTF-8 字符键、solid 实心模式（按显示宽度填色）、brightness/step 语义定稿。

### 场景与卡带

- `phos.scene` 场景栈（push/pop、modal、pause_world、audio_pause、生命周期），11 张出厂卡带全部迁移；
  暂停/浮窗不再各自维护 paused 与音频开关。
- `phos.observe`（函数字段、查询时求值）、`phos.score`（TOP N/坏档容错）、`phos.lang.shared`、
  `phos.text.score|clock|percent`、`phos.save` 槽位 0..9。
- 异步联机 `discover_async`/`join_async`（不阻塞；`connect_failed` 带 reason）。

### 存档

- `PHOSPHOR-SAVE 2` 容器：magic + 版本 + 卡带 id + CRC32、原子写、旧档自动升级 + `.v1` 备份、
  坏档只读、跨卡带拒绝。
- 值类型保真：文本/数字/布尔/**表**（嵌套对象/数组，深度 ≤8，非法值拒绝）；磁带码仍走文本语义。

### 音频

- 暂停/恢复/停止/master 突变的 **6ms 线性斜坡**（消爆音）；声部优先级/抢占（48 + 8 尾巴）；
  music/sfx/ui 三路总线；ducking（`phos.audio.duck`）；`phos.audio.music_state()`。
- 主机事件音分档（错误/确认/插拔）走 UI 总线，不再被氛围音挤掉。

### 输入与外壳

- 窗口失焦释放全部按键；F2 设置、F1 关于、F3 存档管理、F5 内容包热重载、F12 截图（`screenshots/`）、
  反引号键打开调试台。
- 设置搜索（`/` 过滤、Esc 先退搜索）；关于页（版本/按键/内容根/致谢）。
- 内容包可选 `phos_api` 版本声明（过高版本跳过并 warning；check-packs 报错）。
- 动作映射 `phos.input.action`（动作→多键、默认同名、随卡带生命周期清理）。
- 按键重绑定：设置 F4（config.json 的 `input_bindings` 物理键→虚拟键；冲突覆盖提示）。
- 设置屏主题样张（当前主题色板/字形/文字/选中/BAR 即时预览）。
- 手柄：GLFW 标准布局 → 现有虚拟键（摇杆死区 0.35、热插拔、键盘/手柄共存、失焦释放）。
- 磁带码集中入口、存档管理入口（本版新增）。

### 内部结构

- App 拆出 `app/` 组装层与 DisplayState/FontState/SoundState/ShelfPlayback/BootSequence/TapeGlue/
  AgentController（21 分支命令与状态快照）；core 不再反向 include 上层。
- Screen 拆为 screen_store/screen_draw/screen_text；HostContext 脚本字段由 `HostCartBinding` 拥有卡带生命周期。
- 存档 v2、`json_lite` 严格化（转义/代理对/数字/深度/非有限数拒绝）。
- `FrameView` 统一 present/CPU 截图的「面/层/覆盖物」决策（绘制列表/文本投影仍待做）。

### 已知限制

- 音频无 CI 设备/单测；流式采样、渲染三路径收口（FrameComposer）未完成。
- 像素 golden 非门禁（跨机字体差异）；JSON 解析仍保留宽松容错。
- towerdef 4096 字节/值上限在极后期高密度局可能逼近；`mods/towerdef-build-pause` 仍为整文件 fork。

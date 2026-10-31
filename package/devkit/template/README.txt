__NAME__ —— PHOSPHOR 卡带骨架
================================

建卡（标题、作者创建时就能定）：
    phosphor.exe --new carts/mygame --id mygame --name "我的游戏" --author "你"

运行（改完直接跑，卡带**不需要**编译；内容目录由构建时从源码同步而来）：
    phosphor.exe --cart carts/mygame
自测（无窗口跑 N 帧并把字符画面打出来，适合脚本与 agent）：
    phosphor.exe --cart carts/mygame --headless --frames 60 --dump-screen
静态检查（不运行卡带；manifest / 入口 / 隐式全局 / 阻塞调用）：
    phosphor.exe --check-cart carts/mygame

该填哪里
--------
manifest.lua   卡带身份证。id / name / desc（双语）/ version 直接改；
               sidebar = { w = 18 } 决定右栏宽度（删掉这行 = 无侧栏，
               也可运行时 phos.panel.resize(w)）；
               save = true 才会用到 phos.save.*；entry 指向入口脚本；
               phos_api = 7（模板侧栏用声明式界面，世代 7 才有的接口）。
main.lua       入口。只做三件事：装配模块 / 把输入翻成"意图" / 把状态画出来。
               要动手的地方都标了「填」：Text 文案表、init、update、draw、debug_state。
game.lua       玩法规则。不读键盘、不画东西、不发声音——只按 move/act/update 推进局面，
               并 return 事件表告诉 main.lua"发生了什么"。
panel.lua      右侧栏。用 phos.ui.render 声明组件（surface = "panel"、input = false），
               坐标/裁剪/对齐由引擎负责，不再手写面板局部坐标。
assets/        可选。分语言文本示例（motd.zh.txt / motd.en.txt，取不到回落 motd.txt），
               用 phos.assets.rows("assets/motd.txt") 读；覆盖层 mod 会替换这里的内容。

四条最容易踩的线
----------------
1) 画面只画到**可玩区**：
       local px, py, pw, ph = phos.screen.playfield()
   直接用 phos.screen.size() 会连侧栏覆盖的几列一起算，画到右边会被挡掉
   （侧栏宽度可在运行时改，所以每次画的时候取一次）。
2) 定宽位置的文案用 phos.text.fit(text, cols)：超宽会截断并补"…"；
   直接 print 会被主机从右边硬切，留下半句话。分区 / 小地图用
   phos.ui.region(...)（自带裁剪，越界不画）。
3) 键位提示写键盘上真实的键：phos.input.key_name("a")，不要写手柄按钮名。
4) 界面写组件，不写像素：phos.ui.render{ ... } 用 text/list/stat/checkbox/field/bar/hint
   等元素声明，盒模型（padding/margin/gap/grow/宽高/对齐）、配色、焦点、滚动由引擎负责；
   完整字段见 docs/api-reference.md 的「声明式界面」一节，可跑样板在 devkit/examples/ui/。

接着读
------
docs/devkit.md         上手手册：模板填空表、踩坑清单、给 agent 的流程
docs/api-reference.md  每个 phos.* 调用（权威规格）
docs/cart-format.md    manifest 字段、生命周期、沙箱规则
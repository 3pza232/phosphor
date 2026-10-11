WORMS —— PHOSPHOR 卡带骨架
================================

建卡（标题、作者创建时就能定）：
    phosphor.exe --new carts/mygame --id mygame --name "我的游戏" --author "你"

运行（改完直接跑，卡带**不需要**编译；内容目录由构建时从源码同步而来）：
    phosphor.exe --cart carts/mygame
自测（无窗口跑 N 帧并把字符画面打出来，适合脚本与 agent）：
    phosphor.exe --cart carts/mygame --headless --frames 60 --dump-screen

该填哪里
--------
manifest.lua   卡带身份证。id / name / desc（双语）/ version 直接改；
               sidebar = { w = 18 } 决定右栏宽度（删掉这行 = 无侧栏，
               也可运行时 phos.panel.resize(w)）；
               save = true 才会用到 phos.save.*；entry 指向入口脚本。
main.lua       入口。只做三件事：装配模块 / 把输入翻成"意图" / 把状态画出来。
               绘制分三层：世界（天空+地形）写底层，前景 fx / 读数 hud / 浮窗 overlay
               各一层，见 main.lua 顶部与 init 的说明。
               要动手的地方都标了「填」：Text 文案表、init、update、draw、debug_state。
game.lua       玩法规则。不读键盘、不画东西、不发声音——只按 move/act/update 推进局面，
               并 return 事件表告诉 main.lua"发生了什么"。
panel.lua      右侧栏。坐标是面板局部的；定宽文案一律过 phos.text.fit(text, pw - 2)。
assets/        可选。分语言文本示例（motd.zh.txt / motd.en.txt，取不到回落 motd.txt），
               用 phos.assets.rows("assets/motd.txt") 读；覆盖层 mod 会替换这里的内容。

三条最容易踩的线
----------------
1) 画面只画到**可玩区**：
       local px, py, pw, ph = phos.screen.playfield()
   直接用 phos.screen.size() 会连侧栏覆盖的几列一起算，画到右边会被挡掉
   （侧栏宽度可在运行时改，所以每次画的时候取一次）。
2) 定宽位置的文案用 phos.text.fit(text, cols)：超宽会截断并补"…"；
   直接 print 会被主机从右边硬切，留下半句话。分区 / 小地图用
   phos.ui.region(...)（自带裁剪，越界不画）。
3) 键位提示写键盘上真实的键：phos.input.key_name("a")，不要写手柄按钮名。

接着读
------
docs/devkit.md         上手手册：模板填空表、踩坑清单、给 agent 的流程
docs/api-reference.md  每个 phos.* 调用（权威规格）
docs/cart-format.md    manifest 字段、生命周期、沙箱规则

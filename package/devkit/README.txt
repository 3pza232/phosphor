PHOSPHOR 开发套件
=================

做卡带用的工具。运行主机本身不需要它们 —— 它们是给卡带作者（人或 agent）用的。


1. 模板 —— devkit/template/
--------------------------------
一份最小、带注释的卡带骨架。可以直接用命令行生成（给个目录名就够了）：

    phosphor.exe --new carts/mygame

id 与标题默认取这个名字，其余字段（author / desc / icon / sidebar / save）在
manifest.lua 里改 —— 改完立刻生效。

接着从 game.lua（你的规则：不碰输入、绘制、音频、存档）与
main.lua（读按键 → 调规则 → 绘制）入手。直接跑：

    phosphor.exe --cart carts/mygame

或者把目录丢进 carts/ 从卡带架上选。做完之后打包：

    phosphor.exe --pack carts/mygame            （产出 dist/mygame.phos）


2. 编辑器支持 —— devkit/phos.lua
-------------------------------------
整套 phos.* API 的类型定义（EmmyLua / Lua Language Server 用）。
把它加进你的卡带工作区，就有补全与参数提示。VSCode：在卡带旁建一个 .luarc.json：

    {
      "workspace.library": ["../devkit/phos.lua"],
      "runtime.version": "Lua 5.4"
    }

注解必须与实现一致，主机可以当场核对：

    phosphor.exe --check-api        （退出码 0 = 一致，2 = 有漂移）


3. 控制通道 —— 给自动化测试与 agent 用
-------------------------------------------------------
带一个控制端口启动主机：

    phosphor.exe --cart carts/mygame --control 7654

然后在 127.0.0.1:7654 上收发按行分隔的 JSON：

    {"id":1,"cmd":"state.query"}
    {"id":2,"cmd":"screen.read"}
    {"id":3,"cmd":"input.inject","key":"right","frames":5}
    {"id":4,"cmd":"time.step","frames":60}     <- 精确推进 60 个逻辑帧
    {"id":5,"cmd":"cart.reload"}               <- 改完代码热重载

命令：ping / state.query / screen.read / screenshot / carts.scan /
      input.inject / input.text / input.clear / time.step / time.resume /
      save.export / save.import / cart.load / cart.reload / cart.eject / quit
      （参数全表见 docs/agent-interface.md）

不想开通道的话，还有一次性的办法：

    phosphor.exe --cart carts/mygame --headless --frames 300 --dump-screen


参考
----------
  docs/api-reference.md      每个 phos.* 调用
  docs/cart-format.md        manifest 字段、生命周期、沙箱
  docs/agent-interface.md    命令行与控制通道协议
  carts/snake/               一个多文件的完整例子（6 个模块）

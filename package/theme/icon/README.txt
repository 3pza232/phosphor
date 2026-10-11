PHOSPHOR 图标
=============

这个目录有两张图标，用途**不一样**：

  phos_icon.jpg   窗口图标。
                  主机开窗时用 glfwSetWindowIcon 设置，运行期读取。
                  改这张、存盘、重开主机即生效（无需重新构建）。
                  读不到就退回系统默认图标，并在主机日志里留一行。

  phos_icon.ico   可执行文件图标 —— Explorer / 任务栏给 phosphor.exe 显示的那枚。
                  它是**链接期嵌进 exe 的 Win32 资源**，运行时改不动：
                  光换 jpg 不会改它（窗口图标会变，exe 图标不会）。

想换 exe 图标（源码仓库里操作）：

  1. 用新的图覆盖 phos_icon.jpg
  2. 重新生成 ico：  python tools/make_icon.py
  3. 重新构建：      cmake --build build

.ico 是开发期生成一次、随源码提交的（构建不依赖 Python）。尺寸覆盖
16/24/32/48/64/128/256，够 Explorer、任务栏与 Alt-Tab 各场景用。

（发行包里只有本目录的文件内容，不含 tools/ —— 普通玩家换窗口图标改 jpg 即可，
换 exe 图标需要源码与一次构建。）

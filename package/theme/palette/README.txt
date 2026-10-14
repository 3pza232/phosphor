[ theme/palette - 内容色板 ]
============================

每个子文件夹 = 一套色板（12 个颜色槽 + 扫描线/色调参数）。
**它不再是一个单独的设置项**：每套主题（theme/skin）用 skin.lua 的 `palette = "<名>"`
声明自己用哪套色板；换主题就换色板，卡带与开机动画的 `phos.color.*` 随之变。

现有：
  default    GREEN PHOSPHOR：经典荧光绿（出厂默认）
  amber      AMBER CRT：琥珀色单色显像管
  ice-blue   ICE BLUE：冷色冰蓝
  slate      SLATE TERMINAL：去饱和灰白
  paper      PAPER INK：纸面深墨（配浅色机身主题，卡带变"浅底深字"）
  crimson    CRIMSON PHOSPHOR：血橙红街机显像管（配 crimson-arcade）
  eva        NERV UNIT-01：初号机色（紫 / 荧光绿 / 橙，配 eva-unit01）

主机内置、不是文件夹：
  NONE (RAW) 不改配色、不加扫描线 —— 卡带自身配色被完整保留（主题未声明色板或找不到时回落它）

一套色板决定什么：
  * 12 个颜色槽位的色值（卡带里的 phos.color.green 等会跟着变）；
    其中 black 是卡带清屏底、white 是默认文字色 —— 浅色色板就是"浅底深字"
  * 扫描线强度、整体色调（连机身界面一起受影响）

怎么做：复制 default 文件夹，改名成新色板，编辑 palette.lua，再到某套 skin.lua 里写 `palette = "<名>"`。
      字段规范见 docs/content-packs.md。

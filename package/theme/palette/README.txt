[ theme/palette - 显像管滤镜 ]
==============================

每个子文件夹 = 一种显像管味道。文件夹名就是设置里显示的名字。

现有：
  default    GREEN PHOSPHOR：经典荧光绿（出厂默认）
  amber      AMBER CRT：琥珀色单色显像管
  ice-blue   ICE BLUE：冷色冰蓝
  slate      SLATE TERMINAL：去饱和灰白

设置里还有一项是主机内置的，不是文件夹：
  NONE       不改配色、不加扫描线 —— 卡带自身配色被完整保留

因此：卡带的原色设计很重要时（比如卡带自己精心配过色），游玩时选 NONE。

一套滤镜决定什么：
  * 12 个颜色槽位的色值（卡带里的 phos.color.green 等会跟着变）
  * 扫描线强度、整体色调（连机身界面一起受影响）

怎么做：复制 default 文件夹，改名，编辑 palette.lua。
      字段规范见 docs/content-packs.md。

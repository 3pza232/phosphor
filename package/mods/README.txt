[ mods - 覆盖层 Mod ]
=====================

一个文件夹就是一个 Mod：**放进这里即自动生效**，删除即还原。自由命名，无需开关。

  mods/<任意名>/overrides/<目标id>/<目标内路径>

「目标 id」是要覆盖的内容包的文件夹名、字体方案名，或卡带 id；
「目标内路径」与包内一致。一个 Mod 可以放多条 overrides，同时改多处内容。

例：

  big-font/overrides/default/font.lua        抬高字号上限（出厂自带的示例 Mod）
  my-tweaks/overrides/snake/panel.lua        改贪吃蛇侧栏
  my-tweaks/overrides/snake/game.lua         改玩法数值
  my-tweaks/overrides/snake/assets/map.txt   改关卡数据
  dark/overrides/graphite/skin.lua           改某个主题的外观
  loud/overrides/relay/sounds.lua            改主机音效

多个 Mod 改同一个文件时，按 Mod 目录名排序，后者覆盖前者。

唯一例外：卡带的 manifest.lua 不可覆盖（身份必须稳定，否则扫描/打包/运行会认知不一）。
想改身份请直接改原文件。

规范见 docs/content-packs.md 的「Mod 体系」。

[ mods - 覆盖层 Mod ]
=====================

**mods/ 下的相对路径本身就是覆盖键**：`mods/<目标id>/<目标内路径>`。
放进这里即自动生效，删除即还原；没有开关、没有多余层级。

  「目标 id」= 内容包文件夹名 / 字体方案名 / 卡带 id（目录名，或 <id>.phos 去后缀）
  「目标内路径」与包内一致（font.lua / skin.lua / panel.lua / assets/…）

例：

  default/font.lua        抬高字号上限（出厂自带的示例 Mod）
  snake/panel.lua         改贪吃蛇侧栏
  snake/game.lua          改玩法数值
  snake/assets/map.txt    改关卡数据
  graphite/skin.lua       改某个主题的外观
  relay/sounds.lua        改主机音效

一个键（`<目标id>/<路径>`）在文件系统里只有一份 → 没有"多 Mod 叠层、谁盖谁"的问题。
根目录下的裸文件（只有一段、定位不到目标）会被忽略。

唯一例外：卡带的 manifest.lua 不可覆盖（身份必须稳定，否则扫描/打包/运行会认知不一）。
想改身份请直接改原文件。

规范见 docs/content-packs.md 的「Mod 体系」。

[ mods - 覆盖层 Mod ]
=====================

mods/ 下直接是**有名字的 mod 文件夹**：一个文件夹 = 一个 mod，**文件夹名就是它的 id**。
列表里显示的是 mod 自己的名字（见下面的 mod.lua），而不是"目标 id"。

  mods/<mod-id>/                 一个 mod（文件夹名 = id，如 font-resize）
  ├── mod.lua                    可选清单：return { name = {..}, desc = {..} }（显示名/说明）
  └── <目标id>/<目标内路径>        覆盖内容（镜像要覆盖的包/卡带结构）

放进这里即自动生效（默认启用），删除即还原。

  游戏内开关：卡带架按 M 打开 MODS 浮窗，逐条勾选生效的 Mod；禁用集合写进
  config.json 的 mods_disabled（按 **mod-id** 记，不是目标 id），改动后重启主机生效。
  （mods/ 为空时不显示此键）

  「目标 id」= 内容包文件夹名 / 字体方案名 / 卡带 id（目录名，或 <id>.phos 去后缀）
  「目标内路径」与包内一致（font.lua / skin.lua / panel.lua / assets/…）

覆盖键取 **<mod-id> 之后**的相对路径 `<目标id>/<目标内路径>`：

  mods/font-resize/default/font.lua   覆盖键 default/font.lua   → 抬高字体方案 default 的字号上限
  mods/snake-tweaks/snake/panel.lua   覆盖键 snake/panel.lua    → 改贪吃蛇侧栏
  mods/snake-tweaks/snake/game.lua    覆盖键 snake/game.lua     → 改玩法数值
  mods/snake-tweaks/snake/assets/map.txt                         → 改关卡数据
  mods/bold-theme/graphite/skin.lua   覆盖键 graphite/skin.lua  → 改某个主题的外观
  mods/quiet/relay/sounds.lua         覆盖键 relay/sounds.lua   → 改主机音效

一个 mod 可以覆盖多个目标（多放几个 `<目标id>/…`）。覆盖键在一个 mod 内只有一份；
两个 mod 撞同一个键时按 mod-id 字典序后者覆盖前者，并写日志告警（mods 目录里的
`mod.lua` 与任何"只有一段"的裸文件定位不到目标，会被忽略）。

唯一例外：卡带的 manifest.lua 不可覆盖（身份必须稳定，否则扫描/打包/运行会认知不一）。
想改身份请直接改原文件。

规范见 docs/content-packs.md 的「Mod 体系」。

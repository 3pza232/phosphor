[ mods - 覆盖层 Mod ]
=====================

想改某张卡带或某个主题，又不想动原文件？在这里放同名文件即可覆盖。

  mods/<目标id>/<与包内相同的相对路径>

目标 id 就是文件夹名（.phos 单文件取文件名去掉后缀）。
可以覆盖的东西：

  mods/snake/panel.lua              改贪吃蛇的侧栏面板
  mods/snake/game.lua               改玩法数值/规则
  mods/snake/assets/map.txt         改关卡数据
  mods/snake/main.lua               改主逻辑
  mods/rust-cabinet/skin.lua        改机台外观
  mods/static-rain/main.lua         改开机动画
  mods/relay/sounds.lua             改主机音效

唯一例外：卡带的 manifest.lua 不可覆盖。
卡带身份（id / entry / 是否要存档）必须稳定，否则扫描、打包与运行时会
对同一张卡带产生不同认知 —— 想改身份请直接改原文件。

删除对应文件即可还原；原包始终完好无损。
规范见 docs/content-packs.md

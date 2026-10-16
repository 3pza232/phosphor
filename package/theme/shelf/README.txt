[ theme/shelf - 卡带架样式 ]
============================

一个 shelf 包 = theme/shelf/<名字>/shelf.lua，提供 draw(ctx)。
文件夹名就是设置里"卡带架样式"一行显示的名字。

它接管的是卡带架的**内容区**（不是机身，也不管输入）：
  主机照常画机身/chrome，也照常处理上下移动光标、搜索、Enter 插卡、Esc；
  内容区交给当前激活的 shelf 包逐帧画出来。

shelf.lua 的契约（与开机动画同构的一段 Lua）：
  * 必须有 function draw(ctx)  —— ctx 见 docs/content-packs.md 的「shelf」一节
  * update(dt) 可选            —— 每逻辑帧先调它，再调 draw(ctx)
  * 可用 phos.screen / phos.ui / phos.color / phos.text / phos.lang / phos.sys
    在 ctx.content 划定的内容区（内容区局部坐标，80x45）内作画

顶层还可声明（扫描时被主机读走，不进入 ctx）：
  * name = { zh = "卡片墙", en = "GRID" }  设置里显示的名字（也可是字符串）
  * cols = 4                                每行个数：上/下键按行移动（∓cols），左/右键逐格

空列表（一张卡带都没有）由主机自己画提示，不会调用包。
包缺失/脚本出错时，主机安静回退内置的 list / window 样式并留下日志。

现有：
  grid     GRID：卡带墙——网格排布的图标，当前项高亮、其余变暗，底部一行名称 + 简介

怎么做：复制 grid 文件夹，改名，编辑 shelf.lua。
        package/theme/shelf/grid/shelf.lua 是一份可直接照抄的样板。

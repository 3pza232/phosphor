[ mods - 覆盖层 Mod ]
=====================

mods/ 下每个文件夹就是一个**独立的 mod**：文件夹名 = mod 名。文件夹里直接放这个 mod
独有的内容（扁平，文件名自由），再由它自己的 `mod.lua` 清单**声明这些内容覆盖到哪里**。
列表里显示的是 mod 自己的名字（见 mod.lua 的 name），而不是"目标 id"。

  mods/<mod-id>/                 一个 mod（文件夹名 = mod 名，如 font-resize）
  ├── mod.lua                    必需清单：name/desc + overrides（见下）
  └── <任意文件名>                该 mod 独有的内容（扁平；也可放子目录，如 files/x.lua）

mod.lua（Lua，返回一个表）：

  return {
    name = { zh = "字体放大", en = "Font Resize" },   -- 管理器显示名（缺省 = 文件夹名）
    desc = { zh = "…", en = "…" },                    -- 可选说明
    overrides = {                                     -- 覆盖注册：键 = "<目标id>/<包内路径>"
      ["default/font.lua"] = "font.lua",              -- 值 = 本 mod 目录内的相对文件
    },
  }

放进 mods/ 即自动生效（默认启用），删除即还原；没有 mod.lua 或 overrides 的文件夹会被
跳过（并写日志）。游戏内开关：卡带架按 M 打开 MODS 浮窗，逐条勾选；禁用集合写进 config.json
的 mods_disabled（按 **mod-id** = 文件夹名记），改动后重启主机生效。（mods/ 为空时不显示此键）

  「目标 id」= 内容包文件夹名 / 字体方案名 / 卡带 id（目录名，或 <id>.phos 去后缀）
  「包内路径」与包内一致（font.lua / skin.lua / panel.lua / assets/…）

例子：

  mods/font-resize/       mod.lua: overrides = { ["default/font.lua"] = "font.lua" }
                          font.lua: 抬高字体方案 default 的字号上限
  mods/snake-tweaks/      mod.lua: overrides = { ["snake/panel.lua"] = "panel.lua",
                                                 ["snake/game.lua"] = "game.lua" }
                          panel.lua / game.lua: 改贪吃蛇侧栏与玩法数值（一个 mod 覆盖多文件）

一个 mod 可注册多条 overrides（多目标 / 多文件）。多个 mod 撞同一个键时，按 mod-id 字典序
后者覆盖前者，并写日志告警。被禁用的 mod 整份不进表（但仍列在管理器里，可再打开）。

唯一例外：卡带的 manifest.lua 不可覆盖（身份必须稳定，否则扫描/打包/运行会认知不一）。
想改身份请直接改原文件。

规范见 docs/content-packs.md 的「Mod 体系」。

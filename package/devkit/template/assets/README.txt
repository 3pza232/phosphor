[ assets - 卡带自带的资源 ]
============================

放在这里的文件随卡带一起分发（打包进 .phos 时一并写入）。

读取方式（phos.assets，路径相对包根）：

  local text = phos.assets.text("assets/motd.txt")     -- 全文，缺失返回 nil
  local rows = phos.assets.rows("assets/map.txt")      -- 按行，1 基数组
  phos.assets.exists("assets/map.txt")                 -- 是否存在
  phos.assets.size("assets/motd.txt")                  -- 字节数
  phos.assets.list("assets/")                          -- 列出包内文件

适合放的东西：
  * 关卡片段、地图、对话表    —— 纯文本，一行一个元素，用 rows 读
  * 字符画素材（sprites/UI）
  * 音频文件（配合 phos.audio.sample）
  * 调参表（平衡性数值），改完不必动代码

覆盖层 Mod 也能替换这里的文件：把同名文件放到程序目录的
mods/<卡带id>/assets/ 下即可，卡带代码无需改动。

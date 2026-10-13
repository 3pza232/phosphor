[ mod: big-font —— 大字号 ]
============================

这个文件夹就是一个**覆盖层 Mod**。放进 mods/ 里即**自动生效**（没有开关、没有"方案"）。
删掉整个文件夹即还原。

它把「设置 → 字号」的可调上限从出厂 24 抬到 28（多一档更大的字）。

做法：覆盖字体方案 default 的声明文件——

  overrides/default/font.lua   → 覆盖 package/theme/font/default/font.lua

这是覆盖层 Mod 的通用写法：

  mods/<任意名>/overrides/<目标id>/<目标内路径>

可覆盖的目标：任意内容包脚本（skin / palette / boot / sound / font）与任意卡带脚本 /
资源（manifest.lua 除外，身份必须稳定）。一个 mod 可以放多个 overrides，改多处内容。

规范见 docs/content-packs.md 的「Mod 体系」。

-- Mod 清单：MODS 管理器里显示的就是这里的 name（缺省显示名 = 文件夹名）。
-- overrides 把这个 mod 独有的 main.lua 登记到卡带 towerdef 的入口上。
-- default_off = true：出厂附带但**默认关闭**，玩家在 MODS 管理器里打开、重启后才生效。
return {
  name = { zh = "塔防建造暂停", en = "Towerdef Build Pause" },
  desc = {
    zh = "对局中按 F 冻结战场：塔不开火、敌人不动、计时不流失，从容摆塔",
    en = "Press F in-game to freeze the field and place towers",
  },
  default_off = true,
  overrides = {
    ["towerdef/main.lua"] = "main.lua",
  },
}

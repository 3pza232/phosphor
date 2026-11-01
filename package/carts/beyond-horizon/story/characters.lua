-- story/characters.lua —— 《视界线外》角色表（纯数据，schema 见 design/STORY_SCHEMA.md）
return {
  schema = 1,
  order = { "ye", "hestia", "gu", "isha", "ada", "voice", "sleeper", "narrator" },
  cast = {
    ye     = { name = { zh = "叶翎", en = "YE LING" }, color = "yellow", style = "player" },
    hestia = { name = { zh = "赫斯提亚", en = "HESTIA" }, color = "cyan", style = "ai" },
    gu     = { name = { zh = "顾长明", en = "GU CHANGMING" }, color = "orange", style = "recording" },
    isha   = { name = { zh = "伊莎·科尔", en = "ISHA KOR" }, color = "blue", style = "radio" },
    ada    = { name = { zh = "艾达", en = "ADA" }, color = "magenta", style = "dream" },
    voice  = { name = { zh = "声音", en = "THE VOICE" }, color = "red", style = "voice" },
    sleeper= { name = { zh = "沉睡者", en = "SLEEPER" }, color = "gray", style = "dream" },
    narrator = { name = { zh = "", en = "" }, color = "gray", style = "narration" },
  },
}

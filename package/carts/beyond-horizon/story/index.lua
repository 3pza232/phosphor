-- story/index.lua —— 剧情数据汇总装载（纯数据；STORY_SCHEMA v1）。
-- 程序也可按 STORY_SCHEMA §2 直接 require story.ch1..ch8 / story.endings / story.characters；
-- 本文件只是给“一次拿到全部数据”的工具/校验器用的静态汇总，不做任何逻辑。
return {
  schema = 1,
  chapters = {
    require("story.ch1"),
    require("story.ch2"),
    require("story.ch3"),
    require("story.ch4"),
    require("story.ch5"),
    require("story.ch6"),
    require("story.ch7"),
    require("story.ch8"),
  },
  endings = require("story.endings"),
  characters = require("story.characters"),
}

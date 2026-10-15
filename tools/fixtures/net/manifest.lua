-- manifest.lua —— 局域网联机的**测试夹具卡带**，供 tools/net_smoke.py 驱动。
-- 放在 tools/fixtures（**开发目录，不随发行包**）：它测的是引擎的 `phos.net`，
-- 不是给玩家玩的出厂卡带。设计见 docs/engine/networking.md。
return {
  id = "net-demo",
  name = "NET DEMO",
  version = "1.0.0",
  author = "phosphor",
  desc = {
    zh = "局域网联机示例：H 开房、J 加入（自动发现），连上后互发心跳、显示对端与收发包数。",
    en = "LAN demo: H to host, J to join (auto-discovery); heartbeats and peer list.",
  },
  entry = "main.lua",

  -- 局域网联机是第四代接口：声明 4，旧主机在卡带架上就明确拒绝
  phos_api = 4,
}

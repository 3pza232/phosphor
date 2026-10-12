-- main.lua —— 局域网联机示例。把 `phos.net` 的每个调用都摆出来，并把状态交给观察口。
--
-- 玩法（也是 tools/net_smoke.py 的被测点）：
--   H 开房（固定端口 7770）        J 加入（先局域网发现，找不到就本地回环 127.0.0.1）
--   连上之后每 60 帧给所有人发一次心跳；收到任何消息都计数并记录来源。
-- 卡带只做**收发与显示**，同步模型（谁该干什么）不在示例范围——那是各卡带自己的事。

local C = phos.color

local Text = {
  zh = { title = "PHOSPHOR NET", hint = "H 开房   J 加入   D 发现   O 开关可加入   Esc 退出",
         status = "状态", peers = "对端", sent = "发出", recv = "收到", last = "最近" },
  en = { title = "PHOSPHOR NET", hint = "H host   J join   D discover   O toggle open   Esc quit",
         status = "STATUS", peers = "PEERS", sent = "SENT", recv = "RECV", last = "LAST" },
}
local function L() return phos.lang.dict(Text) end

local PORT = 7770
local role = "none"
local sent, received, last_from, last_kind = 0, 0, -1, "-"
local connects, disconnects = 0, 0
local join_discovered = false
local found_count, found_open = 0, true  -- 最近一次 discover 的结果（房间数 / 首个房间是否可加入）
local room_open = true                    -- set_room 的开关（O 键切换），供 net_smoke 校验
local frame = 0

local function try_host()
  role = phos.net.role()
  phos.net.host({ port = PORT, name = "HOST" })
  role = phos.net.role()
end

local function try_join()
  -- 先自动发现；找不到再退回本地回环（同机自测/单机演示都能用）
  local rooms = phos.net.discover(0.6)
  join_discovered = #rooms > 0
  if join_discovered then
    phos.net.join(rooms[1].address, { port = rooms[1].port, name = "P2" })
  else
    phos.net.join("127.0.0.1", { port = PORT, name = "P2" })
  end
  role = phos.net.role()
end

function init()
  role = phos.net.role()
end

function update(dt)
  frame = frame + 1
  if phos.input.pressed("h") then try_host() end
  if phos.input.pressed("j") then try_join() end
  if phos.input.pressed("d") then
    local rooms = phos.net.discover(0.4)
    found_count = #rooms
    found_open = (rooms[1] and rooms[1].open) and true or false
  end
  if phos.input.pressed("o") then
    room_open = not room_open
    phos.net.set_room({ open = room_open })
  end

  role = phos.net.role()
  for _, e in ipairs(phos.net.events()) do
    if e.type == "connected" then connects = connects + 1 else disconnects = disconnects + 1 end
  end
  for _, m in ipairs(phos.net.poll()) do
    received = received + 1
    last_from, last_kind = m.from, m.kind
  end
  if phos.net.connected() and frame % 60 == 0 then
    if phos.net.send(0, "beat", { n = frame }) then sent = sent + 1 end
  end
end

function draw()
  local t = L()
  phos.screen.clear(C.white, phos.color.rgb(10, 20, 30))
  phos.screen.print(2, 1, t.title, C.yellow)
  phos.screen.print(2, 3, t.hint, C.gray)
  phos.screen.print(2, 5, string.format("%s: %s  role=%s  self=%d  host=%d  port=%d",
    t.status, phos.net.status(), role, phos.net.self_id(), phos.net.host_id(),
    phos.net.port()), C.white)
  phos.screen.print(2, 6, "local_ip=" .. phos.net.local_ip(), C.dark_gray)

  local peers = phos.net.peers()
  phos.screen.print(2, 8, string.format("%s (%d):", t.peers, #peers), C.cyan)
  for i, p in ipairs(peers) do
    phos.screen.print(4, 8 + i, string.format("#%d %s %s rtt=%d", p.id, p.name, p.address,
      math.floor((p.rtt_ms or -1) + 0.5)), C.white)
  end
  local y = 8 + #peers + 2
  phos.screen.print(2, y, string.format("%s=%d  %s=%d  %s=%s", t.sent, sent, t.recv, received,
    t.last, last_kind), C.green)
  phos.screen.print(2, y + 1, string.format("connects=%d disconnects=%d discovered=%s",
    connects, disconnects, join_discovered and "yes" or "no"), C.gray)
end

function debug_state()
  local ids = {}
  for _, p in ipairs(phos.net.peers()) do ids[#ids + 1] = p.id end
  return {
    status = phos.net.status(),
    role = role,
    self_id = phos.net.self_id(),
    host_id = phos.net.host_id(),
    connected = phos.net.connected(),
    peers = ids,
    peer_count = #ids,
    sent = sent,
    received = received,
    last_from = last_from,
    last_kind = last_kind,
    connects = connects,
    disconnects = disconnects,
    join_discovered = join_discovered and 1 or 0,
    found_count = found_count,          -- 上次 discover 找到的房间数（去重后应为 1）
    found_open = found_open and 1 or 0, -- 首个房间的 open 标志（配合 set_room 校验）
    room_open = room_open and 1 or 0,   -- 本机 set_room 的当前值
  }
end

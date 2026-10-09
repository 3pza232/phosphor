-- game.lua —— 玩法规则。三条纪律，越早守住越省事：
--   1) 不读键盘：输入由 main.lua 翻成 move/act 这类"意图"再调用这里
--   2) 不画东西：画法归 main.lua，规则只认"格/秒"这类与屏幕无关的单位
--   3) 不发声音：要出声就 return 一张事件表，由 main.lua 决定怎么响
-- 这样规则可以脱离画面单独推演，长起来也方便再拆文件（panel / music / scores…）。

local Game = {}
Game.__index = Game

function Game.new()
  local self = setmetatable({}, Game)
  self.score = 0
  -- 「填」这里放你的局面：位置、速度、计时器……单位一律用格和秒
  return self
end

-- 「填」输入意图：由 main.lua 在玩家按键时调用；能不能这么做由这里判定
-- （例如"撞墙就不动""冷却没到就忽略"——这类判断属于规则，不属于输入）
function Game:move(dx, dy) end
function Game:act() end

-- 「填」推进一帧。dt 为秒；返回值是事件表，main.lua 据此决定音效/存档等副作用
function Game:update(dt)
  local events = {}
  return events
end

-- 「填」供 agent 观察的玩法状态（由 main.lua 的 debug_state 转出去）
function Game:status()
  return { score = self.score }
end

return Game

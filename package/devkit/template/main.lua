-- main.lua —— 卡带入口。它只做三件事：装配模块、把输入翻成"意图"、把状态画出来。
--
-- 生命周期（主机按固定逻辑帧调用）：
--   init()      插卡后一次
--   update(dt)  每逻辑帧一次（dt 为秒）
--   draw()      紧随 update，每逻辑帧一次
--
-- 开始写之前只要记住一句话：**规则放 game.lua，输入与画法留在这里**。
-- 全文件需要你动手的地方都标了「填」，其余是骨架自带的约定，照抄即可。
-- 完整 API：docs/api-reference.md；本目录的 phos.lua 提供编辑器补全。
--
-- ─────────────────────────────────────────────────────────────
-- 十条约定：每条都对应一条真实约束（违反其中任何一条，都会以难查的显示问题收场）
--
-- 1. 底色默认透明。put/print/fill/blit 不传背景 = **保留原来那格的背景**。
--    只有"需要强调"的地方才显式传一个底（例如画面内的读数、血条、浮窗）：
--      S.print(x, y, text, C.white)                     -- 透明 ✓
--      S.print(x, y, text, C.white, C.rgb(10,12,20))    -- 有底 ✓
--    卡带的 phos.ui.* 与 phos.ui.region 同样默认不透明？
--    不——它们也默认"不动背景"，要底就显式给色。
--
-- 2. 画"铺满画面"的东西一律用 S.playfield()，不要用 screen.size()：
--    后者含侧栏盖住的那几列，画过去会被挡掉一截（障碍物会"藏在侧栏后面走出来"）。
--
-- 3. 定宽位置（侧栏、状态条）用 phos.text.fit(文案, 列数) 裁剪并补省略号；
--    主机在右边是硬切，会留下"[↑/A] 跳：按住更"这种半句话。
--    中文占两格，要用 phos.text.width() 量，别用 #str（那是字节数）。
--
-- 4. 键名是**动态**的：phos.input.down("space")、"z"、"f1"、"1" 都能用，
--    主机不需要为某个键改代码、更不需要重编译。做"自定义按键"就用
--    phos.input.any_pressed() 拿名字存进 phos.save，之后直接按名字查状态。
--
-- 5. 单次调用不得超过 **100 毫秒**（主机有看门狗，超了直接报卡带错误）。
--    要算几百组候选（AI、寻路、预演）就做成"分帧推进"：每帧算一小批。
--
-- 6. 数值靠算，不靠试。跳跃能否越过障碍 = 高度的**保持时间**要长于通过时间；
--    写死一个"看起来能跳过"的参数，迟早被一个更高的障碍打脸。
--
-- 7. 位置按数据推，不要写死坐标。地图/棋盘/地形是数据驱动的，
--    "正中那格"很可能正好是墙，写死的奖励物会长在墙里，永远拿不到。
--
-- 8. 寻路/追人要防死角：只有一条出口的格子进去就出不来（禁止掉头时会卡死），
--    要么不进，要么允许掉头，换目标时全体转向也是个好习惯。
--
-- 9. 像素精灵的颜色映射以**单字节字符**为键；想画实心块又想要准确颜色，
--    自己用 S.put(x, y, "█", 颜色) 铺更省事（框字符画也不需要额外映射）。
--
-- 10. 新卡带写在 build/carts/<id>/ 里（--new 默认就建在那儿）；
--     package/carts 只放"准备随发行版一起出"的卡带，别顺手复制过去。
-- ─────────────────────────────────────────────────────────────

local Game = require("game")
local Panel = require("panel")

-- 界面文案：中英各一列，取值一律走 L()。新增语言只需加一列。
-- 不要在代码里写死中文——语言由 phos.sys.language() 给出
local Text = {
  zh = { hud = "得分", paused = "暂停中", keys = "[%s] 动作   [%s] 暂停" },
  en = { hud = "SCORE", paused = "PAUSED", keys = "[%s] ACT   [%s] PAUSE" },
}
local function L() return Text[phos.sys.language()] or Text.zh end

local game          -- 「填」你的规则对象，见 game.lua
local cart = {}
local paused = false

function init()
  cart = phos.cart.info()      -- 标题/作者/版本以 manifest.lua 为唯一来源，不要在 Lua 里再抄一份
  game = Game.new()            -- 「填」换成你的初始化

  -- 「填」需要背景音乐时：phos.audio.music({ ... })；要读包内文本资源时：
  -- local rows = phos.assets.rows("assets/motd." .. phos.sys.language() .. ".txt")
end

function update(dt)
  -- 主机保留键（Esc 返回卡带架、F2 调试台）不在这里，卡带不用管
  if phos.input.pressed("start") then
    paused = not paused
    phos.audio.paused(paused)
  end
  if paused then return end

  -- 输入 → 意图：这里只回答"哪个键按下了"，能不能这么做由 game.lua 判定。
  -- 键名取虚拟手柄的抽象名；要写提示就用 phos.input.key_name() 换成键盘上真实的键
  if phos.input.pressed("left") then game:move(-1, 0) end    -- 「填」
  if phos.input.pressed("right") then game:move(1, 0) end    -- 「填」
  if phos.input.pressed("a") then game:act() end             -- 「填」

  local events = game:update(dt)        -- 「填」让规则推进一帧
  if events.tick then phos.audio.beep(880, 0.04, { wave = "square", volume = 0.2 }) end  -- 「填」
end

function draw()
  local C, S = phos.color, phos.screen
  local t = L()
  S.clear()

  -- 布局：**一律以可玩区为准**。playfield() 已经把侧栏算掉，
  -- 所以"铺满画面"的排版写它就不会被侧栏挡住（它每次都按当前侧栏宽度算）
  local px, py, pw, ph = S.playfield()

  -- 「填」把 game 的状态画出来。坐标相对可玩区左上角；
  -- 定宽的位置（侧栏、状态条）用 phos.text.fit() 裁剪，别让主机从右边硬切
  S.print(px + 1, py + 1, phos.text.fit(cart.name, pw - 2), C.yellow)
  S.print(px + 1, py + 3, t.hud .. "  " .. tostring(game.score), C.white)
  if paused then
    S.print(px + 1, py + ph - 2, t.paused, C.gray)
  end

  -- 「填」键位提示写键盘上真实的键，不要写手柄按钮名（主机没有手柄）
  S.print(px + 1, py + ph - 1,
          string.format(t.keys, phos.input.key_name("a"), phos.input.key_name("start")), C.green)

  Panel.draw(game, cart)     -- 侧栏；不想要就在 manifest 里删掉 sidebar 这一行
end

-- agent / 自测观察口：主机在 state.query 时会把这里返回的表一并带出。
-- 「填」把玩法的关键量放进来，agent 就不必从字符画面反推
function debug_state()
  return { paused = paused, score = game.score }
end

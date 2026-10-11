-- main.lua —— 图层示例：世界 / HUD / 浮窗各画一层。
--
-- 底层仍然是 phos.screen —— 与不分层的卡带写法完全一样；分层只在"HUD 与浮窗"上取用。
-- 层里的空白格是**透明**的，所以：
--   * HUD 只写字形、不给底色 → 字压在世界之上（世界照常可见）
--   * 浮窗先 clear 铺一块不透明底板，再画边框与文字 → 世界被挡住
-- 注意"铺底板"要自己动手：`frame` 只画边框，而卡带侧的界面样式默认**保留背景**
-- （见 core/ui.cpp 的 cart style：卡带的浮窗压在游戏画面上时不该糊成黑板）。
-- 显式铺底色的地方才真的不透，这一条与"只写字形就透出世界"是同一套规则的两面

local SIZE_W, SIZE_H = phos.screen.size()

local hud_layer, window_layer
local hud, window          -- 两块绑定到层的绘制区域
local cursor = { x = 40, y = 22 }
local window_open = true
local elapsed = 0

function init()
  -- 取用分层的全部成本：建层 + 把绘制区域锚定到层
  hud_layer = phos.layer.create("hud", { z = 20 })
  window_layer = phos.layer.create("overlay", { z = 30 })
  hud = phos.ui.region(0, 0, SIZE_W, SIZE_H, { layer = "hud" })
  window = phos.ui.region(24, 8, 32, 12, { layer = "overlay" })
end

local function move_cursor(dt, key, dx, dy)
  -- 按住越走越快：phos.input.duration 直接给出"按住多久"，卡带不必自己攒计时
  local held = phos.input.duration(key)
  local speed = 12 + math.min(1, held / 0.9) * 70
  cursor.x = math.max(1, math.min(SIZE_W - 2, cursor.x + dx * speed * dt))
  cursor.y = math.max(1, math.min(SIZE_H - 2, cursor.y + dy * speed * dt))
end

function update(dt)
  elapsed = elapsed + dt
  move_cursor(dt, "left", -1, 0)
  move_cursor(dt, "right", 1, 0)
  move_cursor(dt, "up", 0, -1)
  move_cursor(dt, "down", 0, 1)
  if phos.input.pressed("a") then window_open = not window_open end
  if phos.input.pressed("b") then hud_layer.visible = not hud_layer.visible end
end

local function draw_world()
  -- 世界写底层：不分层的卡带到这里为止就是全部
  phos.screen.clear(phos.color.dark_gray, phos.color.rgb(8, 10, 20))
  for i = 0, 60 do
    local x = (i * 7 + math.floor(elapsed * 6)) % SIZE_W
    local y = (i * 11) % SIZE_H
    phos.screen.put(x, y, ".", phos.color.dark_gray)
  end
  phos.screen.print(2, SIZE_H - 2, "WORLD LAYER", phos.color.green)
end

local function draw_hud()
  -- 层每帧由主机清成透明（与底层"每帧重画"同一心智），所以这里只画这一帧的内容：
  -- 写过的格才存在，其余照透下层
  hud:print(2, 1, "LAYERS DEMO", phos.color.yellow)
  hud:print(2, 2, string.format("A window %s   B hud %s   frame %d",
                                window_open and "ON " or "OFF",
                                hud_layer.visible and "ON " or "OFF", phos.sys.frame()),
            phos.color.cyan)
  local xoff, width, approx = phos.text.ink_box("@")
  hud:print(2, 3, string.format("ink_box('@') = %d..%d%s", xoff, xoff + width,
                                approx and " (approx)" or ""), phos.color.gray)
  -- 光标只有字形、不铺底：它压在世界上，而不是盖住世界。
  -- 坐标是连续量，落到格子上要取整（写屏接口只认整数格）
  hud:put(math.floor(cursor.x), math.floor(cursor.y), "@", phos.color.orange)
end

local function draw_window()
  -- 浮窗落在 overlay 层；`clear` 恒写底色 → 整块不透明，世界被挡住。
  -- 这正是"要遮住底下"的写法，与 HUD 的"透出世界"形成对照
  window:clear(phos.color.gray, phos.color.dark_gray)
  window:frame("LAYER WINDOW")
  window:print(2, 2, "opaque: world hidden", phos.color.white)
  window:print(2, 3, "z: " .. table.concat(phos.layer.order(), " < "), phos.color.gray)
  window:divider(4)
  window:print(2, 5, string.format("cursor %d,%d", math.floor(cursor.x), math.floor(cursor.y)),
               phos.color.cyan)
end

function draw()
  draw_world()
  if hud_layer.visible then draw_hud() end
  if window_open then draw_window() end
end

function debug_state()
  return {
    frame = phos.sys.frame(),
    window_open = window_open and 1 or 0,
    hud_visible = hud_layer.visible and 1 or 0,
    layer_count = #phos.layer.order(),
    cursor_x = math.floor(cursor.x),
    cursor_y = math.floor(cursor.y),
  }
end
